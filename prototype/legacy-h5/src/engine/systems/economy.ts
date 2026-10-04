import type { GameState } from '../state'
import type { RNG } from '../rng'
import { ITEM_INDEX } from '../../content/items'
import { STOCKS } from '../../content/stocks'

export function marketFactor(state: GameState, category: string): number {
  return state.market.categoryFactor[category] ?? 1
}

/** Current sell price of an item, adjusted by category factor. */
export function itemPrice(state: GameState, itemId: string): number {
  const item = ITEM_INDEX.get(itemId)
  if (!item) return 0
  return Math.max(1, Math.round(item.price * marketFactor(state, item.category)))
}

/** Daily drift of all market factors toward 1 and inflation decay. */
export function tickMarket(state: GameState): void {
  for (const key of Object.keys(state.market.categoryFactor)) {
    const f = state.market.categoryFactor[key]
    state.market.categoryFactor[key] = f + (1 - f) * 0.05
    if (Math.abs(state.market.categoryFactor[key] - 1) < 0.005) {
      state.market.categoryFactor[key] = 1
    }
  }
  if (state.market.inflation !== 0) {
    state.market.inflation *= 0.95
    if (Math.abs(state.market.inflation) < 0.001) state.market.inflation = 0
  }
}

/** Random walk for stock prices, recorded daily. */
export function tickStocks(state: GameState, rng: RNG): void {
  for (const st of state.stocks) {
    const def = STOCKS.find((d) => d.id === st.stockId)
    if (!def) continue
    const drift = rng.float(-def.volatility, def.volatility) + state.market.inflation * 0.1
    st.price = Math.max(1, Math.round(st.price * (1 + drift) * 100) / 100)
    st.history.push(st.price)
    if (st.history.length > 30) st.history.shift()
  }
}

/** Quarterly property index drift. */
export function tickPropertyIndex(state: GameState, rng: RNG): void {
  const drift = rng.float(-0.03, 0.035) + state.market.inflation
  state.market.propertyIndex = Math.max(0.5, state.market.propertyIndex + drift)
}

export function propertyValue(state: GameState, basePrice: number): number {
  return Math.round(basePrice * state.market.propertyIndex)
}
