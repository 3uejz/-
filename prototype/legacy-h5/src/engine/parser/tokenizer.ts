// Tokenizer: segments free-form Chinese input against the content vocabulary.
// Strategy: strip whitespace, longest-match against the merged word index.

export interface WordTarget {
  type: 'location' | 'item' | 'npc' | 'skill' | 'job' | 'stock' | 'property' | 'license' | 'education' | 'talent' | 'wishKind' | 'stat'
  id: string
}

export interface WordIndex {
  words: Map<string, WordTarget>
  maxLen: number
}

export interface Token {
  kind: 'verb' | 'word' | 'number' | 'text'
  value: string
  target?: WordTarget
}

/** Greedy segmentation of the remainder after the verb is consumed. */
export function segmentRemainder(remainder: string, index: WordIndex): Token[] {
  const tokens: Token[] = []
  let pos = 0
  while (pos < remainder.length) {
    const ch = remainder[pos]
    // Numbers (Arabic numerals).
    if (/[0-9]/.test(ch)) {
      let end = pos
      while (end < remainder.length && /[0-9]/.test(remainder[end])) end++
      tokens.push({ kind: 'number', value: remainder.slice(pos, end) })
      pos = end
      continue
    }
    // Chinese numerals up to 四位数词.
    const cnNumMatch = /^(十|百|千|[一二两三四五六七八九]+(十|百|千)?[一二三四五六七八九]?)/.exec(remainder.slice(pos))
    if (cnNumMatch && cnNumMatch[0]) {
      const n = parseCnNumber(cnNumMatch[0])
      if (n !== null) {
        tokens.push({ kind: 'number', value: String(n) })
        pos += cnNumMatch[0].length
        continue
      }
    }
    // Longest vocabulary match.
    let matched = false
    const maxTry = Math.min(index.maxLen, remainder.length - pos)
    for (let len = maxTry; len >= 1; len--) {
      const sub = remainder.slice(pos, pos + len)
      const target = index.words.get(sub)
      if (target) {
        tokens.push({ kind: 'word', value: sub, target })
        pos += len
        matched = true
        break
      }
    }
    if (!matched) {
      tokens.push({ kind: 'text', value: ch })
      pos += 1
    }
  }
  return tokens
}

export function parseCnNumber(text: string): number | null {
  const digits: Record<string, number> = { 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 }
  if (text === '十') return 10
  if (text === '百') return 100
  if (text === '千') return 1000
  let total = 0
  let current = 0
  for (const ch of text) {
    if (digits[ch] !== undefined) {
      current = digits[ch]
    } else if (ch === '十') {
      total += (current || 1) * 10
      current = 0
    } else if (ch === '百') {
      total += (current || 1) * 100
      current = 0
    } else if (ch === '千') {
      total += (current || 1) * 1000
      current = 0
    } else {
      return null
    }
  }
  return total + current || (total > 0 ? total : null)
}

export function levenshtein(a: string, b: string): number {
  const m = a.length
  const n = b.length
  const dp: number[][] = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0))
  for (let i = 0; i <= m; i++) dp[i][0] = i
  for (let j = 0; j <= n; j++) dp[0][j] = j
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      )
    }
  }
  return dp[m][n]
}

/** Find close vocabulary words for fuzzy suggestions. */
export function fuzzySuggest(input: string, index: WordIndex, max = 3): string[] {
  const scored: { word: string; d: number }[] = []
  for (const word of index.words.keys()) {
    const d = levenshtein(input, word)
    if (d <= Math.max(1, Math.floor(word.length / 3))) scored.push({ word, d })
  }
  return scored.sort((a, b) => a.d - b.d).slice(0, max).map((x) => x.word)
}
