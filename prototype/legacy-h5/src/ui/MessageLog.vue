<script setup lang="ts">
import { ref, watch, nextTick } from 'vue'
import type { Message } from '../engine/state'

const props = defineProps<{ messages: Message[] }>()
const emit = defineEmits<{ (e: 'fill', text: string): void }>()

const container = ref<HTMLElement | null>(null)

watch(
  () => props.messages.length,
  async () => {
    await nextTick()
    container.value?.scrollTo({ top: container.value.scrollHeight, behavior: 'smooth' })
  },
)

const kindClass: Record<Message['kind'], string> = {
  system: 'msg-system',
  narrative: 'msg-narrative',
  event: 'msg-event',
  result: 'msg-result',
  warning: 'msg-warning',
}

/** Convert 「名字」 quoted tokens into clickable fill buttons. */
function parts(text: string): { t: string; clickable: boolean }[] {
  return text.split(/(「[^」]+」)/g).filter(Boolean).map((seg) => ({
    t: seg,
    clickable: seg.startsWith('「') && seg.endsWith('」') && seg.length >= 3,
  }))
}
</script>

<template>
  <div ref="container" class="log">
    <div
      v-for="m in messages"
      :key="m.id"
      class="msg"
      :class="kindClass[m.kind]"
    >
      <template v-for="(part, i) in parts(m.text)" :key="i">
        <button v-if="part.clickable" class="fill-btn" @click="emit('fill', part.t.slice(1, -1))">{{ part.t }}</button>
        <template v-else>{{ part.t }}</template>
      </template>
    </div>
  </div>
</template>

<style scoped>
.log {
  flex: 1;
  overflow-y: auto;
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.msg { line-height: 1.65; white-space: pre-wrap; word-break: break-word; font-size: 14.5px; }
.msg-system { color: var(--fg-dim); font-size: 13px; border-left: 3px solid #3a3f77; padding-left: 8px; }
.msg-narrative { color: var(--fg); }
.msg-event { color: var(--event); }
.msg-result { color: var(--accent); }
.msg-warning { color: var(--danger); }
.fill-btn {
  display: inline;
  padding: 0 2px;
  background: transparent;
  color: var(--accent-2);
  border-bottom: 1px dashed var(--accent-2);
  border-radius: 0;
  font-size: inherit;
  line-height: inherit;
}
.fill-btn:hover { background: transparent; color: var(--fg); }
</style>
