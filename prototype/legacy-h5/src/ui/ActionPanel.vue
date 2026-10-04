<script setup lang="ts">
import { computed } from 'vue'
import type { GameState } from '../engine/state'
import { LOCATION_INDEX } from '../content/locations'

const props = defineProps<{ state: GameState }>()
const emit = defineEmits<{ (e: 'cmd', text: string): void }>()

const loc = computed(() => LOCATION_INDEX.get(props.state.player.locationId))

const nearby = computed(() => {
  const current = props.state.player.locationId
  return [...LOCATION_INDEX.values()]
    .filter((l) => l.id !== current && l.id !== 'jail')
    .slice(0, 8)
})

const contextActions = computed(() => loc.value?.actions ?? [])
</script>

<template>
  <div class="panel">
    <div class="section">
      <div class="title">当前地点：{{ loc?.name }}</div>
      <div class="desc">{{ loc?.desc }}</div>
      <div class="actions">
        <button v-for="a in contextActions" :key="a" class="ctx" @click="emit('cmd', actionText(a))">{{ a }}</button>
      </div>
    </div>
    <div class="section">
      <div class="title">前往</div>
      <div class="places">
        <button v-for="pl in nearby" :key="pl.id" class="place" @click="emit('cmd', '去 ' + pl.name)">
          {{ pl.name }}
        </button>
      </div>
    </div>
  </div>
</template>

<script lang="ts">
function actionText(a: string): string {
  const map: Record<string, string> = {
    work: '工作', overtime: '加班', resign: '辞职', jobHunt: '找工作',
    sleep: '睡觉', cook: '做饭', decorate: '装修',
    study: '学习', read: '看书', exercise: '锻炼', attendSchool: '上学', takeExam: '考试',
    deposit: '存款', withdraw: '取款', loan: '贷款', repay: '还款',
    buyStock: '买股票', sellStock: '卖股票', buyLottery: '买彩票',
    rent: '租房', buyHouse: '买房', sellHouse: '卖房',
    openShop: '开店', stroll: '散步', treat: '看病', checkup: '体检',
    buy: '买', eat: '吃', chat: '聊天', surf: '上网', watchMovie: '看电影',
    sing: '唱歌', travel: '旅游', bus: '坐公交', refuel: '加油', surrender: '自首', reflect: '反思',
    marry: '结婚', divorce: '离婚',
  }
  return map[a] ?? a
}
export default { methods: {} }
</script>

<style scoped>
.panel {
  background: var(--bg-panel);
  border-top: 1px solid #2c2f55;
  padding: 8px 12px;
  display: flex;
  gap: 14px;
  overflow-x: auto;
}
.section { min-width: 140px; }
.title { font-size: 12px; color: var(--fg-dim); margin-bottom: 6px; }
.desc { font-size: 11px; color: var(--fg-dim); opacity: 0.7; margin-bottom: 6px; max-width: 200px; }
.actions, .places { display: flex; gap: 6px; flex-wrap: wrap; }
.ctx, .place { padding: 5px 10px; font-size: 12px; }
.place { color: var(--fg-dim); }
</style>
