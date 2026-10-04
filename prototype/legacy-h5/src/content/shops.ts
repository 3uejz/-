import { ITEM_INDEX } from './items'

export interface ShopDef {
  id: string
  name: string
  itemIds: string[]
}

export const SHOPS: ShopDef[] = [
  {
    id: 'supermarket', name: '超市货架',
    itemIds: [
      'food_rice', 'food_noodle', 'food_dumpling', 'food_egg', 'food_milk', 'food_bread',
      'food_apple', 'food_banana', 'food_watermelon', 'food_nuts', 'food_juice', 'food_cola',
      'food_water', 'food_yogurt', 'food_instantNoodle', 'food_chips', 'food_cake', 'food_mooncake',
      'med_bandage', 'med_vitamin', 'tool_umbrella', 'tool_notebook', 'lux_plant',
    ],
  },
  {
    id: 'convenience', name: '便利店货架',
    itemIds: [
      'food_baozi', 'food_mantou', 'food_youtiao', 'food_riceBall', 'food_hamburg', 'food_hotdog',
      'food_instantNoodle', 'food_cola', 'food_water', 'food_beer', 'food_icecream', 'food_milkTea',
      'med_cold', 'med_bandage', 'cl_slippers',
    ],
  },
  {
    id: 'mall', name: '商场专柜',
    itemIds: [
      'cl_shirt', 'cl_suit', 'cl_dress', 'cl_jeans', 'cl_sweater', 'cl_sneakers', 'cl_leatherShoes',
      'cl_tie', 'cl_skirt', 'cl_downJacket', 'cl_hat',
      'ap_tv', 'ap_fridge', 'ap_washer', 'ap_ac', 'ap_pc', 'ap_phone', 'ap_console', 'ap_speaker',
      'ap_vacuum', 'ap_microwave', 'ap_riceCooker', 'ap_lamp',
      'lux_watch', 'lux_necklace', 'lux_perfume', 'lux_chocolate', 'lux_toy',
      'tool_camera', 'tool_luggage', 'tool_skateboard',
    ],
  },
  {
    id: 'restaurant', name: '餐厅菜单',
    itemIds: ['food_hotpot', 'food_pizza', 'food_bbq', 'food_sushi', 'food_luwei', 'food_cake', 'food_fruitBox'],
  },
  {
    id: 'fastFood', name: '快餐菜单',
    itemIds: ['food_hamburg', 'food_friedChicken', 'food_rice', 'food_noodle', 'food_cola', 'food_milk'],
  },
  {
    id: 'cafe', name: '咖啡菜单',
    itemIds: ['food_coffeeBeans', 'food_cake', 'food_milkTea', 'food_salad'],
  },
  {
    id: 'nightMarket', name: '夜市摊位',
    itemIds: ['food_bbq', 'food_friedChicken', 'food_luwei', 'food_milkTea', 'food_icecream', 'food_baozi', 'lux_toy'],
  },
  {
    id: 'pharmacy', name: '药店货架',
    itemIds: ['med_cold', 'med_fever', 'med_stomach', 'med_bandage', 'med_vitamin', 'med_tonic'],
  },
  {
    id: 'bookstore', name: '书店书架',
    itemIds: ['tool_bookProg', 'tool_bookCook', 'tool_bookFin', 'tool_bookLit', 'tool_bookLang', 'tool_notebook', 'tool_bag'],
  },
  {
    id: 'carDealer', name: '车行展厅',
    itemIds: ['veh_ebike', 'veh_usedCar', 'veh_newCar', 'veh_luxury'],
  },
]

export const SHOP_INDEX = new Map(SHOPS.map((s) => [s.id, s]))

/** Validate that all shop items exist in the item catalogue. */
export function validateShopItems(): string[] {
  const errors: string[] = []
  for (const shop of SHOPS) {
    for (const id of shop.itemIds) {
      if (!ITEM_INDEX.has(id)) errors.push(`${shop.id}: missing item ${id}`)
    }
  }
  return errors
}
