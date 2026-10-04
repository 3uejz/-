<script setup lang="ts">
import { ref, computed } from 'vue'
import type { GameState } from '../engine/state'
import { ACHIEVEMENTS } from '../content/achievements'
import { fmtMoney, calendar } from '../engine/time'
import { itemById } from '../content/items'
import { PROPERTY_INDEX } from '../content/properties'
import { STOCK_INDEX } from '../content/stocks'
import { jobById, SKILL_BY_NAME } from '../content/jobs'
import { TALENT_INDEX } from '../engine/legacy'

const props = defineProps<{ state: GameState }>()
const emit = defineEmits<{ (e: 'close'): void; (e: 'cmd', text: string): void }>()

const tab = ref<'attrs' | 'bag' | 'skills' | 'relations' | 'assets' | 'achv' | 'wishes'>('attrs')
const p = computed(() => props.state.player)
const c = computed(() => calendar(props.state.time))

const tabs = [
  { id: 'attrs', label: '状态' },
  { id: 'bag', label: '背包' },
  { id: 'skills', label: '技能' },
  { id: 'relations', label: '关系' },
  { id: 'assets', label: '资产' },
  { id: 'achv', label: '成就' },
  { id: 'wishes', label: '愿望' },
] as const

const achvByCat = computed(() => {
  const groups = new Map<string, { name: string; desc: string; done: boolean }[]>()
  for (const a of ACHIEVEMENTS) {
    const list = groups.get(a.category) ?? []
    list.push({ name: a.name, desc: a.desc, done: props.state.achievements.includes(a.id) })
    groups.set(a.category, list)
  }
  return groups
})

const catNames: Record<string, string> = {
  wealth: '财富', career: '事业', skill: '技能', social: '社交', family: '家庭', explore: '探索', fortune: '奇遇',
}
</script>

<template>
  <div class="overlay" @click.self="emit('close')">
    <div class="sheet">
      <div class="tabs">
        <button v-for="t in tabs" :key="t.id" :class="{ active: tab === t.id }" @click="tab = t.id">{{ t.label }}</button>
        <button class="close" @click="emit('close')">关闭</button>
      </div>

      <div class="body">
        <!-- 状态 -->
        <div v-if="tab === 'attrs'" class="grid2">
          <div>姓名：{{ p.name }}</div>
          <div>年龄：{{ c.age }} 岁（{{ p.gender === 'm' ? '男' : '女' }}）</div>
          <div>健康：{{ Math.round(p.attrs.health) }}</div>
          <div>体力：{{ Math.round(p.attrs.stamina) }}</div>
          <div>心情：{{ Math.round(p.attrs.mood) }}</div>
          <div>智力：{{ Math.round(p.attrs.intellect) }}</div>
          <div>魅力：{{ Math.round(p.attrs.charm) }}</div>
          <div>饱食：{{ Math.round(p.attrs.satiety) }}</div>
          <div>清洁：{{ Math.round(p.attrs.hygiene) }}</div>
          <div>声望：{{ p.reputation }}｜信用：{{ p.credit }}</div>
          <div>职业：{{ p.job ? jobById(p.job.jobId).title : '无业' }}</div>
          <div>学历：{{ p.education }}</div>
          <div v-if="p.jailDaysLeft > 0">服刑中：剩余 {{ p.jailDaysLeft }} 天</div>
          <div>天赋：{{ p.talents.talents.map((t) => TALENT_INDEX.get(t)?.name).join('、') || '无' }}</div>
        </div>

        <!-- 背包 -->
        <div v-if="tab === 'bag'">
          <div v-if="p.inventory.length === 0" class="empty">背包空空如也。</div>
          <div v-for="e in p.inventory" :key="e.itemId" class="line">
            <span>{{ itemById(e.itemId).name }} ×{{ e.count }}</span>
            <span class="dim">{{ itemById(e.itemId).desc }}{{ e.expiryDays !== undefined ? `｜保质期剩${e.expiryDays}天` : '' }}</span>
          </div>
        </div>

        <!-- 技能 -->
        <div v-if="tab === 'skills'">
          <div v-if="Object.keys(p.skills).length === 0" class="empty">还没有任何技能，试试「学习 编程」。</div>
          <div v-for="(s, id) in p.skills" :key="id" class="line">
            <span>{{ SKILL_BY_NAME.get(id)?.name ?? id }}</span>
            <div class="skill-track"><div class="skill-fill" :style="{ width: (s.level * 10) + '%' }" /></div>
            <span class="dim">Lv.{{ s.level }}（{{ s.exp }} exp）</span>
          </div>
          <div v-if="p.licenses.length > 0" class="line">证书：{{ p.licenses.join('、') }}</div>
        </div>

        <!-- 关系 -->
        <div v-if="tab === 'relations'">
          <div v-for="npc in state.npcs" :key="npc.id" class="line">
            <span :class="{ dead: !npc.alive }">{{ npc.name }}</span>
            <span class="dim">{{ npc.alive ? `关系 ${npc.relationship}｜${npc.personality.join('·')}` : '已故' }}</span>
          </div>
        </div>

        <!-- 资产 -->
        <div v-if="tab === 'assets'" class="grid2">
          <div>现金：{{ fmtMoney(p.money) }}</div>
          <div>存款：{{ fmtMoney(p.bank) }}</div>
          <div v-if="p.depositDue">定期：{{ fmtMoney(p.depositDue.amount) }}</div>
          <div v-if="p.loan">贷款：{{ fmtMoney(p.loan.principal) }}</div>
          <div>房产：{{ p.estate.propertyId ? PROPERTY_INDEX.get(p.estate.propertyId)?.name : '无' }}</div>
          <div>租住：{{ p.estate.rentedId ? PROPERTY_INDEX.get(p.estate.rentedId)?.name : '无' }}</div>
          <div>车辆：{{ p.vehicle.vehicleItemId ?? '无' }}</div>
          <div>店铺：{{ p.shop?.shopId ?? '无' }}</div>
          <div class="span2">
            股票：
            <span v-for="s in p.stocks" :key="s.stockId" class="stock">
              {{ STOCK_INDEX.get(s.stockId)?.name ?? s.stockId }} {{ s.shares }}股（成本 {{ s.avgCost.toFixed(2) }}）
            </span>
            <span v-if="p.stocks.length === 0" class="dim">无持仓</span>
          </div>
        </div>

        <!-- 成就 -->
        <div v-if="tab === 'achv'">
          <div class="dim head">已解锁 {{ state.achievements.length }} / {{ ACHIEVEMENTS.length }}（累计 {{ state.legacy.totalAchievements.length }} 跨周目）</div>
          <div v-for="[cat, list] in achvByCat" :key="cat" class="achv-cat">
            <div class="title">{{ catNames[cat] }}</div>
            <div v-for="a in list" :key="a.name" class="line" :class="{ done: a.done }">
              <span>{{ a.done ? '★' : '☆' }} {{ a.name }}</span>
              <span class="dim">{{ a.desc }}</span>
            </div>
          </div>
        </div>

        <!-- 愿望 -->
        <div v-if="tab === 'wishes'">
          <div v-if="p.wishes.length === 0" class="empty">还没有人生愿望。用「愿望 攒钱 100000」立下目标。</div>
          <div v-for="w in p.wishes" :key="w.id" class="line" :class="{ done: w.done }">
            <span>{{ w.done ? '✓' : '◇' }} {{ w.label }}</span>
            <span class="dim">进度 {{ Math.min(100, Math.round((w.progress / w.target) * 100)) }}%</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed; inset: 0; background: rgba(0,0,0,0.55);
  display: flex; align-items: flex-end; justify-content: center; z-index: 50;
}
.sheet {
  width: 100%; max-width: 560px; max-height: 78vh;
  background: var(--bg-panel); border-radius: 16px 16px 0 0;
  display: flex; flex-direction: column;
}
.tabs { display: flex; gap: 4px; padding: 10px 12px 0; overflow-x: auto; }
.tabs button { font-size: 12px; padding: 6px 10px; background: transparent; color: var(--fg-dim); }
.tabs button.active { color: var(--fg); background: var(--bg-input); }
.tabs .close { margin-left: auto; color: var(--danger); }
.body { padding: 12px 16px 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 6px; }
.grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; font-size: 13.5px; }
.span2 { grid-column: span 2; }
.line { display: flex; justify-content: space-between; gap: 10px; font-size: 13.5px; padding: 4px 0; border-bottom: 1px dashed #2c2f55; }
.line.done { color: var(--success); }
.line .dead { color: var(--fg-dim); text-decoration: line-through; }
.dim { color: var(--fg-dim); font-size: 12px; }
.empty { color: var(--fg-dim); padding: 20px 0; text-align: center; }
.title { color: var(--accent); font-size: 13px; margin: 8px 0 2px; }
.head { margin-bottom: 4px; }
.skill-track { flex: 1; height: 6px; background: #2c2f55; border-radius: 3px; margin: 0 8px; }
.skill-fill { height: 100%; background: var(--accent); border-radius: 3px; }
.stock { margin-right: 10px; font-size: 12.5px; }
.achv-cat .line { flex-direction: column; gap: 2px; }
</style>
