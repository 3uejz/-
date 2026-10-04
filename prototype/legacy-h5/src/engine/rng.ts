// Deterministic PRNG (mulberry32) - seedable, serializable

export class RNG {
  private s: number

  constructor(seed: number) {
    this.s = seed >>> 0
  }

  next(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0
    let t = this.s
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }

  int(min: number, max: number): number {
    return Math.floor(this.next() * (max - min + 1)) + min
  }

  float(min: number, max: number): number {
    return this.next() * (max - min) + min
  }

  pick<T>(arr: readonly T[]): T {
    return arr[Math.floor(this.next() * arr.length)]
  }

  chance(p: number): boolean {
    return this.next() < p
  }

  /** Weighted pick: entries with weight <= 0 are skipped. */
  weighted<T>(items: T[], weightOf: (item: T) => number): T | undefined {
    const total = items.reduce((sum, it) => sum + Math.max(0, weightOf(it)), 0)
    if (total <= 0) return undefined
    let roll = this.next() * total
    for (const it of items) {
      roll -= Math.max(0, weightOf(it))
      if (roll <= 0) return it
    }
    return items[items.length - 1]
  }

  get state(): number {
    return this.s
  }
}
