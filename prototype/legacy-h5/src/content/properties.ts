export interface PropertyDef {
  id: string
  name: string
  price: number
  rent: number
  comfort: number
  commuteMinutes: number
  desc: string
}

export const PROPERTIES: PropertyDef[] = [
  { id: 'prop_flatsmall', name: '城郊小单间', price: 180000, rent: 600, comfort: 1, commuteMinutes: 40, desc: '巴掌大的房间，勉强安身。' },
  { id: 'prop_flatown', name: '老小区两居', price: 450000, rent: 1500, comfort: 2, commuteMinutes: 30, desc: '楼龄老但生活气息浓。' },
  { id: 'prop_flathigh', name: '电梯高层两居', price: 800000, rent: 2600, comfort: 3, commuteMinutes: 25, desc: '视野开阔，采光极佳。' },
  { id: 'prop_flathome', name: '市中心三居', price: 1500000, rent: 4800, comfort: 5, commuteMinutes: 15, desc: '繁华触手可及。' },
  { id: 'prop_villaSub', name: '近郊洋房', price: 2600000, rent: 7500, comfort: 6, commuteMinutes: 35, desc: '带小院的独栋。' },
  { id: 'prop_villaLux', name: '湖畔别墅', price: 8000000, rent: 20000, comfort: 8, commuteMinutes: 40, desc: '推窗见湖，圈层象征。' },
]

export const PROPERTY_INDEX = new Map(PROPERTIES.map((p) => [p.id, p]))
export const PROPERTY_BY_NAME = new Map(PROPERTIES.map((p) => [p.name, p]))
