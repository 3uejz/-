<script setup lang="ts">
import { computed } from 'vue'
import type { GameState } from '../engine/state'
import { calendar, fmtMoney } from '../engine/time'
import { LOCATION_INDEX } from '../content/locations'
import { jobTitle } from '../content/jobs'

const props = defineProps<{ state: GameState }>()

const c = computed(() => calendar(props.state.time))
const locName = computed(() => LOCATION_INDEX.get(props.state.player.locationId)?.name ?? '未知')
const p = computed(() => props.state.player)

const weatherIcon: Record<string, string> = { sunny: '晴', rain: '雨', snow: '雪', heatwave: '热', coldwave: '寒' }

const attrBars = computed(() => [
  { key: 'health', label: '健康', value: p.value.attrs.health },
  { key: 'stamina', label: '体力', value: p.value.attrs.stamina },
  { key: 'mood', label: '心情', value: p.value.attrs.mood },
  { key: 'satiety', label: '饱食', value: p.value.attrs.satiety },
])
</script>

<template>
  <header class="status">
    <div class="row line1">
      <span class="time">{{ c.year }}年{{ c.month }}月{{ c.day }}日 {{ String(c.hour).padStart(2, '0') }}:{{ String(c.minute).padStart(2, '0') }}</span>
      <span class="weather">{{ weatherIcon[state.weather] }}</span>
      <span class="money">{{ fmtMoney(p.money) }}</span>
    </div>
    <div class="row line2">
      <span class="age">{{ c.age }}岁</span>
      <span class="job">{{ jobTitle(p.job?.jobId ?? null) }}</span>
      <span class="loc">@{{ locName }}</span>
      <span v-if="p.jailDaysLeft > 0" class="jail">刑期{{ p.jailDaysLeft }}天</span>
    </div>
    <div class="bars">
      <div v-for="bar in attrBars" :key="bar.key" class="bar">
        <span class="bar-label">{{ bar.label }}</span>
        <div class="bar-track">
          <div class="bar-fill" :class="{ low: bar.value < 25 }" :style="{ width: bar.value + '%' }" />
        </div>
      </div>
    </div>
  </header>
</template>

<style scoped>
.status {
  background: var(--bg-panel);
  padding: 8px 12px 10px;
  border-bottom: 1px solid #2c2f55;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.row { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.line1 { font-size: 13px; color: var(--fg-dim); }
.time { color: var(--fg); font-variant-numeric: tabular-nums; }
.money { color: var(--accent-2); font-weight: 600; margin-left: auto; }
.line2 { font-size: 12px; color: var(--fg-dim); gap: 8px; }
.jail { color: var(--danger); }
.bars { display: flex; gap: 8px; }
.bar { flex: 1; display: flex; align-items: center; gap: 4px; }
.bar-label { font-size: 11px; color: var(--fg-dim); white-space: nowrap; }
.bar-track { flex: 1; height: 6px; background: #2c2f55; border-radius: 3px; overflow: hidden; }
.bar-fill { height: 100%; background: var(--success); transition: width 0.3s; }
.bar-fill.low { background: var(--danger); }
</style>
