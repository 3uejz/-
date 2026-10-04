<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import { Game } from './engine/Game'
import type { GameState } from './engine/state'
import { loadFromStorage, clearStorage, loadLegacy } from './engine/save'
import { TALENTS } from './engine/legacy'
import StatusBar from './ui/StatusBar.vue'
import MessageLog from './ui/MessageLog.vue'
import InputBar from './ui/InputBar.vue'
import ActionPanel from './ui/ActionPanel.vue'
import OverviewTabs from './ui/OverviewTabs.vue'

type Screen = 'boot' | 'newgame' | 'playing'

const screen = ref<Screen>('boot')
const game = ref<Game | null>(null)
const state = ref<GameState | null>(null)
const showOverview = ref(false)
const hasSave = ref(false)
const legacyInfo = ref(loadLegacy())

// New game form
const newName = ref('')
const newGender = ref<'m' | 'f'>('m')
const selectedTalents = ref<string[]>([])
const legacyPoints = computed(() => legacyInfo.value?.legacyPoints ?? 0)

onMounted(() => {
  hasSave.value = loadFromStorage() !== null
  screen.value = hasSave.value ? 'boot' : 'newgame'
})

function startNewGame(): void {
  const g = Game.newGame({
    name: newName.value.trim() || '无名氏',
    gender: newGender.value,
    talents: selectedTalents.value,
    startBonusMoney: selectedTalents.value.includes('tal_money') ? 20000 : 0,
  })
  game.value = g
  state.value = reactive(g.state) as GameState
  screen.value = 'playing'
}

function continueGame(): void {
  const g = Game.continueGame()
  if (!g) return
  game.value = g
  state.value = reactive(g.state) as GameState
  screen.value = 'playing'
}

function abandonSave(): void {
  clearStorage()
  hasSave.value = false
  screen.value = 'newgame'
}

function submit(text: string): void {
  const g = game.value
  if (!g) return
  g.submitCommand(text)
}

function fillText(text: string): void {
  inputBar.value?.fill(text)
}

const inputBar = ref<InstanceType<typeof InputBar> | null>(null)

function toggleOverview(): void {
  showOverview.value = !showOverview.value
}

function chooseEventOption(index: number): void {
  game.value?.chooseEvent(index)
}

function restartRun(): void {
  clearStorage()
  const prev = legacyInfo.value
  legacyInfo.value = loadLegacy() ?? prev
  hasSave.value = false
  game.value = null
  state.value = null
  screen.value = 'newgame'
}

function talentToggle(id: string): void {
  const list = selectedTalents.value
  const idx = list.indexOf(id)
  if (idx >= 0) list.splice(idx, 1)
  else if (list.length < 2) list.push(id)
}
</script>

<template>
  <div class="app">
    <!-- 开局选择 -->
    <div v-if="screen === 'boot'" class="modal-full">
      <div class="boot-card">
        <h1>浮生录</h1>
        <p class="tagline">一座城市，一生故事。文字人生沙盒。</p>
        <div class="boot-actions">
          <button class="primary big" @click="continueGame">继续上一次的人生</button>
          <button class="big" @click="abandonSave">重新开档</button>
        </div>
        <p v-if="legacyInfo" class="legacy">
          传承：累计成就 {{ legacyInfo.totalAchievements.length }} 项 · 传承点 {{ legacyInfo.legacyPoints }} · 已历 {{ legacyInfo.runsCompleted }} 世
        </p>
      </div>
    </div>

    <!-- 新档设置 -->
    <div v-else-if="screen === 'newgame'" class="modal-full">
      <div class="boot-card">
        <h1>浮生录</h1>
        <p class="tagline">设定你的起点</p>
        <div class="form">
          <input v-model="newName" maxlength="12" placeholder="你的名字" />
          <div class="gender">
            <button :class="{ active: newGender === 'm' }" @click="newGender = 'm'">男</button>
            <button :class="{ active: newGender === 'f' }" @click="newGender = 'f'">女</button>
          </div>
        </div>
        <div v-if="legacyPoints > 0" class="talents">
          <div class="talent-title">传承天赋（选 2 项 · 剩余 {{ Math.max(0, 2 - selectedTalents.length) }}）</div>
          <button
            v-for="t in TALENTS"
            :key="t.id"
            class="talent"
            :class="{ on: selectedTalents.includes(t.id) }"
            :disabled="t.cost > legacyPoints && !selectedTalents.includes(t.id)"
            @click="talentToggle(t.id)"
          >
            <b>{{ t.name }}</b>（{{ t.cost }}点）<span>{{ t.desc }}</span>
          </button>
        </div>
        <button class="primary big" @click="startNewGame">开始人生</button>
        <p v-if="legacyInfo" class="legacy">传承点：{{ legacyPoints }}（完成成就积累，死亡后继承）</p>
      </div>
    </div>

    <!-- 游戏主界面 -->
    <template v-else-if="screen === 'playing' && state">
      <StatusBar :state="state" />
      <MessageLog :messages="state.messages" @fill="fillText" />

      <!-- 事件选项 -->
      <div v-if="state.activeEvent" class="event-bar">
        <div class="event-title">事件抉择</div>
        <div class="event-options">
          <button v-for="(opt, i) in state.activeEvent.options" :key="i" class="primary" @click="chooseEventOption(i)">
            {{ opt.label }}
          </button>
        </div>
      </div>

      <ActionPanel :state="state" @cmd="submit" />
      <InputBar ref="inputBar" :disabled="!!state.activeEvent || !state.player.alive" @submit="submit" />

      <button class="fab" @click="toggleOverview">总览</button>

      <OverviewTabs v-if="showOverview" :state="state" @close="showOverview = false" />

      <!-- 死亡结算 -->
      <div v-if="state.finished" class="modal-full">
        <div class="boot-card death">
          <h1>人生落幕</h1>
          <pre class="summary">{{ game?.lifeSummary() }}</pre>
          <div class="legacy-gain">
            本世成就 {{ state.achievements.length }} 项 → 传承点已累积，来世更强。
          </div>
          <button class="primary big" @click="restartRun">轮回 · 开启新人生</button>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.app {
  height: 100%;
  display: flex;
  flex-direction: column;
  max-width: 620px;
  margin: 0 auto;
  position: relative;
  background: var(--bg);
}
.modal-full {
  position: fixed; inset: 0; z-index: 100;
  background: rgba(10, 11, 24, 0.92);
  display: flex; align-items: center; justify-content: center;
  padding: 20px;
}
.boot-card {
  width: 100%; max-width: 420px; max-height: 90vh; overflow-y: auto;
  background: var(--bg-panel); border-radius: 18px; padding: 28px 24px;
  display: flex; flex-direction: column; gap: 16px; text-align: center;
}
.boot-card h1 { font-size: 30px; letter-spacing: 8px; color: var(--accent); }
.tagline { color: var(--fg-dim); font-size: 13px; }
.boot-actions { display: flex; flex-direction: column; gap: 10px; }
.big { padding: 13px; font-size: 15px; }
.legacy { font-size: 12px; color: var(--fg-dim); }
.form { display: flex; gap: 8px; }
.form input { flex: 1; text-align: center; }
.gender { display: flex; gap: 4px; }
.gender button { width: 52px; }
.gender button.active { background: var(--accent); color: #fff; }
.talents { text-align: left; display: flex; flex-direction: column; gap: 6px; }
.talent-title { font-size: 12px; color: var(--fg-dim); }
.talent {
  display: flex; flex-direction: column; align-items: flex-start; gap: 2px;
  text-align: left; font-size: 12px; padding: 8px 10px; background: var(--bg-input);
}
.talent.on { outline: 2px solid var(--accent-2); }
.talent span { color: var(--fg-dim); }
.talent:disabled { opacity: 0.4; }
.event-bar {
  background: #2d2417; border-top: 1px solid var(--event);
  padding: 8px 12px;
}
.event-title { font-size: 12px; color: var(--event); margin-bottom: 6px; }
.event-options { display: flex; gap: 8px; flex-wrap: wrap; }
.fab {
  position: fixed; right: 14px; bottom: 118px; z-index: 40;
  border-radius: 50%; width: 52px; height: 52px; font-size: 12px;
  background: var(--accent); color: #fff; box-shadow: 0 4px 14px rgba(0,0,0,0.4);
}
.death h1 { color: var(--danger); letter-spacing: 4px; }
.summary {
  text-align: left; font-size: 13px; line-height: 1.7; white-space: pre-wrap;
  background: var(--bg); border-radius: 10px; padding: 14px; font-family: inherit;
}
.legacy-gain { font-size: 12px; color: var(--accent-2); }
</style>
