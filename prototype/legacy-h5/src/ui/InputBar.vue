<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { completionCandidates } from '../engine/parser/resolver'

const props = defineProps<{ disabled: boolean }>()
const emit = defineEmits<{ (e: 'submit', text: string): void }>()

const input = ref('')
const history = ref<string[]>([])
const historyIdx = ref(-1)
const inputEl = ref<HTMLInputElement | null>(null)

const candidates = computed(() => (input.value.trim() ? completionCandidates(input.value.trim()) : []))

function submit() {
  const text = input.value.trim()
  if (!text || props.disabled) return
  history.value.unshift(text)
  if (history.value.length > 20) history.value.pop()
  historyIdx.value = -1
  input.value = ''
  emit('submit', text)
}

function onKey(e: KeyboardEvent) {
  if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
    if (history.value.length === 0) return
    e.preventDefault()
    if (e.key === 'ArrowUp') {
      historyIdx.value = Math.min(history.value.length - 1, historyIdx.value + 1)
    } else {
      historyIdx.value = Math.max(-1, historyIdx.value - 1)
    }
    input.value = historyIdx.value >= 0 ? history.value[historyIdx.value] : ''
  } else if (e.key === 'Tab') {
    e.preventDefault()
    if (candidates.value.length > 0) {
      input.value = candidates.value[0] + ' '
    }
  }
}

function fill(text: string) {
  input.value = text + ' '
  inputEl.value?.focus()
}

function quick(text: string) {
  if (props.disabled) return
  emit('submit', text)
}

defineExpose({ fill, focus: () => inputEl.value?.focus() })

watch(() => props.disabled, (d) => { if (!d) inputEl.value?.focus() })
</script>

<template>
  <div class="input-area">
    <div v-if="candidates.length > 0" class="candidates">
      <button v-for="cand in candidates" :key="cand" class="cand" @click="input = cand + ' '; inputEl?.focus()">
        {{ cand }}
      </button>
    </div>
    <div class="quick">
      <button v-for="q in ['查看 状态', '查看 背包', '查看 地图', '找工作', '吃饭', '睡觉']" :key="q" @click="quick(q)">{{ q }}</button>
    </div>
    <div class="row">
      <input
        ref="inputEl"
        v-model="input"
        class="cmd"
        :disabled="disabled"
        placeholder="输入你想做的事…（如：去 公园 / 买 苹果 3 / 学习 编程 2）"
        @keydown="onKey"
        @keyup.enter="submit"
      />
      <button class="primary send" :disabled="disabled" @click="submit">行动</button>
    </div>
  </div>
</template>

<style scoped>
.input-area {
  background: var(--bg-panel);
  border-top: 1px solid #2c2f55;
  padding: 8px 12px 10px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.candidates { display: flex; gap: 6px; flex-wrap: wrap; }
.cand { padding: 4px 10px; font-size: 12px; background: #2c2f55; }
.quick { display: flex; gap: 6px; overflow-x: auto; }
.quick button { padding: 5px 10px; font-size: 12px; white-space: nowrap; color: var(--fg-dim); }
.row { display: flex; gap: 8px; }
.cmd { flex: 1; }
.send { min-width: 72px; }
</style>
