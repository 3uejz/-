export interface StockDef {
  id: string
  name: string
  basePrice: number
  volatility: number
  sector: string
}

export const STOCKS: StockDef[] = [
  { id: 'stk_tech', name: '星辉科技', basePrice: 42, volatility: 0.035, sector: '科技' },
  { id: 'stk_bank', name: '恒信银行', basePrice: 18, volatility: 0.012, sector: '金融' },
  { id: 'stk_energy', name: '华能电力', basePrice: 12, volatility: 0.015, sector: '能源' },
  { id: 'stk_estate', name: '金地置业', basePrice: 26, volatility: 0.03, sector: '地产' },
  { id: 'stk_pharma', name: '康泰医药', basePrice: 33, volatility: 0.025, sector: '医药' },
  { id: 'stk_food', name: '味佳食品', basePrice: 15, volatility: 0.01, sector: '消费' },
  { id: 'stk_auto', name: '驰骋汽车', basePrice: 28, volatility: 0.028, sector: '汽车' },
  { id: 'stk_media', name: '光影传媒', basePrice: 21, volatility: 0.04, sector: '传媒' },
  { id: 'stk_agri', name: '丰登农业', basePrice: 9, volatility: 0.018, sector: '农业' },
  { id: 'stk_aviation', name: '翔云航空', basePrice: 24, volatility: 0.035, sector: '航空' },
  { id: 'stk_steel', name: '宝铸钢铁', basePrice: 11, volatility: 0.014, sector: '钢铁' },
  { id: 'stk_retail', name: '万家百货', basePrice: 17, volatility: 0.016, sector: '零售' },
]

export const STOCK_INDEX = new Map(STOCKS.map((s) => [s.id, s]))
export const STOCK_BY_NAME = new Map(STOCKS.map((s) => [s.name, s]))
