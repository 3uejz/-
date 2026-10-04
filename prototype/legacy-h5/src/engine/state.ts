// Core type definitions for the game world.
// One month = 30 days, one year = 360 days. All time is stored as absolute minutes.

export const MINUTES_PER_DAY = 1440
export const DAYS_PER_MONTH = 30
export const DAYS_PER_YEAR = 360
export const MINUTES_PER_YEAR = MINUTES_PER_DAY * DAYS_PER_YEAR
export const START_YEAR = 2026
export const ADULT_AGE = 18
export const LIFESPAN_MAX = 90

export interface WorldTime {
  /** Absolute minutes since character birth (age ADULT_AGE start point). */
  total: number
}

export type Season = 'spring' | 'summer' | 'autumn' | 'winter'
export type WeatherKind = 'sunny' | 'rain' | 'snow' | 'heatwave' | 'coldwave'

export interface CalendarInfo {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  weekday: number
  age: number
  season: Season
}

export interface Attrs {
  health: number
  stamina: number
  mood: number
  intellect: number
  charm: number
  satiety: number
  hygiene: number
}

export type AttrKey = keyof Attrs

export interface SkillState {
  level: number
  exp: number
}

export interface JobState {
  jobId: string
  /** Consecutive well-performed work days in current year, drives promotion. */
  performance: number
  yearsHeld: number
}

export interface InventoryEntry {
  itemId: string
  count: number
  /** Remaining days before expiry, if applicable. */
  expiryDays?: number
}

export interface EstateState {
  propertyId: string | null
  rentedId: string | null
  /** Days of rent arrears. */
  rentArrears: number
}

export interface VehicleState {
  vehicleItemId: string | null
}

export interface FamilyState {
  spouseNpcId: string | null
  children: { npcId: string; age: number }[]
}

export interface StockPosition {
  stockId: string
  shares: number
  avgCost: number
}

export interface LoanState {
  principal: number
  dailyRate: number
  overdueDays: number
}

export interface CriminalRecord {
  year: number
  crime: string
  penalty: string
}

export type WishKind = 'money' | 'skill' | 'job' | 'family' | 'estate' | 'reputation' | 'age' | 'business'

export interface Wish {
  id: string
  kind: WishKind
  label: string
  target: number
  progress: number
  done: boolean
}

export interface TalentState {
  /** Legacy talents carried into this run, max 2. */
  talents: string[]
  startBonusMoney: number
}

export interface LifeStats {
  totalEarned: number
  totalSpent: number
  crimes: number
  daysInJail: number
  milestones: { year: number; text: string }[]
  jobsHeld: string[]
  coursesLearned: string[]
}

export interface NPCScheduleSlot {
  /** Hour range [from, to) and location id. */
  from: number
  to: number
  locationId: string
}

export interface NPC {
  id: string
  name: string
  gender: 'm' | 'f'
  age: number
  jobId: string | null
  personality: string[]
  schedule: NPCScheduleSlot[]
  currentLocationId: string
  relationship: number
  homeId: string
  alive: boolean
  spouseNpcId: string | null
  childrenCount: number
}

export interface StockState {
  stockId: string
  price: number
  history: number[]
}

export interface MarketState {
  /** Multiplier per item category, e.g. { food: 1.05, ... }. */
  categoryFactor: Record<string, number>
  inflation: number
  propertyIndex: number
}

export interface ActiveEventOption {
  label: string
  outcomeText: string
  effects: EventEffect[]
}

export interface EventEffect {
  kind: 'attrs' | 'money' | 'relationship' | 'reputation' | 'item' | 'marketFactor' | 'weather'
  target?: string
  value: number
}

export interface ActiveEvent {
  eventId: string
  text: string
  options: ActiveEventOption[]
}

export interface Message {
  id: number
  kind: 'system' | 'narrative' | 'event' | 'result' | 'warning'
  text: string
  day: number
}

export interface GameState {
  version: number
  seed: number
  rngState: number
  time: WorldTime
  weather: WeatherKind
  weatherDaysLeft: number
  player: {
    name: string
    gender: 'm' | 'f'
    attrs: Attrs
    money: number
    bank: number
    depositDue?: { amount: number; dueTotal: number }
    loan: LoanState | null
    credit: number
    job: JobState | null
    skills: Record<string, SkillState>
    licenses: string[]
    education: string
    educationProgress: number
    inventory: InventoryEntry[]
    estate: EstateState
    vehicle: VehicleState
    family: FamilyState
    stocks: StockPosition[]
    shop: ShopState | null
    reputation: number
    locationId: string
    jailDaysLeft: number
    wishes: Wish[]
    talents: TalentState
    stats: LifeStats
    alive: boolean
    deathCause: string | null
  }
  npcs: NPC[]
  market: MarketState
  stocks: StockState[]
  activeEvent: ActiveEvent | null
  eventCooldowns: Record<string, number>
  achievements: string[]
  messages: Message[]
  nextMessageId: number
  /** Transient: minutes the current action will consume, applied by Game after verb run. */
  pendingMinutes: number
  /** Transient: verb requested an explicit save. */
  pendingSave: boolean
  /** Legacy meta persisted across runs. */
  legacy: {
    totalAchievements: string[]
    legacyPoints: number
    runsCompleted: number
  }
  finished: boolean
}

export interface ShopState {
  shopId: string
  typeId: string
  inventory: { itemId: string; count: number; costEach: number }[]
  priceFactor: number
  employees: string[]
  reputation: number
  dailyRevenue: number
  open: boolean
}

export interface NewGameOptions {
  name: string
  gender: 'm' | 'f'
  talents: string[]
  startBonusMoney: number
  seed?: number
}
