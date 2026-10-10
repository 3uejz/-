# 本文件由 tools/genbaseline 自动生成，请勿手改。
# 真源：shared/consistency/baseline/（运行 `go run ./tools/genbaseline` 重新生成）。
class_name BaselineGenerated
extends RefCounted

const RANGES: Dictionary = {
	"attribute": [0, 100],
	"awe": [0, 100],
	"favor": [-100, 100],
	"grudge": [-100, 100],
	"intimacy": [0, 100],
	"personality": [0, 100],
	"skill": [0, 20],
	"trust": [0, 100],
	"values_axis": [0, 100],
}
const RELATION_ANNUAL_DECAY_K: float = 0.05
const MINUTES_PER_DAY: int = 1440
const SPEED_LEVELS: Array = [0, 1, 2, 4, 60, 3600, 86400]
const DAY_PHASES: Dictionary = {"dawn_start_hour": 5, "day_start_hour": 8, "dusk_start_hour": 18, "night_start_hour": 21}

const ADDICTION_CRAVING_DECAY_PER_DAY: float = 0.5

const ADDICTION_DEPENDENT_MIN: float = 20.0

const ADDICTION_SEVERE_MIN: float = 60.0

const ADDICTION_SPECIES: Dictionary = {
	"alcohol": {"dose_gain": 4.0, "physiological": true, "relapse_rate": 0.45, "tolerance_growth": 0.03, "treatment_days": 30.0, "withdrawal_days": 10.0, "withdrawal_intensity": 8.0},
	"drug": {"dose_gain": 6.0, "physiological": true, "relapse_rate": 0.6, "tolerance_growth": 0.05, "treatment_days": 60.0, "withdrawal_days": 14.0, "withdrawal_intensity": 12.0},
	"gambling": {"dose_gain": 2.5, "physiological": false, "relapse_rate": 0.5, "tolerance_growth": 0.02, "treatment_days": 45.0, "withdrawal_days": 14.0, "withdrawal_intensity": 5.0},
	"internet": {"dose_gain": 2.0, "physiological": false, "relapse_rate": 0.35, "tolerance_growth": 0.02, "treatment_days": 30.0, "withdrawal_days": 14.0, "withdrawal_intensity": 4.0},
	"tobacco": {"dose_gain": 3.0, "physiological": true, "relapse_rate": 0.4, "tolerance_growth": 0.02, "treatment_days": 30.0, "withdrawal_days": 7.0, "withdrawal_intensity": 6.0},
}

const ADDICTION_TREATMENT: Dictionary = {
	"counseling": {"reduction": 0.2, "success_bonus": 0.15},
	"inpatient": {"reduction": 0.5, "success_bonus": 0.4},
	"substitution": {"reduction": 0.3, "success_bonus": 0.25},
}

const ADDICTION_WITHDRAWAL_TRIGGER_HOURS: float = 12.0

const AESTHETICS_ILLEGAL_COMPLICATION_MULT: float = 2.2

const AESTHETICS_ILLEGAL_SUCCESS_MULT: float = 0.55

const AESTHETICS_MALPRACTICE_COMPENSATION: int = 3000000

const AESTHETICS_OVER_MEDICALIZATION_THRESHOLD: int = 5

const AESTHETICS_STIFFNESS_PER_PROCEDURE: float = 8.0

const AGRI_CROPS: Dictionary = {
	"cotton": {"base_yield": 300.0, "fertility_cost": 0.18, "growth_days": 180.0, "name": "棉花", "price": 8000, "spoil_rate": 0.001, "use": "cash", "water_need": 0.9},
	"herb": {"base_yield": 200.0, "fertility_cost": 0.1, "growth_days": 240.0, "name": "药材", "price": 20000, "spoil_rate": 0.005, "use": "herbal", "water_need": 0.9},
	"rapeseed": {"base_yield": 250.0, "fertility_cost": 0.12, "growth_days": 160.0, "name": "油菜", "price": 6000, "spoil_rate": 0.001, "use": "cash", "water_need": 0.7},
	"rice": {"base_yield": 600.0, "fertility_cost": 0.15, "growth_days": 120.0, "name": "水稻", "price": 3000, "spoil_rate": 0.002, "use": "grain", "water_need": 1.2},
	"vegetable": {"base_yield": 2000.0, "fertility_cost": 0.2, "growth_days": 60.0, "name": "蔬菜", "price": 2500, "spoil_rate": 0.02, "use": "vegetable", "water_need": 1.3},
	"wheat": {"base_yield": 500.0, "fertility_cost": 0.1, "growth_days": 150.0, "name": "小麦", "price": 3200, "spoil_rate": 0.002, "use": "grain", "water_need": 0.8},
}

const AGRI_LIVESTOCK: Dictionary = {
	"cattle": {"breed_rate": 0.03, "disease_risk": 0.05, "feed_per_day": 6.0, "kind": "livestock", "market_price": 15000, "name": "肉牛"},
	"chicken": {"breed_rate": 0.15, "disease_risk": 0.12, "feed_per_day": 0.15, "kind": "poultry", "market_price": 60, "name": "肉鸡"},
	"duck": {"breed_rate": 0.12, "disease_risk": 0.12, "feed_per_day": 0.2, "kind": "poultry", "market_price": 80, "name": "鸭"},
	"fish": {"breed_rate": 0.1, "disease_risk": 0.15, "feed_per_day": 0.05, "kind": "aquaculture", "market_price": 25, "name": "鱼"},
	"pig": {"breed_rate": 0.06, "disease_risk": 0.08, "feed_per_day": 2.5, "kind": "livestock", "market_price": 4000, "name": "生猪"},
}

const AGRI_MARKET_CHANNELS: Dictionary = {
	"cooperative": {"name": "合作社", "price_mult": 1.08},
	"futures": {"name": "期货", "price_mult": 1.25},
	"market": {"name": "集市", "price_mult": 1.0},
	"order": {"name": "订单农业", "price_mult": 1.15},
	"self_supply": {"name": "自给", "price_mult": 0.0},
}

const ANOMALY_ABILITY_MAX_LEVEL: int = 20

const ANOMALY_AMNESTIC_CLEAR_PER_DOSE: float = 40.0

const ANOMALY_AMNESTIC_DEFAULT_MAX: int = 3

const ANOMALY_EXP_PER_LEVEL: float = 100.0

const ANOMALY_RARE_TALENT_RATE: float = 0.001

const ANOMALY_TOTAL_CATALOG_SIZE: int = 2000

const APPEAR_BMI_NORMAL_MAX: float = 24.9

const APPEAR_BMI_NORMAL_MIN: float = 18.5

const APPEAR_TYPICAL_HEIGHT_M: float = 170.0

const APPEAR_TYPICAL_WEIGHT_KG: float = 62.0

const ARTS_AWARD_CHANCE: float = 0.5

const ARTS_AWARD_MIN_SCORE: float = 85.0

const ARTS_BASE_INCOME: int = 20000

const ARTS_INSPIRATION_WEIGHT: float = 0.3

const ARTS_LUCK_WEIGHT: float = 0.2

const ARTS_PANDER_LOSS: float = 30.0

const ARTS_SKILL_WEIGHT: float = 0.5

const BANK_CREDIT_MAX: int = 1000

const BANK_CREDIT_MIN: int = 0

const BANK_CREDIT_OVERDUE_PENALTY: int = 100

const BANK_CREDIT_START: int = 700

const BANK_DEFAULT_OVERDUE_DAYS: int = 0

const BANK_DEMAND_RATE_ANNUAL: float = 0.003

const BANK_FIXED_RATE_ANNUAL: float = 0.02

const BANK_LOAN_RATE_ANNUAL: float = 0.05

const BANK_OVERDUE_DAYS_DOWNGRADE: int = 30

const CALENDAR_EPOCH_UNIX_DAYS: int = 10957

const CALENDAR_MINUTES_PER_DAY: int = 1440

const CIVIL_LAWYER_FEE_PER_LEVEL: int = 200000

const CLEANLINESS_DECAY_PER_MIN: float = 0.06944444444444445

const CLIMATE_ZONES: Dictionary = {
	"mediterranean": {"amp_diurnal": 9.0, "amp_temp": 9.0, "arid": 0.5, "base_temp": 17.0, "can_snow": false, "humidity": 55.0, "monsoon": false, "name": "地中海", "phase": 0.0, "precip_scale": 3.0, "pressure": 1013.0, "visibility": 18.0, "wind": 3.5},
	"polar_highland": {"amp_diurnal": 8.0, "amp_temp": 15.0, "arid": 0.6, "base_temp": -20.0, "can_snow": true, "humidity": 45.0, "monsoon": false, "name": "极地高原", "phase": 0.0, "precip_scale": 0.8, "pressure": 1008.0, "visibility": 10.0, "wind": 6.0},
	"subarctic_conifer": {"amp_diurnal": 9.0, "amp_temp": 18.0, "arid": 0.2, "base_temp": -4.0, "can_snow": true, "humidity": 65.0, "monsoon": false, "name": "亚寒带针叶林", "phase": 0.0, "precip_scale": 1.5, "pressure": 1012.0, "visibility": 12.0, "wind": 3.0},
	"subtropical_monsoon": {"amp_diurnal": 9.0, "amp_temp": 12.0, "arid": 0.1, "base_temp": 17.0, "can_snow": true, "humidity": 70.0, "monsoon": true, "name": "亚热带季风", "phase": -0.5, "precip_scale": 5.0, "pressure": 1010.0, "visibility": 12.0, "wind": 3.0},
	"temperate_continental": {"amp_diurnal": 11.0, "amp_temp": 16.0, "arid": 0.3, "base_temp": 8.0, "can_snow": true, "humidity": 55.0, "monsoon": false, "name": "温带大陆", "phase": 0.0, "precip_scale": 2.0, "pressure": 1014.0, "visibility": 15.0, "wind": 3.5},
	"temperate_oceanic": {"amp_diurnal": 6.0, "amp_temp": 7.0, "arid": 0.05, "base_temp": 11.0, "can_snow": true, "humidity": 78.0, "monsoon": false, "name": "温带海洋", "phase": 0.2, "precip_scale": 3.5, "pressure": 1012.0, "visibility": 12.0, "wind": 4.5},
	"tropical_desert": {"amp_diurnal": 18.0, "amp_temp": 12.0, "arid": 0.95, "base_temp": 30.0, "can_snow": false, "humidity": 20.0, "monsoon": false, "name": "热带沙漠", "phase": 0.0, "precip_scale": 0.3, "pressure": 1005.0, "visibility": 25.0, "wind": 4.0},
	"tropical_monsoon": {"amp_diurnal": 8.0, "amp_temp": 6.0, "arid": 0.1, "base_temp": 26.0, "can_snow": false, "humidity": 75.0, "monsoon": true, "name": "热带季风", "phase": -1.0, "precip_scale": 8.0, "pressure": 1008.0, "visibility": 15.0, "wind": 3.0},
	"tropical_rainforest": {"amp_diurnal": 6.0, "amp_temp": 2.0, "arid": 0.0, "base_temp": 26.0, "can_snow": false, "humidity": 85.0, "monsoon": true, "name": "热带雨林", "phase": 0.0, "precip_scale": 12.0, "pressure": 1008.0, "visibility": 15.0, "wind": 2.0},
	"tropical_savanna": {"amp_diurnal": 12.0, "amp_temp": 5.0, "arid": 0.4, "base_temp": 27.0, "can_snow": false, "humidity": 55.0, "monsoon": false, "name": "热带草原", "phase": 0.5, "precip_scale": 4.0, "pressure": 1010.0, "visibility": 20.0, "wind": 3.0},
}

const CLIMATE_ZONE_ORDER: Array = ["tropical_rainforest", "tropical_monsoon", "tropical_savanna", "tropical_desert", "subtropical_monsoon", "mediterranean", "temperate_oceanic", "temperate_continental", "subarctic_conifer", "polar_highland"]

const COMPANY_BASE_CONVERSION: float = 0.5

const COMPANY_CUSTOMERS_PER_SQM: float = 0.3

const COMPANY_LIQUIDATION_RATIO: float = 0.5

const COMPANY_LOYALTY_UNPAID_PENALTY: float = 8.0

const COMPANY_MONTH_DAYS: int = 30

const COMPANY_REFERENCE_MARKUP: float = 1.5

const COMPANY_REPUTATION_GAIN_PER_DAY: float = 0.2

const COMPANY_REPUTATION_LOSS_SHORTAGE: float = 1.0

const COMPANY_RESIGN_CHANCE: float = 0.3

const COMPANY_RESIGN_LOYALTY_THRESHOLD: float = 20.0

const CP_CHANNEL_WEIGHTS: Dictionary = {"class_action": 0.9, "consumer_association": 0.7, "hotline_12315": 0.6, "litigation": 0.85, "negotiate": 0.25, "platform": 0.4}

const CP_RETURN_WINDOW_DAYS: int = 7

const CP_THREE_GUARANTEE_DAYS: int = 15

const CP_WARRANTY_DEFECT_DAYS: int = 180

const CURRENCIES: Dictionary = {
	"CNY": {"name": "人民币", "rate": 7.0},
	"EUR": {"name": "欧元", "rate": 0.92},
	"GBP": {"name": "英镑", "rate": 0.8},
	"JPY": {"name": "日元", "rate": 150.0},
	"KRW": {"name": "韩元", "rate": 1350.0},
	"USD": {"name": "美元", "rate": 1.0},
}

const CURRENCY_BASE: String = "USD"

const DEHYDRATE_HEALTH_PER_HOUR: float = 4.0

const DE_CARE_MODES: Dictionary = {
	"community_care": {"cost_per_month": 600000, "happiness": 2.0, "life_modifier": 0.1, "name": "社区养老", "quality": 0.65},
	"home_care": {"cost_per_month": 400000, "happiness": 0.0, "life_modifier": 0.0, "name": "居家护理", "quality": 0.5},
	"institution_care": {"cost_per_month": 1200000, "happiness": -1.0, "life_modifier": 0.2, "name": "机构养老", "quality": 0.8},
}

const DE_DEVICES: Dictionary = {
	"accessibility": {
		"cost": 500000,
		"mobility_bonus": 0.2,
		"name": "无障碍改造",
		"types": ["physical", "sensory"],
	},
	"guide_dog": {
		"cost": 300000,
		"mobility_bonus": 0.35,
		"name": "导盲犬",
		"types": ["sensory"],
	},
	"hearing_aid": {
		"cost": 200000,
		"mobility_bonus": 0.1,
		"name": "助听器",
		"types": ["sensory"],
	},
	"prosthesis": {
		"cost": 1500000,
		"mobility_bonus": 0.4,
		"name": "义肢",
		"types": ["physical"],
	},
	"rehab": {
		"cost": 100000,
		"mobility_bonus": 0.15,
		"name": "康复训练",
		"types": ["physical", "sensory", "intellectual", "mental"],
	},
	"wheelchair": {
		"cost": 800000,
		"mobility_bonus": 0.5,
		"name": "轮椅",
		"types": ["physical"],
	},
}

const DE_SEVERITY_PENALTY: Dictionary = {"heavy": 0.75, "light": 0.15, "medium": 0.4}

const DIGITAL_ADDICTION_THRESHOLD_HOURS: float = 8.0

const DIGITAL_CONTENT_PLATFORMS: Dictionary = {
	"livestream": {"base_views": 20000, "conversion": 0.05, "cut": 0.3, "name": "直播", "tip_rate": 0.02},
	"short_video": {"base_views": 60000, "conversion": 0.08, "cut": 0.2, "name": "短视频", "tip_rate": 0.005},
}

const DIGITAL_HACK_TARGETS: Dictionary = {
	"black_market": {"base_gain": 800000, "difficulty": 12.0, "exposure": 0.5, "fine": 300000, "name": "黑产", "sentence_days": 365, "wanted": 1},
	"enterprise": {"base_gain": 500000, "difficulty": 10.0, "exposure": 0.4, "fine": 500000, "name": "企业", "sentence_days": 730, "wanted": 2},
	"government": {"base_gain": 2000000, "difficulty": 15.0, "exposure": 0.6, "fine": 2000000, "name": "政府", "sentence_days": 1825, "wanted": 3},
	"personal": {"base_gain": 20000, "difficulty": 6.0, "exposure": 0.25, "fine": 50000, "name": "个人", "sentence_days": 180, "wanted": 1},
}

const DIGITAL_SECURITY_JOBS: Dictionary = {
	"breach_disposal": {"difficulty": 10.0, "income": 200000, "name": "数据泄露处置", "reputation": 1.5},
	"defense": {"difficulty": 7.0, "income": 90000, "name": "安全防护", "reputation": 0.8},
	"incident_response": {"difficulty": 9.0, "income": 150000, "name": "应急响应", "reputation": 1.2},
	"pentest": {"difficulty": 8.0, "income": 120000, "name": "渗透测试", "reputation": 1.0},
}

const DINING_BASE_INCIDENT_PENALTY: int = 200000

const DINING_DAILY_RENT_DAYS: float = 30.0

const DINING_DEFAULT_TASTE: float = 65.0

const DINING_PACKAGING_COST: int = 300

const DINING_POACH_THRESHOLD: float = 40.0

const DINING_RECALL_UNIT_COST: int = 2000

const DINING_REFERENCE_STAFF: float = 5.0

const DOC_MINUTES_PER_YEAR: int = 525960

const DOC_PHOTO_MATCH_THRESHOLD: float = 0.75

const DS_BANKRUPTCY_ERA_START: int = 2021

const DS_BUSINESSES: Dictionary = {
	"consumer_finance": {"collateral_required": false, "era": "all", "name": "消费金融", "rate_cap": 0.24, "requires_license": true},
	"crowdfunding": {"collateral_required": false, "era": "all", "name": "众筹", "rate_cap": 0.0, "requires_license": true},
	"micro_loan": {"collateral_required": false, "era": "all", "name": "小额信贷", "rate_cap": 0.24, "requires_license": true},
	"p2p": {"collateral_required": false, "era": "2013-2020", "name": "P2P", "rate_cap": 0.24, "requires_license": true},
	"pawn": {"collateral_required": true, "era": "all", "name": "典当", "rate_cap": 0.36, "requires_license": true},
	"private_lending": {"collateral_required": false, "era": "all", "name": "民间借贷", "rate_cap": 0.36, "requires_license": false},
}

const DS_COLLECTION_MODES: Dictionary = {
	"harassment": {"legal": false, "name": "骚扰", "severity": 0.4},
	"home_visit": {"legal": false, "name": "上门施压", "severity": 0.65},
	"litigation": {"legal": true, "name": "起诉", "severity": 0.2},
	"reminder": {"legal": true, "name": "短信电话提醒", "severity": 0.1},
	"violence": {"legal": false, "name": "暴力催收", "severity": 0.9},
}

const DS_INTEREST_RATE_CAP: float = 0.36

const DS_P2P_ERA_END: int = 2020

const DS_P2P_ERA_START: int = 2013

const DYING_HEALTH_MARGIN: float = 30.0

const DYING_HEALTH_THRESHOLD: float = 10.0

const DYING_LIFESPAN_MARGIN_YEARS: float = 2.0

const EARTH_RADIUS_KM: float = 6371.0

const EDU_EXAM_PASS_MARGIN: float = 0.0

const EDU_STUDY_RATE: float = 12.0

const EMPLOYMENT_BASE_HIRE_DIFFICULTY: float = 0.7

const EMPLOYMENT_UNEMPLOYMENT_SENSITIVITY: float = 3.0

const EMPLOYMENT_WAGE_UNEMPLOYMENT_SENSITIVITY: float = 1.5

const EM_COMMAND_FAULT_LINE: float = 0.5

const EM_DEFAULT_RESPONSE_CAP: float = 60.0

const EM_PROFESSIONS: Dictionary = {
	"coast_guard": {
		"base_response": 15.0,
		"equipment": ["patrol_boat", "life_raft", "sonar"],
		"name": "海警",
	},
	"earthquake_rescue": {
		"base_response": 20.0,
		"equipment": ["hydraulic_tool", "search_dog", "rescue_bed"],
		"name": "地震救援",
	},
	"ems": {
		"base_response": 6.0,
		"equipment": ["ambulance", "defibrillator", "stretcher"],
		"name": "急救",
	},
	"fire": {
		"base_response": 8.0,
		"equipment": ["fire_truck", "aerial_ladder", "breathing_apparatus"],
		"name": "消防",
	},
	"flood_rescue": {
		"base_response": 18.0,
		"equipment": ["rubber_boat", "life_jacket", "pump"],
		"name": "洪水救援",
	},
	"mountain_rescue": {
		"base_response": 30.0,
		"equipment": ["rope_kit", "helicopter", "thermal_drone"],
		"name": "山地救援",
	},
}

const EM_SECONDARY_BASE_RISK: float = 0.15

const EM_SURVIVAL_TREATED: float = 0.9

const EM_SURVIVAL_UNTREATED: float = 0.35

const ENGINEERING_ACCEPTANCE_QUALITY_THRESHOLD: float = 0.6

const ENGINEERING_CHAIN: Array = ["survey", "design", "cost_estimation", "construction", "supervision", "acceptance"]

const ENGINEERING_PROCUREMENT_MODES: Dictionary = {
	"government_tender": {"name": "政府招投标"},
	"private": {"name": "私人工程"},
}

const ENGINEERING_QUALIFICATIONS: Dictionary = {
	"first": {"bid_bonus": 0.08, "max_scale": 300000000, "min_capital": 10000000, "name": "一级"},
	"second": {"bid_bonus": 0.0, "max_scale": 80000000, "min_capital": 2000000, "name": "二级"},
	"special": {"bid_bonus": 0.15, "max_scale": 1000000000, "min_capital": 50000000, "name": "特级"},
}

const ENGINEERING_STAGES: Dictionary = {
	"acceptance": {"cost_ratio": 0.01, "duration_ratio": 0.03, "name": "验收", "quality_weight": 0.1},
	"construction": {"cost_ratio": 0.7, "duration_ratio": 0.55, "name": "施工", "quality_weight": 0.4},
	"cost_estimation": {"cost_ratio": 0.02, "duration_ratio": 0.04, "name": "造价", "quality_weight": 0.05},
	"design": {"cost_ratio": 0.07, "duration_ratio": 0.15, "name": "设计", "quality_weight": 0.2},
	"supervision": {"cost_ratio": 0.03, "duration_ratio": 0.1, "name": "监理", "quality_weight": 0.15},
	"survey": {"cost_ratio": 0.03, "duration_ratio": 0.08, "name": "勘察", "quality_weight": 0.1},
}

const ENGINEERING_ZONE_TYPES: Dictionary = {
	"commercial": {"land_mult": 1.8, "name": "商业区", "population_pull": 0.3, "traffic_demand": 1.0},
	"green": {"land_mult": 0.5, "name": "绿地", "population_pull": 0.2, "traffic_demand": 0.2},
	"industrial": {"land_mult": 0.7, "name": "工业区", "population_pull": 0.4, "traffic_demand": 0.8},
	"mixed": {"land_mult": 1.3, "name": "综合区", "population_pull": 0.8, "traffic_demand": 0.9},
	"residential": {"land_mult": 1.0, "name": "居住区", "population_pull": 1.0, "traffic_demand": 0.6},
}

const ENT_ADDICTION_THRESHOLD: float = 60.0

const ENV_CARBON_FINE_MULTIPLIER: float = 3.0

const ENV_DEFAULT_CARBON_PRICE: int = 100

const ENV_ESG_EMISSION_PENALTY: float = 0.5

const ENV_ESG_FINE_DIVISOR: float = 100000.0

const ENV_ESG_FRAUD_PENALTY: float = 30.0

const ENV_ESG_GRADE_A: float = 80.0

const ENV_ESG_GRADE_B: float = 65.0

const ENV_ESG_GRADE_C: float = 50.0

const ENV_ESG_GREEN_INVESTMENT_CAP: float = 15.0

const ENV_ESG_GREEN_INVESTMENT_UNIT: float = 1e+06

const ENV_ESG_ILLEGAL_PENALTY: float = 20.0

const ENV_ESG_SCORE_MAX: float = 100.0

const ENV_FOOTPRINT_SCOPE1: float = 0.5

const ENV_FOOTPRINT_SCOPE2: float = 0.3

const ENV_FOOTPRINT_SCOPE3: float = 0.2

const ERA_COUNT: int = 9

const ERA_DEFINITIONS: Array = [
	{
		"description": "以采集、狩猎与打制石器为生。",
		"forecast_accuracy": 0.3,
		"key": "stone",
		"name": "石器",
		"start_year": -10000,
		"tags": ["fire", "stone_tools", "tribe"],
	},
	{
		"description": "定居耕作、陶器与早期文字。",
		"forecast_accuracy": 0.4,
		"key": "agrarian",
		"name": "农业",
		"start_year": -3000,
		"tags": ["agriculture", "pottery", "early_writing"],
	},
	{
		"description": "城邦与帝国、哲学与铸币。",
		"forecast_accuracy": 0.46,
		"key": "classical",
		"name": "古典",
		"start_year": -800,
		"tags": ["philosophy", "empire", "coinage"],
	},
	{
		"description": "封建秩序、远洋航行与火药初现。",
		"forecast_accuracy": 0.52,
		"key": "medieval",
		"name": "中世纪",
		"start_year": 500,
		"tags": ["feudalism", "compass", "gunpowder_early"],
	},
	{
		"description": "蒸汽、工厂与铁路。",
		"forecast_accuracy": 0.62,
		"key": "industrial",
		"name": "工业",
		"start_year": 1700,
		"tags": ["steam", "factory", "railway"],
	},
	{
		"description": "电力、电话与汽车。",
		"forecast_accuracy": 0.7,
		"key": "electric",
		"name": "电气",
		"start_year": 1870,
		"tags": ["electricity", "telephone", "automobile"],
	},
	{
		"description": "计算机、互联网与卫星。",
		"forecast_accuracy": 0.85,
		"key": "information",
		"name": "信息",
		"start_year": 1970,
		"tags": ["computer", "internet", "satellite"],
	},
	{
		"description": "人工智能、生物科技与新能源。",
		"forecast_accuracy": 0.93,
		"key": "intelligent",
		"name": "智能",
		"start_year": 2020,
		"tags": ["ai", "biotech", "renewable"],
	},
	{
		"description": "聚变、星际航行与外星殖民。",
		"forecast_accuracy": 0.98,
		"key": "interstellar",
		"name": "星际",
		"start_year": 2100,
		"tags": ["fusion", "spacefaring", "colony"],
	},
]

const EVENT_DEFAULT_GLOBAL_DAILY_CAP: int = 3

const EVENT_MINUTES_PER_DAY: int = 1440

const EXPO_BASE_LIABILITY: int = 500000

const EXPO_EXP_PER_EVENT: int = 20

const EXPO_SECURITY_SAFE_LEVEL: float = 0.6

const FAM_CHILD_DAILY_EXPENSE: int = 10000

const FAM_CONFESS_BASE: float = 0.25

const FAM_DIVORCE_ASSET_SPLIT: float = 0.5

const FAM_DIVORCE_MOOD_PENALTY: float = 25.0

const FAM_ELDER_DAILY_EXPENSE: int = 8000

const FAM_GENE_NOISE: float = 10.0

const FAM_HEREDITY_WEIGHT: float = 0.5

const FAM_MARRIAGE_FAVOR_MIN: float = 70.0

const FAM_MARRIAGE_INTIMACY_MIN: float = 70.0

const FASHION_BASE_ORDER_VALUE: int = 5000

const FASHION_BUBBLE_THRESHOLD: float = 1.8

const FASHION_INSPIRATION_WEIGHT: float = 0.2

const FASHION_PLAGIARISM_PENALTY: float = 35.0

const FASHION_SKILL_WEIGHT: float = 0.45

const FASHION_TREND_WEIGHT: float = 0.35

const FIN_ANNUALIZE_DAYS: int = 365

const FIN_CONTROL_THRESHOLD: float = 0.34

const FIN_GROWTH_BONUS_CAP: float = 2.0

const FIN_MIN_VALUATION: int = 10000000

const FIN_REVENUE_MULTIPLE: float = 8.0

const FIN_SENTIMENT_MAX: float = 3.0

const FIN_SENTIMENT_MIN: float = 0.1

const FIN_VAM_CONTROL_TRANSFER: float = 0.2

const FIN_VAM_REPURCHASE_RATIO: float = 0.2

const FX_ANNUAL_VOLATILITY: float = 0.08

const FX_FEE_RATE: float = 0.001

const FX_MEAN_REVERSION: float = 0.15

const FX_SPREAD_BPS: float = 50.0

const GBM_CRYPTO_VOLATILITY: float = 0.8

const GBM_DRIFT_DEFAULT: float = 0.08

const GBM_DRIFT_MAX: float = 0.15

const GBM_DRIFT_MIN: float = 0.05

const GBM_PRICE_FLOOR: float = 1e-06

const GBM_VOLATILITY_DEFAULT: float = 0.3

const GBM_VOLATILITY_MAX: float = 0.5

const GBM_VOLATILITY_MIN: float = 0.2

const GEO_MIN_TOTAL_LOCATIONS: int = 1000

const GOLDFINGER_DEFAULT_DAILY_CAP: int = 1000

const GOLDFINGER_FREE_REROLLS: int = 3

const GOLDFINGER_PITY_EPIC_AT: int = 20

const GOLDFINGER_PITY_LEGENDARY_AT: int = 60

const GRAY_GAMBLING_ADDICTION_THRESHOLD: float = 60.0

const GRAY_LOAN_INTEREST_DAILY: float = 0.01

const HAPPY_EXTREME_LOW: float = 15.0

const HAPPY_LOW_DAYS_FOR_RISK: int = 30

const HAPPY_LOW_THRESHOLD: float = 30.0

const HAPPY_MIDLIFE_AGE_MAX: float = 55.0

const HAPPY_MIDLIFE_AGE_MIN: float = 40.0

const HEALTH_REGEN_AGE_DECAY_PER_YEAR: float = 0.01

const HEALTH_REGEN_PER_HOUR: float = 1.0

const HONOR_BIAS_BONUS: float = 0.1

const HONOR_ENSHRINE_MIN_PRESTIGE: float = 80.0

const HONOR_TIE_EPSILON: float = 0.01

const HUNGER_DECAY_PER_MIN: float = 0.21

const IMMIG_MINUTES_PER_YEAR: int = 525960

const IMMIG_NATURALIZE_YEARS: int = 5

const INDIVIDUAL_TRADE_INFLUENCE: float = 1e-06

const INFRA_BILL_GRACE_DAYS: float = 30.0

const INFRA_CREDIT_PENALTY: float = 30.0

const INFRA_RECONNECT_FEE: int = 5000

const INHERIT_DISPUTE_BASE: float = 0.2

const INHERIT_DISPUTE_MULTI_HEIR_BONUS: float = 0.25

const INHERIT_DISPUTE_WILL_REDUCTION: float = 0.1

const INSURANCE_PAYOUT_RATE: float = 1.0

const INSURANCE_PREMIUM_RATE: float = 0.02

const JOB_DAYS_PER_MONTH: float = 30.0

const JOB_INTERVIEW_CHARM_WEIGHT: float = 0.15

const JOB_INTERVIEW_LUCK_WEIGHT: float = 0.1

const JOB_MOOD_THRESHOLD: float = 40.0

const JOB_PERFORMANCE_DECAY_PER_DAY: float = 0.1

const JOB_PERFORMANCE_GAIN_PER_HOUR: float = 0.25

const JOB_PROBATION_DAYS: int = 90

const JOB_PROMOTION_BASE_CHANCE: float = 0.55

const JOB_PROMOTION_INTERNAL_REP_MIN: float = 60.0

const JOB_PROMOTION_PERFORMANCE_MIN: float = 70.0

const JOB_RETIREMENT_PENSION_RATE: float = 0.02

const JOB_RETIREMENT_YEARS_REQUIRED: float = 20.0

const JOB_WORK_MOOD_PER_HOUR: float = 1.5

const JOB_WORK_STAMINA_PER_HOUR: float = 6.0

const JUSTICE_LAWYER_FEE_PER_LEVEL: int = 200000

const LANG_BASE_STUDY_GAIN: float = 1.2

const LANG_MAX_LEVEL: float = 100.0

const LEGACY_ASSET_CARRY_RATIO: float = 0.3

const LEGACY_BLOODLINE_PER_GEN: float = 0.05

const LEGACY_MAX_BLOODLINE: float = 1.0

const LEGACY_SKILL_MEMORY_RATIO: float = 0.5

const LEGACY_TALENT_SLOTS: int = 3

const LIFESPAN_BASE_YEARS: float = 78.0

const LOTTERY_PAYOUT_MINOR: int = 10000

const LOTTERY_TICKET_PRICE_MINOR: int = 200

const LOTTERY_WIN_CHANCE: float = 0.001

const MACRO_BASE_INFLATION: float = 0.02

const MACRO_BASE_RATE: float = 0.03

const MACRO_BIRTH_RATE: float = 0.012

const MACRO_CYCLE_GDP_EFFECT: Dictionary = {"boom": 0.05, "recession": -0.04, "recovery": 0.02, "slowdown": 0.01}

const MACRO_CYCLE_MAX_QUARTERS: int = 16

const MACRO_CYCLE_MIN_QUARTERS: int = 4

const MACRO_CYCLE_PHASES: Array = ["recession", "recovery", "boom", "slowdown"]

const MACRO_DEATH_RATE: float = 0.008

const MACRO_GDP_GROWTH_BASE: float = 0.03

const MACRO_INFLATION_MAX: float = 3.0

const MACRO_INFLATION_MIN: float = -0.05

const MACRO_INFLATION_UNEMPLOYMENT_TRADEOFF: float = 0.4

const MACRO_MIGRATION_RATE: float = 0.0002

const MACRO_PMI_BASE: float = 50.0

const MACRO_PMI_MAX: float = 100.0

const MACRO_PMI_MIN: float = 0.0

const MACRO_QUARTERS_PER_YEAR: int = 4

const MACRO_RATE_MAX: float = 0.5

const MACRO_RATE_MIN: float = 0.0

const MACRO_RATE_UNEMPLOYMENT_SENSITIVITY: float = 0.8

const MACRO_UNEMPLOYMENT_BASE: float = 0.05

const MACRO_UNEMPLOYMENT_MAX: float = 1.0

const MACRO_UNEMPLOYMENT_MIN: float = 0.0

const MACRO_WAGE_LAG_QUARTERS: int = 1

const MARGIN_INITIAL_RATIO: float = 0.5

const MARGIN_LIQUIDATION_FEE: float = 0.01

const MARGIN_MAINTENANCE_RATIO: float = 0.25

const MARKET_FX_EPSILON: float = 1e-09

const MARKET_MIN_SUPPLY: float = 0.01

const MEDICAL_FACILITIES: Dictionary = {
	"clinic": {
		"cost_mult": 0.7,
		"medical_level": 0.8,
		"name": "诊所",
		"reimburse": 0.5,
		"services": ["register", "consult", "medicine"],
	},
	"dental": {
		"cost_mult": 1.2,
		"medical_level": 0.9,
		"name": "牙科",
		"reimburse": 0.4,
		"services": ["register", "consult", "dental", "surgery"],
	},
	"hospital": {
		"cost_mult": 1.0,
		"medical_level": 1.0,
		"name": "综合医院",
		"reimburse": 0.7,
		"services": ["register", "consult", "admit", "surgery", "checkup"],
	},
	"pharmacy": {
		"cost_mult": 1.0,
		"medical_level": 0.7,
		"name": "药店",
		"reimburse": 0.0,
		"services": ["medicine"],
	},
	"psych_clinic": {
		"cost_mult": 1.0,
		"medical_level": 0.8,
		"name": "心理诊所",
		"reimburse": 0.3,
		"services": ["register", "consult", "therapy"],
	},
}

const MEDICAL_MISDIAGNOSIS_CHANCE: float = 0.1

const MEDICAL_SERVICE_COST: Dictionary = {"admit": 200000, "checkup": 50000, "consult": 20000, "dental": 100000, "medicine": 30000, "register": 5000, "surgery": 500000, "therapy": 30000}

const MEDICAL_UNTREATED_FREE_DAYS: float = 7.0

const MEDICAL_UNTREATED_HEALTH_DECAY_PER_DAY: float = 1.0

const META_CONFIRMATION_BIAS: float = 0.15

const META_PLACEBO_MOOD: float = 5.0

const MFG_DEFECT_SHARE: float = 0.5

const MFG_REFERENCE_LABOR: float = 20.0

const MH_EVENTS: Dictionary = {
	"breakup": {"mood": -15.0, "stress": 16.0},
	"debt": {"mood": -8.0, "stress": 14.0},
	"illness": {"mood": -10.0, "stress": 12.0},
	"marriage": {"mood": 12.0, "stress": 4.0},
	"praise": {"mood": 6.0, "stress": -4.0},
	"promotion": {"mood": 10.0, "stress": 6.0},
	"stay_up": {"mood": -5.0, "stress": 8.0},
	"unemployment": {"mood": -12.0, "stress": 18.0},
}

const MH_STRESS_DISORDER_THRESHOLD: float = 70.0

const MH_TREATMENTS: Dictionary = {
	"cbt": {"adherence": 0.7, "cost": 50000, "cure": 0.35, "minutes": 120, "name": "认知行为治疗", "remit": 0.45, "side_effect": 0.03},
	"crisis_intervention": {"adherence": 0.85, "cost": 80000, "cure": 0.05, "minutes": 240, "name": "重症干预", "remit": 0.75, "side_effect": 0.08},
	"hospitalization": {"adherence": 0.9, "cost": 300000, "cure": 0.2, "minutes": 14400, "name": "住院治疗", "remit": 0.6, "side_effect": 0.1},
	"medication": {"adherence": 0.65, "cost": 20000, "cure": 0.15, "minutes": 30, "name": "药物治疗", "remit": 0.6, "side_effect": 0.35},
	"psychotherapy": {"adherence": 0.8, "cost": 30000, "cure": 0.25, "minutes": 90, "name": "心理咨询", "remit": 0.5, "side_effect": 0.02},
}

const MILITARY_DISCHARGE_PAY_PER_YEAR: float = 2.0

const MILITARY_ENLIST_MAX_AGE: float = 24.0

const MILITARY_ENLIST_MIN_AGE: float = 18.0

const MILITARY_ENLIST_MIN_HEALTH: float = 60.0

const MILITARY_GARRISON_MERIT_PER_YEAR: float = 2.0

const MILITARY_MISSION_BASE_CASUALTY: float = 0.05

const MILITARY_MISSION_MERIT_BASE: float = 4.0

const MILITARY_TRAINING_MERIT_PER_DAY: float = 0.1

const MINING_CONCESSION_MIN_CAPITAL: int = 50000000

const MONEY_MINOR_SCALE: int = 100

const MOOD_RECOVER_PER_HOUR: float = 1.0

const MUNICIPAL_FACILITY_GRADE_THRESHOLD: float = 0.5

const MUNICIPAL_NEGLECT_CONDITION: float = 0.4

const MUNICIPAL_NEGLECT_MAINTENANCE_DAYS: int = 365

const MUNICIPAL_ROAD_REOPEN_WINDOW_DAYS: int = 365

const NPCMEM_BASE_HALF_LIFE_YEARS: float = 1.0

const NPCMEM_MAX_ENTRIES: int = 50

const NPCMEM_MAX_HALF_LIFE_YEARS: float = 10.0

const NPCMEM_REINFORCE_AMOUNT: float = 5.0

const NPC_MASK: int = -1

const NUTRITION_AGE_BASE_YEARS: float = 20.0

const NUTRITION_AGE_SCALE_PER_YEAR: float = 0.01

const NUTRITION_DECAY_PER_DAY: Dictionary = {"carbs": 6.0, "fat": 3.0, "minerals": 4.0, "protein": 4.0, "vitamins": 5.0}

const NUTRITION_EXCESS_DAYS_REQUIRED: float = 30.0

const NUTRITION_EXCESS_THRESHOLD: float = 85.0

const NUTRITION_LABOR_SCALE: float = 0.3

const NUTRITION_LIGHT_THRESHOLD: float = 30.0

const NUTRITION_SEVERE_THRESHOLD: float = 15.0

const ORDER_AUTO_COMPLETE_DAYS: int = 3

const ORDER_MONTH_DAYS: int = 30

const ORDER_RETURN_WINDOW_DAYS: int = 7

const ORG_EXPOSE_HEAT_MAX: float = 200.0

const ORG_EXPOSE_HEAT_THRESHOLD: float = 100.0

const ORG_TRADE_INFLUENCE: float = 0.001

const PARENT_CARE_WEIGHT: float = 0.2

const PARENT_DAILY_COST: Dictionary = {
	"child": {"minutes": 180, "money": 10000},
	"infant": {"minutes": 300, "money": 15000},
	"teen": {"minutes": 120, "money": 12000},
	"toddler": {"minutes": 240, "money": 12000},
}

const PARENT_EARLY_DEATH_RATE: float = 0.002

const PARENT_EDU_WEIGHT: float = 0.2

const PARENT_EVENTS: Dictionary = {
	"academic_pressure": {
		"ability": {"intelligence": 3.0},
		"personality": {"neuroticism": 2.0},
	},
	"bullying": {
		"personality": {"neuroticism": 4.0},
	},
	"illness": {
		"ability": {"physique": -3.0},
	},
	"injury": {
		"ability": {"physique": -5.0},
	},
	"rebellion": {
		"personality": {"agreeableness": -4.0, "extraversion": 2.0},
	},
	"talent_emerge": {
		"ability": {"intelligence": 5.0},
	},
}

const PARENT_GENE_WEIGHT: float = 0.5

const PARENT_RANDOM_WEIGHT: float = 0.1

const PARENT_STAGE_RANGE: Dictionary = {
	"child": [6, 12],
	"infant": [0, 3],
	"teen": [12, 18],
	"toddler": [3, 6],
}

const PERSONALITY_ADULT_AGE: float = 25.0

const PERSONALITY_ADULT_DRIFT_FACTOR: float = 0.25

const PERSONALITY_HEREDITY_WEIGHT: float = 0.5

const PERSONALITY_LIFETIME_DRIFT_CAP: float = 20.0

const PERSONALITY_NOISE_RANGE: float = 12.0

const PERSONALITY_POPULATION_BASELINE: float = 50.0

const PET_DEATH_HAPPINESS_DELTA: float = -15.0

const PET_DEATH_MOOD_DELTA: float = -20.0

const PET_HUNGER_DECAY_PER_DAY: float = 12.0

const PET_LOST_BASE_RISK: float = 0.01

const PET_SPECIES: Dictionary = {
	"bird": {"buy_cost": 80000, "daily_minutes": 20, "feed_cost": 1000, "lifespan": 10.0, "name": "鸟", "trainability": 0.6},
	"cat": {"buy_cost": 150000, "daily_minutes": 30, "feed_cost": 2500, "lifespan": 15.0, "name": "猫", "trainability": 0.5},
	"dog": {"buy_cost": 200000, "daily_minutes": 60, "feed_cost": 3000, "lifespan": 13.0, "name": "狗", "trainability": 0.9},
	"fish": {"buy_cost": 20000, "daily_minutes": 10, "feed_cost": 500, "lifespan": 5.0, "name": "鱼", "trainability": 0.1},
	"hamster": {"buy_cost": 30000, "daily_minutes": 10, "feed_cost": 800, "lifespan": 3.0, "name": "仓鼠", "trainability": 0.2},
	"rabbit": {"buy_cost": 60000, "daily_minutes": 20, "feed_cost": 1200, "lifespan": 8.0, "name": "兔", "trainability": 0.3},
	"reptile": {"buy_cost": 500000, "daily_minutes": 15, "feed_cost": 2000, "lifespan": 20.0, "name": "爬宠", "trainability": 0.2},
}

const PET_STARVATION_HEALTH_LOSS: float = 8.0

const POLICE_MISJUDGMENT_EVIDENCE_LINE: float = 0.4

const PRICE_CEIL_RATIO: float = 5.0

const PRICE_DEMAND_TO_PRICE: float = 0.5

const PRICE_ELASTICITY: Dictionary = {"daily": 0.35, "financial": 1.2, "luxury": 0.9, "necessity": 0.15}

const PRICE_FLOOR_RATIO: float = 0.2

const PRICE_SEASONAL_FACTORS: Dictionary = {"autumn": 1.05, "spring": 1.0, "summer": 1.0, "winter": 1.1}

const PRIMARY_FIRE_BASE_RISK: float = 0.02

const PRIMARY_FISHING_CLOSED_DAYS: float = 90.0

const PRISON_ESCAPE_BASE: float = 0.05

const PRISON_PAROLE_BEHAVIOR_MIN: float = 60.0

const PRISON_RECIDIVISM_BASE: float = 0.3

const PROP_DEED_TAX_RATE: float = 0.015

const PROP_DEFAULT_TERM_YEARS: int = 30

const PROP_DEPRECIATION_RATE_ANNUAL: float = 0.02

const PROP_DOWN_PAYMENT_RATIO: float = 0.3

const PROP_FORECLOSE_ARREARS_MONTHS: int = 3

const PROP_MAINTENANCE_RATE_ANNUAL: float = 0.005

const PROP_MORTGAGE_RATE_ANNUAL: float = 0.045

const PROP_PRICE_CEIL_RATIO: float = 3.0

const PROP_PRICE_FLOOR_RATIO: float = 0.5

const PROP_RENT_YIELD_ANNUAL: float = 0.02

const REGION_ACTIVE_POP_CAP: int = 2000

const REGION_BIRTH_RATE_ANNUAL: float = 0.012

const REGION_DAYS_PER_YEAR: float = 365.25

const REGION_DEATH_RATE_ANNUAL: float = 0.009

const REGION_ECONOMY_GROWTH_ANNUAL: float = 0.02

const REGION_EVENT_RATE_ANNUAL: float = 1.0

const REGION_INFLATION_RATE_ANNUAL: float = 0.02

const REGION_MIGRATION_RATE_ANNUAL: float = 0.0

const RELATION_INTERACTION_CAP: float = 15.0

const RELATION_MAJOR_CAP: float = 60.0

const REPUTATION_HOSTILE_THRESHOLD: float = 40.0

const REPUTATION_MAX_REPUTATION: float = 100.0

const REPUTATION_MINUTES_PER_DAY: float = 1440.0

const REPUTATION_REACH_CIRCLE: float = 0.3

const REPUTATION_REACH_REGION: float = 0.7

const REPUTATION_REFUSE_SERVICE_THRESHOLD: float = 60.0

const RESEARCH_ERA_UNLOCK_QUALITY: float = 90.0

const RESEARCH_EXPERIMENT_COST: int = 500000

const RESEARCH_INNOVATION_WEIGHT: float = 0.2

const RESEARCH_INVESTMENT_WEIGHT: float = 0.3

const RESEARCH_LUCK_WEIGHT: float = 0.1

const RESEARCH_PATENT_MIN_QUALITY: float = 70.0

const RESEARCH_PEER_REVIEW_THRESHOLD: float = 50.0

const RESEARCH_PUBLISH_INCOME_PER_QUALITY: int = 5000

const RESEARCH_PUBLISH_PRESTIGE_FACTOR: float = 0.5

const RESEARCH_SKILL_WEIGHT: float = 0.4

const RESEARCH_STARTUP_COST: int = 1000000

const SEIR_ALERT_ALERT_OCCUPANCY: float = 1.0

const SEIR_ALERT_ALERT_PREVALENCE: float = 0.005

const SEIR_ALERT_EMERGENCY_OCCUPANCY: float = 1.5

const SEIR_ALERT_EMERGENCY_PREVALENCE: float = 0.02

const SEIR_ALERT_WATCH_PREVALENCE: float = 0.0005

const SEIR_BEDS_DIVISOR: float = 1000.0

const SEIR_BETA_REDUCTION_CAP: float = 0.95

const SEIR_DEFAULT_PARAMS: Dictionary = {"beta": 0.5, "gamma": 0.1, "immunity_days": 180.0, "mortality": 0.01, "mutation_rate": 0.001, "sigma": 0.2}

const SEIR_DEFAULT_VACCINE_HESITANCY: float = 0.2

const SEIR_DOCTORS_DIVISOR: float = 500.0

const SEIR_IMMUNITY_WANE_RATE: float = 0.1

const SEIR_POLICY_BETA_REDUCTION: Dictionary = {"lockdown": 0.6, "mask": 0.15, "quarantine": 0.3, "school_closure": 0.2, "travel_restriction": 0.25, "vaccine_mandate": 0.1}

const SEIR_POLICY_ECONOMY_COST: Dictionary = {"lockdown": 0.05, "mask": 0.002, "quarantine": 0.02, "school_closure": 0.02, "travel_restriction": 0.03, "vaccine_mandate": 0.004}

const SEIR_POLICY_TRUST_PENALTY: float = 0.02

const SEIR_STAGE_DECLINING_RATIO: float = 0.01

const SEIR_STAGE_PEAK_RATIO: float = 0.98

const SEIR_STAGE_RESOLVED_INFECTIOUS: float = 0.5

const SEIR_SURGE_EXTRA_SLOPE: float = 0.5

const SEIR_TEST_KITS_DIVISOR: float = 100.0

const SEIR_VACCINE_ACCEPTANCE_NOISE: float = 0.1

const SEIR_VACCINE_STOCK_DIVISOR: float = 250.0

const SEIR_VENTILATORS_DIVISOR: float = 20000.0

const SKILL_DIMINISH_RATE: float = 0.9

const SKILL_DIMINISH_START: int = 10

const SKILL_FORGET_PER_DAY: float = 0.02

const SKILL_IDLE_GRACE_DAYS: float = 30.0

const SKILL_INNATE_CAP: int = 8

const SKILL_MAX_LEVEL: int = 20

const SKILL_PRACTICE_BASE: float = 10.0

const SKILL_XP_BASE: float = 100.0

const SKILL_XP_EXPONENT: float = 1.5

const SLEEP_DEBT_GAIN_PER_HOUR: float = 4.166666666666667

const SLEEP_DEBT_INTELLIGENCE_PENALTY_PER_HOUR: float = 2.0

const SLEEP_DEBT_MOOD_PENALTY_PER_HOUR: float = 3.0

const SLEEP_DEBT_RECOVER_PER_HOUR: float = 12.5

const SLEEP_DEBT_THRESHOLD: float = 60.0

const SOCNET_REACH_CIRCLE: float = 0.3

const SOCNET_REACH_REGION: float = 0.7

const SPORTSI_AGENT_FEE_RATE: float = 0.1

const SPORTSI_BASE_MARKET_VALUE: int = 5000000

const SPORTSI_BROADCAST_BASE: int = 8000000

const SPORTSI_CLUB_BASE_SPONSOR: int = 5000000

const SPORTSI_HOME_ADVANTAGE: float = 5.0

const SPORTSI_PEAK_AGE_MAX: int = 30

const SPORTSI_PEAK_AGE_MIN: int = 24

const SPORTSI_TICKET_BASE_PRICE: int = 10000

const SPORTS_AGE_DECLINE_RATE: float = 0.97

const SPORTS_AGE_FLOOR: float = 0.3

const SPORTS_DOPING_BAN_CHANCE: float = 0.3

const SPORTS_DOPING_BOOST: float = 10.0

const SPORTS_INJURY_BASE_RISK: float = 0.02

const SPORTS_INJURY_PENALTY: float = 8.0

const SPORTS_PEAK_MAX_AGE: int = 28

const SPORTS_PEAK_MIN_AGE: int = 22

const SPORTS_TRAIN_RATE: float = 0.4

const STAMINA_DRAIN_PER_HOUR: float = 20.0

const STAMINA_REGEN_ASLEEP_PER_HOUR: float = 12.5

const STAMINA_REGEN_AWAKE_PER_HOUR: float = 5.0

const STARVE_HEALTH_PER_HOUR: float = 2.0

const TAX_CONSUMPTION_RATE: float = 0.1

const TAX_CORPORATE_RATE: float = 0.25

const TAX_EVASION_AUDIT_CHANCE: float = 0.15

const TAX_INCOME_BRACKETS: Array = [
	{"rate": 0.03, "upper": 36000.0},
	{"rate": 0.1, "upper": 144000.0},
	{"rate": 0.2, "upper": 300000.0},
	{"rate": 0.25, "upper": 420000.0},
	{"rate": 0.3, "upper": 660000.0},
	{"rate": 0.35, "upper": 960000.0},
	{"rate": 0.45, "upper": -1.0},
]

const TAX_INHERITANCE_BRACKETS: Array = [
	{"rate": 0.0, "upper": 500000.0},
	{"rate": 0.1, "upper": 1e+06},
	{"rate": 0.2, "upper": 3e+06},
	{"rate": 0.3, "upper": 1e+07},
	{"rate": 0.45, "upper": -1.0},
]

const TAX_PROPERTY_RATE_ANNUAL: float = 0.012

const TAX_SOCIAL_SECURITY_RATE: float = 0.08

const TAX_STAMP_RATE: float = 0.001

const TAX_STANDARD_DEDUCTION: float = 6000.0

const TAX_TYPES: Array = ["income", "corporate", "vat", "consumption", "property", "inheritance", "stamp", "social_security"]

const TAX_VAT_RATE: float = 0.13

const THIRST_DECAY_PER_MIN: float = 0.42

const TRADE_DEFAULT_TARIFF_RATE: float = 0.08

const TRADE_DEFAULT_VAT_RATE: float = 0.13

const TRANSPORT_CONGESTION_CATEGORIES: Array = ["road", "urban"]

const TRANSPORT_CONGESTION_PEAK_FACTOR: float = 1.5

const TRANSPORT_MODES: Dictionary = {
	"airplane": {
		"base_fare": 320.0,
		"category": "air",
		"comfort": 88.0,
		"headway_minutes": 120.0,
		"hub_type": "airport",
		"name": "飞机",
		"per_km": 0.55,
		"per_minute": 0.0,
		"requires": ["passport"],
		"speed_kmh": 800.0,
		"wait_minutes": 90.0,
	},
	"bicycle": {
		"base_fare": 1.0,
		"category": "urban",
		"comfort": 50.0,
		"headway_minutes": 0.0,
		"hub_type": "",
		"name": "自行车",
		"per_km": 0.0,
		"per_minute": 0.05,
		"requires": [],
		"speed_kmh": 15.0,
		"wait_minutes": 1.0,
	},
	"bus": {
		"base_fare": 2.0,
		"category": "urban",
		"comfort": 55.0,
		"headway_minutes": 12.0,
		"hub_type": "bus_stop",
		"name": "公交",
		"per_km": 0.1,
		"per_minute": 0.0,
		"requires": [],
		"speed_kmh": 25.0,
		"wait_minutes": 6.0,
	},
	"coach": {
		"base_fare": 4.0,
		"category": "coach",
		"comfort": 60.0,
		"headway_minutes": 45.0,
		"hub_type": "coach_station",
		"name": "长途汽车",
		"per_km": 0.22,
		"per_minute": 0.0,
		"requires": ["id_card"],
		"speed_kmh": 70.0,
		"wait_minutes": 15.0,
	},
	"high_speed_rail": {
		"base_fare": 10.0,
		"category": "rail",
		"comfort": 90.0,
		"headway_minutes": 30.0,
		"hub_type": "hsr_station",
		"name": "高铁",
		"per_km": 0.45,
		"per_minute": 0.0,
		"requires": ["id_card"],
		"speed_kmh": 250.0,
		"wait_minutes": 25.0,
	},
	"metro": {
		"base_fare": 3.0,
		"category": "urban",
		"comfort": 70.0,
		"headway_minutes": 6.0,
		"hub_type": "metro_station",
		"name": "地铁",
		"per_km": 0.15,
		"per_minute": 0.0,
		"requires": [],
		"speed_kmh": 40.0,
		"wait_minutes": 3.0,
	},
	"ride_hailing": {
		"base_fare": 9.0,
		"category": "road",
		"comfort": 80.0,
		"headway_minutes": 0.0,
		"hub_type": "",
		"name": "网约车",
		"per_km": 2.2,
		"per_minute": 0.3,
		"requires": [],
		"speed_kmh": 35.0,
		"wait_minutes": 5.0,
	},
	"self_drive": {
		"base_fare": 0.0,
		"category": "road",
		"comfort": 85.0,
		"headway_minutes": 0.0,
		"hub_type": "",
		"name": "自驾",
		"per_km": 0.7,
		"per_minute": 0.0,
		"requires": ["driver_license", "vehicle"],
		"speed_kmh": 50.0,
		"wait_minutes": 0.0,
	},
	"ship": {
		"base_fare": 8.0,
		"category": "water",
		"comfort": 82.0,
		"headway_minutes": 180.0,
		"hub_type": "port",
		"name": "轮船",
		"per_km": 0.18,
		"per_minute": 0.0,
		"requires": [],
		"speed_kmh": 40.0,
		"wait_minutes": 30.0,
	},
	"taxi": {
		"base_fare": 13.0,
		"category": "road",
		"comfort": 80.0,
		"headway_minutes": 0.0,
		"hub_type": "",
		"name": "出租",
		"per_km": 2.6,
		"per_minute": 0.0,
		"requires": [],
		"speed_kmh": 35.0,
		"wait_minutes": 3.0,
	},
	"train": {
		"base_fare": 5.0,
		"category": "rail",
		"comfort": 75.0,
		"headway_minutes": 60.0,
		"hub_type": "train_station",
		"name": "火车",
		"per_km": 0.28,
		"per_minute": 0.0,
		"requires": ["id_card"],
		"speed_kmh": 90.0,
		"wait_minutes": 20.0,
	},
	"walk": {
		"base_fare": 0.0,
		"category": "urban",
		"comfort": 40.0,
		"headway_minutes": 0.0,
		"hub_type": "",
		"name": "步行",
		"per_km": 0.0,
		"per_minute": 0.0,
		"requires": [],
		"speed_kmh": 5.0,
		"wait_minutes": 0.0,
	},
}

const TRANSPORT_MODE_ORDER: Array = ["walk", "bicycle", "bus", "metro", "taxi", "ride_hailing", "self_drive", "train", "high_speed_rail", "coach", "airplane", "ship"]

const TRANSPORT_TRANSFER_MINUTES_DEFAULT: float = 8.0

const WAKE_EPSILON: float = 1e-06

const WAKE_MINUTES_PER_DAY: int = 1440

const WAR_BLACK_MARKET_PER_MOBILIZATION: float = 0.1

const WAR_DEBT_PER_YEAR_PER_MOBILIZATION: int = 500000000

const WAR_DECLARE_WAR_MIN_TENSION: float = 70.0

const WAR_DEFENSE_JOBS_PER_MOBILIZATION: float = 1e+06

const WAR_DRAFT_MAX_AGE: float = 35.0

const WAR_DRAFT_MIN_AGE: float = 18.0

const WAR_DRAFT_MIN_HEALTH: float = 50.0

const WAR_LIMITED_CONFLICT_TENSION: float = 50.0

const WAR_PRICE_SHOCK_PER_MOBILIZATION: float = 0.15

const WAR_RATIONING_MOBILIZATION_THRESHOLD: float = 0.5

const WAR_TENSION_THRESHOLD: float = 20.0

const WAR_TOTAL_WAR_TENSION: float = 80.0

const WEATHER_DAYS_PER_YEAR: float = 365.25

const WEATHER_DERIVED_NOISE_SIGMA: float = 1.5

const WEATHER_DISASTERS: Dictionary = {
	"blizzard": {
		"annual_rate": 0.012,
		"name": "暴雪",
		"seasons": ["winter"],
		"warning_max_days": 3,
		"warning_min_days": 1,
		"zones": ["subarctic_conifer", "polar_highland", "temperate_continental"],
	},
	"drought": {
		"annual_rate": 0.02,
		"name": "干旱",
		"seasons": ["summer"],
		"warning_max_days": 3,
		"warning_min_days": 1,
		"zones": ["tropical_desert", "tropical_savanna", "mediterranean", "subtropical_monsoon"],
	},
	"earthquake": {
		"annual_rate": 0.008,
		"name": "地震",
		"seasons": [],
		"warning_max_days": 1,
		"warning_min_days": 1,
		"zones": [],
	},
	"flood": {
		"annual_rate": 0.02,
		"name": "洪水",
		"seasons": ["summer", "autumn"],
		"warning_max_days": 3,
		"warning_min_days": 1,
		"zones": ["tropical_rainforest", "tropical_monsoon", "subtropical_monsoon", "temperate_oceanic", "tropical_savanna"],
	},
	"hailstorm": {
		"annual_rate": 0.008,
		"name": "冰雹",
		"seasons": ["spring", "summer"],
		"warning_max_days": 2,
		"warning_min_days": 1,
		"zones": ["temperate_continental", "mediterranean", "subtropical_monsoon"],
	},
	"locust": {
		"annual_rate": 0.006,
		"name": "蝗灾",
		"seasons": ["summer", "autumn"],
		"warning_max_days": 3,
		"warning_min_days": 1,
		"zones": ["tropical_savanna", "mediterranean", "subtropical_monsoon"],
	},
	"mudslide": {
		"annual_rate": 0.005,
		"name": "泥石流",
		"seasons": ["summer", "autumn"],
		"warning_max_days": 2,
		"warning_min_days": 1,
		"zones": ["tropical_rainforest", "tropical_monsoon", "subtropical_monsoon"],
	},
	"tsunami": {
		"annual_rate": 0.002,
		"name": "海啸",
		"seasons": [],
		"warning_max_days": 2,
		"warning_min_days": 1,
		"zones": ["tropical_monsoon", "temperate_oceanic", "mediterranean", "subtropical_monsoon"],
	},
	"typhoon": {
		"annual_rate": 0.015,
		"name": "台风",
		"seasons": ["summer", "autumn"],
		"warning_max_days": 3,
		"warning_min_days": 1,
		"zones": ["tropical_monsoon", "tropical_savanna", "subtropical_monsoon", "temperate_oceanic"],
	},
	"wildfire": {
		"annual_rate": 0.012,
		"name": "野火",
		"seasons": ["summer", "autumn"],
		"warning_max_days": 2,
		"warning_min_days": 1,
		"zones": ["tropical_desert", "tropical_savanna", "mediterranean", "temperate_continental"],
	},
}

const WEATHER_DISASTER_ORDER: Array = ["earthquake", "flood", "typhoon", "drought", "wildfire", "mudslide", "tsunami", "blizzard", "hailstorm", "locust"]

const WEATHER_DISASTER_WARNING_MAX_DAYS: int = 3

const WEATHER_DISASTER_WARNING_MIN_DAYS: int = 1

const WEATHER_FORECAST_ACCURACY_DECAY: float = 0.82

const WEATHER_FORECAST_ACCURACY_MIN: float = 0.05

const WEATHER_FORECAST_DAYS: int = 7

const WEATHER_HUMIDITY_MAX: float = 100.0

const WEATHER_HUMIDITY_MIN: float = 0.0

const WEATHER_MARKOV_FAMILY_CONTINUITY: float = 1.3

const WEATHER_MARKOV_PERSISTENCE: float = 2.5

const WEATHER_MAX_HISTORY_DAYS: int = 4096

const WEATHER_MIN_STATE_WEIGHT: float = 0.001

const WEATHER_PRECIP_MAX: float = 200.0

const WEATHER_PRECIP_MIN: float = 0.0

const WEATHER_PRESSURE_MAX: float = 1050.0

const WEATHER_PRESSURE_MIN: float = 950.0

const WEATHER_SEASON_KEYS: Array = ["spring", "summer", "autumn", "winter"]

const WEATHER_SNOW_TEMP_THRESHOLD: float = 2.0

const WEATHER_STATES: Dictionary = {
	"clear": {
		"affinity": {"cold": 0.1, "dry": 1.2, "hot": 0.3},
		"family": "clear",
		"humidity_mod": -20.0,
		"name": "晴",
		"precip_mm": 0.0,
		"pressure_delta": 8.0,
		"temp_delta": 2.0,
		"visibility_mod": 15.0,
		"wind_mod": -1.0,
	},
	"cold_wave": {
		"affinity": {"cold": 2.0, "dry": 0.8},
		"cold_gate": true,
		"family": "cold",
		"humidity_mod": -6.0,
		"name": "寒潮",
		"precip_mm": 0.0,
		"pressure_delta": 6.0,
		"temp_delta": -10.0,
		"visibility_mod": 2.0,
		"wind_mod": 4.0,
	},
	"dust": {
		"affinity": {"dry": 1.6, "wind": 0.8},
		"dust": true,
		"family": "dust",
		"humidity_mod": -15.0,
		"name": "沙尘",
		"precip_mm": 0.0,
		"pressure_delta": -2.0,
		"temp_delta": 0.0,
		"visibility_mod": -30.0,
		"wind_mod": 6.0,
	},
	"fog": {
		"affinity": {"cloud": 0.7, "wet": 0.5},
		"family": "fog",
		"humidity_mod": 30.0,
		"name": "雾",
		"precip_mm": 0.0,
		"pressure_delta": 1.0,
		"temp_delta": -1.0,
		"visibility_mod": -35.0,
		"wind_mod": -2.0,
	},
	"freezing_rain": {
		"affinity": {"cold": 1.2, "wet": 0.9},
		"family": "storm",
		"freezing": true,
		"humidity_mod": 22.0,
		"name": "冻雨",
		"precip_mm": 8.0,
		"pressure_delta": -10.0,
		"temp_delta": -2.0,
		"visibility_mod": -12.0,
		"wind_mod": 1.5,
	},
	"gale": {
		"affinity": {"wind": 2.0},
		"family": "wind",
		"humidity_mod": -5.0,
		"name": "大风",
		"precip_mm": 0.0,
		"pressure_delta": -4.0,
		"temp_delta": -1.0,
		"visibility_mod": -6.0,
		"wind_mod": 12.0,
	},
	"hail": {
		"affinity": {"cold": 0.4, "wet": 1.0},
		"family": "storm",
		"humidity_mod": 20.0,
		"name": "冰雹",
		"precip_mm": 15.0,
		"pressure_delta": -14.0,
		"temp_delta": -3.0,
		"visibility_mod": -16.0,
		"wind_mod": 6.0,
	},
	"haze": {
		"affinity": {"cloud": 0.5, "dry": 0.4},
		"family": "haze",
		"humidity_mod": 10.0,
		"name": "霾",
		"precip_mm": 0.0,
		"pressure_delta": 2.0,
		"temp_delta": 0.0,
		"visibility_mod": -28.0,
		"wind_mod": -2.5,
	},
	"heat": {
		"affinity": {"dry": 0.7, "hot": 2.0},
		"family": "heat",
		"hot_gate": true,
		"humidity_mod": -5.0,
		"name": "高温",
		"precip_mm": 0.0,
		"pressure_delta": 2.0,
		"temp_delta": 8.0,
		"visibility_mod": 2.0,
		"wind_mod": -0.5,
	},
	"heavy_rain": {
		"affinity": {"wet": 1.5},
		"family": "rain",
		"humidity_mod": 28.0,
		"name": "大雨",
		"precip_mm": 30.0,
		"pressure_delta": -12.0,
		"temp_delta": -3.0,
		"visibility_mod": -12.0,
		"wind_mod": 2.0,
	},
	"heavy_snow": {
		"affinity": {"cold": 1.4, "wet": 1.0},
		"family": "snow",
		"humidity_mod": 24.0,
		"name": "大雪",
		"precip_mm": 18.0,
		"pressure_delta": -11.0,
		"snow": true,
		"temp_delta": -3.0,
		"visibility_mod": -14.0,
		"wind_mod": 2.0,
	},
	"light_rain": {
		"affinity": {"wet": 1.0},
		"family": "rain",
		"humidity_mod": 15.0,
		"name": "小雨",
		"precip_mm": 3.0,
		"pressure_delta": -5.0,
		"temp_delta": -1.0,
		"visibility_mod": -5.0,
		"wind_mod": 0.5,
	},
	"light_snow": {
		"affinity": {"cold": 1.0, "wet": 0.6},
		"family": "snow",
		"humidity_mod": 12.0,
		"name": "小雪",
		"precip_mm": 2.0,
		"pressure_delta": -4.0,
		"snow": true,
		"temp_delta": -1.0,
		"visibility_mod": -4.0,
		"wind_mod": 0.5,
	},
	"moderate_rain": {
		"affinity": {"wet": 1.3},
		"family": "rain",
		"humidity_mod": 22.0,
		"name": "中雨",
		"precip_mm": 12.0,
		"pressure_delta": -8.0,
		"temp_delta": -2.0,
		"visibility_mod": -8.0,
		"wind_mod": 1.0,
	},
	"moderate_snow": {
		"affinity": {"cold": 1.2, "wet": 0.8},
		"family": "snow",
		"humidity_mod": 18.0,
		"name": "中雪",
		"precip_mm": 8.0,
		"pressure_delta": -7.0,
		"snow": true,
		"temp_delta": -2.0,
		"visibility_mod": -8.0,
		"wind_mod": 1.0,
	},
	"overcast": {
		"affinity": {"cloud": 1.0, "wet": 0.3},
		"family": "cloud",
		"humidity_mod": 8.0,
		"name": "阴",
		"precip_mm": 0.0,
		"pressure_delta": -3.0,
		"temp_delta": -1.0,
		"visibility_mod": -3.0,
		"wind_mod": 0.0,
	},
	"partly_cloudy": {
		"affinity": {"cloud": 0.6, "dry": 0.4},
		"family": "cloud",
		"humidity_mod": -5.0,
		"name": "多云",
		"precip_mm": 0.0,
		"pressure_delta": 3.0,
		"temp_delta": 1.0,
		"visibility_mod": 8.0,
		"wind_mod": 0.0,
	},
	"rainstorm": {
		"affinity": {"wet": 1.8},
		"family": "storm",
		"humidity_mod": 33.0,
		"name": "暴雨",
		"precip_mm": 70.0,
		"pressure_delta": -18.0,
		"temp_delta": -4.0,
		"visibility_mod": -18.0,
		"wind_mod": 4.0,
	},
	"snowstorm": {
		"affinity": {"cold": 1.5, "wet": 1.1, "wind": 0.6},
		"family": "storm",
		"humidity_mod": 30.0,
		"name": "暴雪",
		"precip_mm": 35.0,
		"pressure_delta": -16.0,
		"snow": true,
		"temp_delta": -4.0,
		"visibility_mod": -22.0,
		"wind_mod": 6.0,
	},
	"thunderstorm": {
		"affinity": {"hot": 0.5, "wet": 1.4},
		"family": "storm",
		"humidity_mod": 25.0,
		"name": "雷阵雨",
		"precip_mm": 25.0,
		"pressure_delta": -15.0,
		"temp_delta": -1.0,
		"visibility_mod": -14.0,
		"wind_mod": 5.0,
	},
}

const WEATHER_STATE_ORDER: Array = ["clear", "partly_cloudy", "overcast", "light_rain", "moderate_rain", "heavy_rain", "rainstorm", "thunderstorm", "hail", "freezing_rain", "light_snow", "moderate_snow", "heavy_snow", "snowstorm", "fog", "haze", "dust", "heat", "cold_wave", "gale"]

const WEATHER_TEMP_MAX: float = 60.0

const WEATHER_TEMP_MIN: float = -60.0

const WEATHER_TEMP_NOISE_SIGMA: float = 2.0

const WEATHER_VISIBILITY_MAX: float = 50.0

const WEATHER_VISIBILITY_MIN: float = 0.0

const WEATHER_WIND_MAX: float = 60.0

const WEATHER_WIND_MIN: float = 0.0

const WELFARE_DIBAO_INCOME_CEILING: float = 12000.0

const WISH_MAX_WISHES: int = 3

const WMEM_BASE_HALF_LIFE_DAYS: float = 30.0

const WMEM_FADE_THRESHOLD: float = 1.0

const WORK_DIM_MAX: float = 100.0

const WORK_EVENT_WEIGHTS: Dictionary = {"blame": 0.3, "credit_grab": 0.3, "report": 0.2, "take_sides": 0.2}

const WORK_FACTION_POWER_MAX: float = 100.0

const WORK_PROMOTION_INDUSTRY_WEIGHT: float = 0.05

const WORK_PROMOTION_LUCK_WEIGHT: float = 0.1

const WORK_PROMOTION_PERFORMANCE_WEIGHT: float = 0.4

const WORK_PROMOTION_REPUTATION_WEIGHT: float = 0.2

const WORK_PROMOTION_SUPERVISOR_WEIGHT: float = 0.25

const WORK_PROMOTION_THRESHOLD: float = 65.0

const BASELINE_DOMAINS: Dictionary = {
	"aesthetics": {"AESTHETICS_ILLEGAL_COMPLICATION_MULT": 2.2, "AESTHETICS_ILLEGAL_SUCCESS_MULT": 0.55, "AESTHETICS_MALPRACTICE_COMPENSATION": 3000000, "AESTHETICS_OVER_MEDICALIZATION_THRESHOLD": 5, "AESTHETICS_STIFFNESS_PER_PROCEDURE": 8.0},
	"agriculture": {
		"AGRI_CROPS": {
			"cotton": {"base_yield": 300.0, "fertility_cost": 0.18, "growth_days": 180.0, "name": "棉花", "price": 8000, "spoil_rate": 0.001, "use": "cash", "water_need": 0.9},
			"herb": {"base_yield": 200.0, "fertility_cost": 0.1, "growth_days": 240.0, "name": "药材", "price": 20000, "spoil_rate": 0.005, "use": "herbal", "water_need": 0.9},
			"rapeseed": {"base_yield": 250.0, "fertility_cost": 0.12, "growth_days": 160.0, "name": "油菜", "price": 6000, "spoil_rate": 0.001, "use": "cash", "water_need": 0.7},
			"rice": {"base_yield": 600.0, "fertility_cost": 0.15, "growth_days": 120.0, "name": "水稻", "price": 3000, "spoil_rate": 0.002, "use": "grain", "water_need": 1.2},
			"vegetable": {"base_yield": 2000.0, "fertility_cost": 0.2, "growth_days": 60.0, "name": "蔬菜", "price": 2500, "spoil_rate": 0.02, "use": "vegetable", "water_need": 1.3},
			"wheat": {"base_yield": 500.0, "fertility_cost": 0.1, "growth_days": 150.0, "name": "小麦", "price": 3200, "spoil_rate": 0.002, "use": "grain", "water_need": 0.8},
		},
		"AGRI_LIVESTOCK": {
			"cattle": {"breed_rate": 0.03, "disease_risk": 0.05, "feed_per_day": 6.0, "kind": "livestock", "market_price": 15000, "name": "肉牛"},
			"chicken": {"breed_rate": 0.15, "disease_risk": 0.12, "feed_per_day": 0.15, "kind": "poultry", "market_price": 60, "name": "肉鸡"},
			"duck": {"breed_rate": 0.12, "disease_risk": 0.12, "feed_per_day": 0.2, "kind": "poultry", "market_price": 80, "name": "鸭"},
			"fish": {"breed_rate": 0.1, "disease_risk": 0.15, "feed_per_day": 0.05, "kind": "aquaculture", "market_price": 25, "name": "鱼"},
			"pig": {"breed_rate": 0.06, "disease_risk": 0.08, "feed_per_day": 2.5, "kind": "livestock", "market_price": 4000, "name": "生猪"},
		},
		"AGRI_MARKET_CHANNELS": {
			"cooperative": {"name": "合作社", "price_mult": 1.08},
			"futures": {"name": "期货", "price_mult": 1.25},
			"market": {"name": "集市", "price_mult": 1.0},
			"order": {"name": "订单农业", "price_mult": 1.15},
			"self_supply": {"name": "自给", "price_mult": 0.0},
		},
	},
	"anomaly": {"ANOMALY_ABILITY_MAX_LEVEL": 20, "ANOMALY_AMNESTIC_CLEAR_PER_DOSE": 40.0, "ANOMALY_AMNESTIC_DEFAULT_MAX": 3, "ANOMALY_EXP_PER_LEVEL": 100.0, "ANOMALY_RARE_TALENT_RATE": 0.001, "ANOMALY_TOTAL_CATALOG_SIZE": 2000},
	"appearance": {"APPEAR_BMI_NORMAL_MAX": 24.9, "APPEAR_BMI_NORMAL_MIN": 18.5, "APPEAR_TYPICAL_HEIGHT_M": 170.0, "APPEAR_TYPICAL_WEIGHT_KG": 62.0},
	"arts": {"ARTS_AWARD_CHANCE": 0.5, "ARTS_AWARD_MIN_SCORE": 85.0, "ARTS_BASE_INCOME": 20000, "ARTS_INSPIRATION_WEIGHT": 0.3, "ARTS_LUCK_WEIGHT": 0.2, "ARTS_PANDER_LOSS": 30.0, "ARTS_SKILL_WEIGHT": 0.5},
	"civil": {"CIVIL_LAWYER_FEE_PER_LEVEL": 200000},
	"climate_weather": {
		"CLIMATE_ZONES": {
			"mediterranean": {"amp_diurnal": 9.0, "amp_temp": 9.0, "arid": 0.5, "base_temp": 17.0, "can_snow": false, "humidity": 55.0, "monsoon": false, "name": "地中海", "phase": 0.0, "precip_scale": 3.0, "pressure": 1013.0, "visibility": 18.0, "wind": 3.5},
			"polar_highland": {"amp_diurnal": 8.0, "amp_temp": 15.0, "arid": 0.6, "base_temp": -20.0, "can_snow": true, "humidity": 45.0, "monsoon": false, "name": "极地高原", "phase": 0.0, "precip_scale": 0.8, "pressure": 1008.0, "visibility": 10.0, "wind": 6.0},
			"subarctic_conifer": {"amp_diurnal": 9.0, "amp_temp": 18.0, "arid": 0.2, "base_temp": -4.0, "can_snow": true, "humidity": 65.0, "monsoon": false, "name": "亚寒带针叶林", "phase": 0.0, "precip_scale": 1.5, "pressure": 1012.0, "visibility": 12.0, "wind": 3.0},
			"subtropical_monsoon": {"amp_diurnal": 9.0, "amp_temp": 12.0, "arid": 0.1, "base_temp": 17.0, "can_snow": true, "humidity": 70.0, "monsoon": true, "name": "亚热带季风", "phase": -0.5, "precip_scale": 5.0, "pressure": 1010.0, "visibility": 12.0, "wind": 3.0},
			"temperate_continental": {"amp_diurnal": 11.0, "amp_temp": 16.0, "arid": 0.3, "base_temp": 8.0, "can_snow": true, "humidity": 55.0, "monsoon": false, "name": "温带大陆", "phase": 0.0, "precip_scale": 2.0, "pressure": 1014.0, "visibility": 15.0, "wind": 3.5},
			"temperate_oceanic": {"amp_diurnal": 6.0, "amp_temp": 7.0, "arid": 0.05, "base_temp": 11.0, "can_snow": true, "humidity": 78.0, "monsoon": false, "name": "温带海洋", "phase": 0.2, "precip_scale": 3.5, "pressure": 1012.0, "visibility": 12.0, "wind": 4.5},
			"tropical_desert": {"amp_diurnal": 18.0, "amp_temp": 12.0, "arid": 0.95, "base_temp": 30.0, "can_snow": false, "humidity": 20.0, "monsoon": false, "name": "热带沙漠", "phase": 0.0, "precip_scale": 0.3, "pressure": 1005.0, "visibility": 25.0, "wind": 4.0},
			"tropical_monsoon": {"amp_diurnal": 8.0, "amp_temp": 6.0, "arid": 0.1, "base_temp": 26.0, "can_snow": false, "humidity": 75.0, "monsoon": true, "name": "热带季风", "phase": -1.0, "precip_scale": 8.0, "pressure": 1008.0, "visibility": 15.0, "wind": 3.0},
			"tropical_rainforest": {"amp_diurnal": 6.0, "amp_temp": 2.0, "arid": 0.0, "base_temp": 26.0, "can_snow": false, "humidity": 85.0, "monsoon": true, "name": "热带雨林", "phase": 0.0, "precip_scale": 12.0, "pressure": 1008.0, "visibility": 15.0, "wind": 2.0},
			"tropical_savanna": {"amp_diurnal": 12.0, "amp_temp": 5.0, "arid": 0.4, "base_temp": 27.0, "can_snow": false, "humidity": 55.0, "monsoon": false, "name": "热带草原", "phase": 0.5, "precip_scale": 4.0, "pressure": 1010.0, "visibility": 20.0, "wind": 3.0},
		},
		"CLIMATE_ZONE_ORDER": ["tropical_rainforest", "tropical_monsoon", "tropical_savanna", "tropical_desert", "subtropical_monsoon", "mediterranean", "temperate_oceanic", "temperate_continental", "subarctic_conifer", "polar_highland"],
		"WEATHER_DAYS_PER_YEAR": 365.25,
		"WEATHER_DERIVED_NOISE_SIGMA": 1.5,
		"WEATHER_DISASTERS": {
			"blizzard": {
				"annual_rate": 0.012,
				"name": "暴雪",
				"seasons": ["winter"],
				"warning_max_days": 3,
				"warning_min_days": 1,
				"zones": ["subarctic_conifer", "polar_highland", "temperate_continental"],
			},
			"drought": {
				"annual_rate": 0.02,
				"name": "干旱",
				"seasons": ["summer"],
				"warning_max_days": 3,
				"warning_min_days": 1,
				"zones": ["tropical_desert", "tropical_savanna", "mediterranean", "subtropical_monsoon"],
			},
			"earthquake": {
				"annual_rate": 0.008,
				"name": "地震",
				"seasons": [],
				"warning_max_days": 1,
				"warning_min_days": 1,
				"zones": [],
			},
			"flood": {
				"annual_rate": 0.02,
				"name": "洪水",
				"seasons": ["summer", "autumn"],
				"warning_max_days": 3,
				"warning_min_days": 1,
				"zones": ["tropical_rainforest", "tropical_monsoon", "subtropical_monsoon", "temperate_oceanic", "tropical_savanna"],
			},
			"hailstorm": {
				"annual_rate": 0.008,
				"name": "冰雹",
				"seasons": ["spring", "summer"],
				"warning_max_days": 2,
				"warning_min_days": 1,
				"zones": ["temperate_continental", "mediterranean", "subtropical_monsoon"],
			},
			"locust": {
				"annual_rate": 0.006,
				"name": "蝗灾",
				"seasons": ["summer", "autumn"],
				"warning_max_days": 3,
				"warning_min_days": 1,
				"zones": ["tropical_savanna", "mediterranean", "subtropical_monsoon"],
			},
			"mudslide": {
				"annual_rate": 0.005,
				"name": "泥石流",
				"seasons": ["summer", "autumn"],
				"warning_max_days": 2,
				"warning_min_days": 1,
				"zones": ["tropical_rainforest", "tropical_monsoon", "subtropical_monsoon"],
			},
			"tsunami": {
				"annual_rate": 0.002,
				"name": "海啸",
				"seasons": [],
				"warning_max_days": 2,
				"warning_min_days": 1,
				"zones": ["tropical_monsoon", "temperate_oceanic", "mediterranean", "subtropical_monsoon"],
			},
			"typhoon": {
				"annual_rate": 0.015,
				"name": "台风",
				"seasons": ["summer", "autumn"],
				"warning_max_days": 3,
				"warning_min_days": 1,
				"zones": ["tropical_monsoon", "tropical_savanna", "subtropical_monsoon", "temperate_oceanic"],
			},
			"wildfire": {
				"annual_rate": 0.012,
				"name": "野火",
				"seasons": ["summer", "autumn"],
				"warning_max_days": 2,
				"warning_min_days": 1,
				"zones": ["tropical_desert", "tropical_savanna", "mediterranean", "temperate_continental"],
			},
		},
		"WEATHER_DISASTER_ORDER": ["earthquake", "flood", "typhoon", "drought", "wildfire", "mudslide", "tsunami", "blizzard", "hailstorm", "locust"],
		"WEATHER_DISASTER_WARNING_MAX_DAYS": 3,
		"WEATHER_DISASTER_WARNING_MIN_DAYS": 1,
		"WEATHER_FORECAST_ACCURACY_DECAY": 0.82,
		"WEATHER_FORECAST_ACCURACY_MIN": 0.05,
		"WEATHER_FORECAST_DAYS": 7,
		"WEATHER_HUMIDITY_MAX": 100.0,
		"WEATHER_HUMIDITY_MIN": 0.0,
		"WEATHER_MARKOV_FAMILY_CONTINUITY": 1.3,
		"WEATHER_MARKOV_PERSISTENCE": 2.5,
		"WEATHER_MAX_HISTORY_DAYS": 4096,
		"WEATHER_MIN_STATE_WEIGHT": 0.001,
		"WEATHER_PRECIP_MAX": 200.0,
		"WEATHER_PRECIP_MIN": 0.0,
		"WEATHER_PRESSURE_MAX": 1050.0,
		"WEATHER_PRESSURE_MIN": 950.0,
		"WEATHER_SEASON_KEYS": ["spring", "summer", "autumn", "winter"],
		"WEATHER_SNOW_TEMP_THRESHOLD": 2.0,
		"WEATHER_STATES": {
			"clear": {
				"affinity": {"cold": 0.1, "dry": 1.2, "hot": 0.3},
				"family": "clear",
				"humidity_mod": -20.0,
				"name": "晴",
				"precip_mm": 0.0,
				"pressure_delta": 8.0,
				"temp_delta": 2.0,
				"visibility_mod": 15.0,
				"wind_mod": -1.0,
			},
			"cold_wave": {
				"affinity": {"cold": 2.0, "dry": 0.8},
				"cold_gate": true,
				"family": "cold",
				"humidity_mod": -6.0,
				"name": "寒潮",
				"precip_mm": 0.0,
				"pressure_delta": 6.0,
				"temp_delta": -10.0,
				"visibility_mod": 2.0,
				"wind_mod": 4.0,
			},
			"dust": {
				"affinity": {"dry": 1.6, "wind": 0.8},
				"dust": true,
				"family": "dust",
				"humidity_mod": -15.0,
				"name": "沙尘",
				"precip_mm": 0.0,
				"pressure_delta": -2.0,
				"temp_delta": 0.0,
				"visibility_mod": -30.0,
				"wind_mod": 6.0,
			},
			"fog": {
				"affinity": {"cloud": 0.7, "wet": 0.5},
				"family": "fog",
				"humidity_mod": 30.0,
				"name": "雾",
				"precip_mm": 0.0,
				"pressure_delta": 1.0,
				"temp_delta": -1.0,
				"visibility_mod": -35.0,
				"wind_mod": -2.0,
			},
			"freezing_rain": {
				"affinity": {"cold": 1.2, "wet": 0.9},
				"family": "storm",
				"freezing": true,
				"humidity_mod": 22.0,
				"name": "冻雨",
				"precip_mm": 8.0,
				"pressure_delta": -10.0,
				"temp_delta": -2.0,
				"visibility_mod": -12.0,
				"wind_mod": 1.5,
			},
			"gale": {
				"affinity": {"wind": 2.0},
				"family": "wind",
				"humidity_mod": -5.0,
				"name": "大风",
				"precip_mm": 0.0,
				"pressure_delta": -4.0,
				"temp_delta": -1.0,
				"visibility_mod": -6.0,
				"wind_mod": 12.0,
			},
			"hail": {
				"affinity": {"cold": 0.4, "wet": 1.0},
				"family": "storm",
				"humidity_mod": 20.0,
				"name": "冰雹",
				"precip_mm": 15.0,
				"pressure_delta": -14.0,
				"temp_delta": -3.0,
				"visibility_mod": -16.0,
				"wind_mod": 6.0,
			},
			"haze": {
				"affinity": {"cloud": 0.5, "dry": 0.4},
				"family": "haze",
				"humidity_mod": 10.0,
				"name": "霾",
				"precip_mm": 0.0,
				"pressure_delta": 2.0,
				"temp_delta": 0.0,
				"visibility_mod": -28.0,
				"wind_mod": -2.5,
			},
			"heat": {
				"affinity": {"dry": 0.7, "hot": 2.0},
				"family": "heat",
				"hot_gate": true,
				"humidity_mod": -5.0,
				"name": "高温",
				"precip_mm": 0.0,
				"pressure_delta": 2.0,
				"temp_delta": 8.0,
				"visibility_mod": 2.0,
				"wind_mod": -0.5,
			},
			"heavy_rain": {
				"affinity": {"wet": 1.5},
				"family": "rain",
				"humidity_mod": 28.0,
				"name": "大雨",
				"precip_mm": 30.0,
				"pressure_delta": -12.0,
				"temp_delta": -3.0,
				"visibility_mod": -12.0,
				"wind_mod": 2.0,
			},
			"heavy_snow": {
				"affinity": {"cold": 1.4, "wet": 1.0},
				"family": "snow",
				"humidity_mod": 24.0,
				"name": "大雪",
				"precip_mm": 18.0,
				"pressure_delta": -11.0,
				"snow": true,
				"temp_delta": -3.0,
				"visibility_mod": -14.0,
				"wind_mod": 2.0,
			},
			"light_rain": {
				"affinity": {"wet": 1.0},
				"family": "rain",
				"humidity_mod": 15.0,
				"name": "小雨",
				"precip_mm": 3.0,
				"pressure_delta": -5.0,
				"temp_delta": -1.0,
				"visibility_mod": -5.0,
				"wind_mod": 0.5,
			},
			"light_snow": {
				"affinity": {"cold": 1.0, "wet": 0.6},
				"family": "snow",
				"humidity_mod": 12.0,
				"name": "小雪",
				"precip_mm": 2.0,
				"pressure_delta": -4.0,
				"snow": true,
				"temp_delta": -1.0,
				"visibility_mod": -4.0,
				"wind_mod": 0.5,
			},
			"moderate_rain": {
				"affinity": {"wet": 1.3},
				"family": "rain",
				"humidity_mod": 22.0,
				"name": "中雨",
				"precip_mm": 12.0,
				"pressure_delta": -8.0,
				"temp_delta": -2.0,
				"visibility_mod": -8.0,
				"wind_mod": 1.0,
			},
			"moderate_snow": {
				"affinity": {"cold": 1.2, "wet": 0.8},
				"family": "snow",
				"humidity_mod": 18.0,
				"name": "中雪",
				"precip_mm": 8.0,
				"pressure_delta": -7.0,
				"snow": true,
				"temp_delta": -2.0,
				"visibility_mod": -8.0,
				"wind_mod": 1.0,
			},
			"overcast": {
				"affinity": {"cloud": 1.0, "wet": 0.3},
				"family": "cloud",
				"humidity_mod": 8.0,
				"name": "阴",
				"precip_mm": 0.0,
				"pressure_delta": -3.0,
				"temp_delta": -1.0,
				"visibility_mod": -3.0,
				"wind_mod": 0.0,
			},
			"partly_cloudy": {
				"affinity": {"cloud": 0.6, "dry": 0.4},
				"family": "cloud",
				"humidity_mod": -5.0,
				"name": "多云",
				"precip_mm": 0.0,
				"pressure_delta": 3.0,
				"temp_delta": 1.0,
				"visibility_mod": 8.0,
				"wind_mod": 0.0,
			},
			"rainstorm": {
				"affinity": {"wet": 1.8},
				"family": "storm",
				"humidity_mod": 33.0,
				"name": "暴雨",
				"precip_mm": 70.0,
				"pressure_delta": -18.0,
				"temp_delta": -4.0,
				"visibility_mod": -18.0,
				"wind_mod": 4.0,
			},
			"snowstorm": {
				"affinity": {"cold": 1.5, "wet": 1.1, "wind": 0.6},
				"family": "storm",
				"humidity_mod": 30.0,
				"name": "暴雪",
				"precip_mm": 35.0,
				"pressure_delta": -16.0,
				"snow": true,
				"temp_delta": -4.0,
				"visibility_mod": -22.0,
				"wind_mod": 6.0,
			},
			"thunderstorm": {
				"affinity": {"hot": 0.5, "wet": 1.4},
				"family": "storm",
				"humidity_mod": 25.0,
				"name": "雷阵雨",
				"precip_mm": 25.0,
				"pressure_delta": -15.0,
				"temp_delta": -1.0,
				"visibility_mod": -14.0,
				"wind_mod": 5.0,
			},
		},
		"WEATHER_STATE_ORDER": ["clear", "partly_cloudy", "overcast", "light_rain", "moderate_rain", "heavy_rain", "rainstorm", "thunderstorm", "hail", "freezing_rain", "light_snow", "moderate_snow", "heavy_snow", "snowstorm", "fog", "haze", "dust", "heat", "cold_wave", "gale"],
		"WEATHER_TEMP_MAX": 60.0,
		"WEATHER_TEMP_MIN": -60.0,
		"WEATHER_TEMP_NOISE_SIGMA": 2.0,
		"WEATHER_VISIBILITY_MAX": 50.0,
		"WEATHER_VISIBILITY_MIN": 0.0,
		"WEATHER_WIND_MAX": 60.0,
		"WEATHER_WIND_MIN": 0.0,
	},
	"company": {"COMPANY_BASE_CONVERSION": 0.5, "COMPANY_CUSTOMERS_PER_SQM": 0.3, "COMPANY_LIQUIDATION_RATIO": 0.5, "COMPANY_LOYALTY_UNPAID_PENALTY": 8.0, "COMPANY_MONTH_DAYS": 30, "COMPANY_REFERENCE_MARKUP": 1.5, "COMPANY_REPUTATION_GAIN_PER_DAY": 0.2, "COMPANY_REPUTATION_LOSS_SHORTAGE": 1.0, "COMPANY_RESIGN_CHANCE": 0.3, "COMPANY_RESIGN_LOYALTY_THRESHOLD": 20.0},
	"consumer_protection": {
		"CP_CHANNEL_WEIGHTS": {"class_action": 0.9, "consumer_association": 0.7, "hotline_12315": 0.6, "litigation": 0.85, "negotiate": 0.25, "platform": 0.4},
		"CP_RETURN_WINDOW_DAYS": 7,
		"CP_THREE_GUARANTEE_DAYS": 15,
		"CP_WARRANTY_DEFECT_DAYS": 180,
	},
	"core": {
		"day_phases": {"dawn_start_hour": 5, "day_start_hour": 8, "dusk_start_hour": 18, "night_start_hour": 21},
		"defaults": {"minutes_per_day": 1440, "relation_annual_decay_k": 0.05},
		"note": "数值基线核心段。真源目录：shared/consistency/baseline/。本文件同时决定生成的一致性快照 shared/consistency/vectors/baseline.json 的形状；其余分域文件为 {常量名: 值}。由 tools/genbaseline 生成 client/sim/baseline_generated.gd 与 server/internal/sim/baseline_generated.go。",
		"ranges": {
			"attribute": [0, 100],
			"awe": [0, 100],
			"favor": [-100, 100],
			"grudge": [-100, 100],
			"intimacy": [0, 100],
			"personality": [0, 100],
			"skill": [0, 20],
			"trust": [0, 100],
			"values_axis": [0, 100],
		},
		"spec": "numeric_baseline",
		"speed_levels": [0, 1, 2, 4, 60, 3600, 86400],
		"version": 2,
	},
	"debt_service": {
		"DS_BANKRUPTCY_ERA_START": 2021,
		"DS_BUSINESSES": {
			"consumer_finance": {"collateral_required": false, "era": "all", "name": "消费金融", "rate_cap": 0.24, "requires_license": true},
			"crowdfunding": {"collateral_required": false, "era": "all", "name": "众筹", "rate_cap": 0.0, "requires_license": true},
			"micro_loan": {"collateral_required": false, "era": "all", "name": "小额信贷", "rate_cap": 0.24, "requires_license": true},
			"p2p": {"collateral_required": false, "era": "2013-2020", "name": "P2P", "rate_cap": 0.24, "requires_license": true},
			"pawn": {"collateral_required": true, "era": "all", "name": "典当", "rate_cap": 0.36, "requires_license": true},
			"private_lending": {"collateral_required": false, "era": "all", "name": "民间借贷", "rate_cap": 0.36, "requires_license": false},
		},
		"DS_COLLECTION_MODES": {
			"harassment": {"legal": false, "name": "骚扰", "severity": 0.4},
			"home_visit": {"legal": false, "name": "上门施压", "severity": 0.65},
			"litigation": {"legal": true, "name": "起诉", "severity": 0.2},
			"reminder": {"legal": true, "name": "短信电话提醒", "severity": 0.1},
			"violence": {"legal": false, "name": "暴力催收", "severity": 0.9},
		},
		"DS_INTEREST_RATE_CAP": 0.36,
		"DS_P2P_ERA_END": 2020,
		"DS_P2P_ERA_START": 2013,
	},
	"digital": {
		"DIGITAL_ADDICTION_THRESHOLD_HOURS": 8.0,
		"DIGITAL_CONTENT_PLATFORMS": {
			"livestream": {"base_views": 20000, "conversion": 0.05, "cut": 0.3, "name": "直播", "tip_rate": 0.02},
			"short_video": {"base_views": 60000, "conversion": 0.08, "cut": 0.2, "name": "短视频", "tip_rate": 0.005},
		},
		"DIGITAL_HACK_TARGETS": {
			"black_market": {"base_gain": 800000, "difficulty": 12.0, "exposure": 0.5, "fine": 300000, "name": "黑产", "sentence_days": 365, "wanted": 1},
			"enterprise": {"base_gain": 500000, "difficulty": 10.0, "exposure": 0.4, "fine": 500000, "name": "企业", "sentence_days": 730, "wanted": 2},
			"government": {"base_gain": 2000000, "difficulty": 15.0, "exposure": 0.6, "fine": 2000000, "name": "政府", "sentence_days": 1825, "wanted": 3},
			"personal": {"base_gain": 20000, "difficulty": 6.0, "exposure": 0.25, "fine": 50000, "name": "个人", "sentence_days": 180, "wanted": 1},
		},
		"DIGITAL_SECURITY_JOBS": {
			"breach_disposal": {"difficulty": 10.0, "income": 200000, "name": "数据泄露处置", "reputation": 1.5},
			"defense": {"difficulty": 7.0, "income": 90000, "name": "安全防护", "reputation": 0.8},
			"incident_response": {"difficulty": 9.0, "income": 150000, "name": "应急响应", "reputation": 1.2},
			"pentest": {"difficulty": 8.0, "income": 120000, "name": "渗透测试", "reputation": 1.0},
		},
	},
	"dining": {"DINING_BASE_INCIDENT_PENALTY": 200000, "DINING_DAILY_RENT_DAYS": 30.0, "DINING_DEFAULT_TASTE": 65.0, "DINING_PACKAGING_COST": 300, "DINING_POACH_THRESHOLD": 40.0, "DINING_RECALL_UNIT_COST": 2000, "DINING_REFERENCE_STAFF": 5.0},
	"disability_elderly": {
		"DE_CARE_MODES": {
			"community_care": {"cost_per_month": 600000, "happiness": 2.0, "life_modifier": 0.1, "name": "社区养老", "quality": 0.65},
			"home_care": {"cost_per_month": 400000, "happiness": 0.0, "life_modifier": 0.0, "name": "居家护理", "quality": 0.5},
			"institution_care": {"cost_per_month": 1200000, "happiness": -1.0, "life_modifier": 0.2, "name": "机构养老", "quality": 0.8},
		},
		"DE_DEVICES": {
			"accessibility": {
				"cost": 500000,
				"mobility_bonus": 0.2,
				"name": "无障碍改造",
				"types": ["physical", "sensory"],
			},
			"guide_dog": {
				"cost": 300000,
				"mobility_bonus": 0.35,
				"name": "导盲犬",
				"types": ["sensory"],
			},
			"hearing_aid": {
				"cost": 200000,
				"mobility_bonus": 0.1,
				"name": "助听器",
				"types": ["sensory"],
			},
			"prosthesis": {
				"cost": 1500000,
				"mobility_bonus": 0.4,
				"name": "义肢",
				"types": ["physical"],
			},
			"rehab": {
				"cost": 100000,
				"mobility_bonus": 0.15,
				"name": "康复训练",
				"types": ["physical", "sensory", "intellectual", "mental"],
			},
			"wheelchair": {
				"cost": 800000,
				"mobility_bonus": 0.5,
				"name": "轮椅",
				"types": ["physical"],
			},
		},
		"DE_SEVERITY_PENALTY": {"heavy": 0.75, "light": 0.15, "medium": 0.4},
	},
	"documents": {"DOC_MINUTES_PER_YEAR": 525960, "DOC_PHOTO_MATCH_THRESHOLD": 0.75},
	"domain_wake": {"WAKE_EPSILON": 1e-06, "WAKE_MINUTES_PER_DAY": 1440},
	"economy": {
		"BANK_CREDIT_MAX": 1000,
		"BANK_CREDIT_MIN": 0,
		"BANK_CREDIT_OVERDUE_PENALTY": 100,
		"BANK_CREDIT_START": 700,
		"BANK_DEFAULT_OVERDUE_DAYS": 0,
		"BANK_DEMAND_RATE_ANNUAL": 0.003,
		"BANK_FIXED_RATE_ANNUAL": 0.02,
		"BANK_LOAN_RATE_ANNUAL": 0.05,
		"BANK_OVERDUE_DAYS_DOWNGRADE": 30,
		"CURRENCIES": {
			"CNY": {"name": "人民币", "rate": 7.0},
			"EUR": {"name": "欧元", "rate": 0.92},
			"GBP": {"name": "英镑", "rate": 0.8},
			"JPY": {"name": "日元", "rate": 150.0},
			"KRW": {"name": "韩元", "rate": 1350.0},
			"USD": {"name": "美元", "rate": 1.0},
		},
		"CURRENCY_BASE": "USD",
		"EMPLOYMENT_BASE_HIRE_DIFFICULTY": 0.7,
		"EMPLOYMENT_UNEMPLOYMENT_SENSITIVITY": 3.0,
		"EMPLOYMENT_WAGE_UNEMPLOYMENT_SENSITIVITY": 1.5,
		"FX_ANNUAL_VOLATILITY": 0.08,
		"FX_FEE_RATE": 0.001,
		"FX_MEAN_REVERSION": 0.15,
		"FX_SPREAD_BPS": 50.0,
		"GBM_CRYPTO_VOLATILITY": 0.8,
		"GBM_DRIFT_DEFAULT": 0.08,
		"GBM_DRIFT_MAX": 0.15,
		"GBM_DRIFT_MIN": 0.05,
		"GBM_PRICE_FLOOR": 1e-06,
		"GBM_VOLATILITY_DEFAULT": 0.3,
		"GBM_VOLATILITY_MAX": 0.5,
		"GBM_VOLATILITY_MIN": 0.2,
		"INDIVIDUAL_TRADE_INFLUENCE": 1e-06,
		"INSURANCE_PAYOUT_RATE": 1.0,
		"INSURANCE_PREMIUM_RATE": 0.02,
		"LOTTERY_PAYOUT_MINOR": 10000,
		"LOTTERY_TICKET_PRICE_MINOR": 200,
		"LOTTERY_WIN_CHANCE": 0.001,
		"MACRO_BASE_INFLATION": 0.02,
		"MACRO_BASE_RATE": 0.03,
		"MACRO_BIRTH_RATE": 0.012,
		"MACRO_CYCLE_GDP_EFFECT": {"boom": 0.05, "recession": -0.04, "recovery": 0.02, "slowdown": 0.01},
		"MACRO_CYCLE_MAX_QUARTERS": 16,
		"MACRO_CYCLE_MIN_QUARTERS": 4,
		"MACRO_CYCLE_PHASES": ["recession", "recovery", "boom", "slowdown"],
		"MACRO_DEATH_RATE": 0.008,
		"MACRO_GDP_GROWTH_BASE": 0.03,
		"MACRO_INFLATION_MAX": 3.0,
		"MACRO_INFLATION_MIN": -0.05,
		"MACRO_INFLATION_UNEMPLOYMENT_TRADEOFF": 0.4,
		"MACRO_MIGRATION_RATE": 0.0002,
		"MACRO_PMI_BASE": 50.0,
		"MACRO_PMI_MAX": 100.0,
		"MACRO_PMI_MIN": 0.0,
		"MACRO_QUARTERS_PER_YEAR": 4,
		"MACRO_RATE_MAX": 0.5,
		"MACRO_RATE_MIN": 0.0,
		"MACRO_RATE_UNEMPLOYMENT_SENSITIVITY": 0.8,
		"MACRO_UNEMPLOYMENT_BASE": 0.05,
		"MACRO_UNEMPLOYMENT_MAX": 1.0,
		"MACRO_UNEMPLOYMENT_MIN": 0.0,
		"MACRO_WAGE_LAG_QUARTERS": 1,
		"MARGIN_INITIAL_RATIO": 0.5,
		"MARGIN_LIQUIDATION_FEE": 0.01,
		"MARGIN_MAINTENANCE_RATIO": 0.25,
		"MONEY_MINOR_SCALE": 100,
		"ORG_TRADE_INFLUENCE": 0.001,
		"PRICE_CEIL_RATIO": 5.0,
		"PRICE_DEMAND_TO_PRICE": 0.5,
		"PRICE_ELASTICITY": {"daily": 0.35, "financial": 1.2, "luxury": 0.9, "necessity": 0.15},
		"PRICE_FLOOR_RATIO": 0.2,
		"PRICE_SEASONAL_FACTORS": {"autumn": 1.05, "spring": 1.0, "summer": 1.0, "winter": 1.1},
		"TAX_CONSUMPTION_RATE": 0.1,
		"TAX_CORPORATE_RATE": 0.25,
		"TAX_EVASION_AUDIT_CHANCE": 0.15,
		"TAX_INCOME_BRACKETS": [
			{"rate": 0.03, "upper": 36000.0},
			{"rate": 0.1, "upper": 144000.0},
			{"rate": 0.2, "upper": 300000.0},
			{"rate": 0.25, "upper": 420000.0},
			{"rate": 0.3, "upper": 660000.0},
			{"rate": 0.35, "upper": 960000.0},
			{"rate": 0.45, "upper": -1.0},
		],
		"TAX_INHERITANCE_BRACKETS": [
			{"rate": 0.0, "upper": 500000.0},
			{"rate": 0.1, "upper": 1e+06},
			{"rate": 0.2, "upper": 3e+06},
			{"rate": 0.3, "upper": 1e+07},
			{"rate": 0.45, "upper": -1.0},
		],
		"TAX_PROPERTY_RATE_ANNUAL": 0.012,
		"TAX_SOCIAL_SECURITY_RATE": 0.08,
		"TAX_STAMP_RATE": 0.001,
		"TAX_STANDARD_DEDUCTION": 6000.0,
		"TAX_TYPES": ["income", "corporate", "vat", "consumption", "property", "inheritance", "stamp", "social_security"],
		"TAX_VAT_RATE": 0.13,
	},
	"education": {"EDU_EXAM_PASS_MARGIN": 0.0, "EDU_STUDY_RATE": 12.0},
	"emergency": {
		"EM_COMMAND_FAULT_LINE": 0.5,
		"EM_DEFAULT_RESPONSE_CAP": 60.0,
		"EM_PROFESSIONS": {
			"coast_guard": {
				"base_response": 15.0,
				"equipment": ["patrol_boat", "life_raft", "sonar"],
				"name": "海警",
			},
			"earthquake_rescue": {
				"base_response": 20.0,
				"equipment": ["hydraulic_tool", "search_dog", "rescue_bed"],
				"name": "地震救援",
			},
			"ems": {
				"base_response": 6.0,
				"equipment": ["ambulance", "defibrillator", "stretcher"],
				"name": "急救",
			},
			"fire": {
				"base_response": 8.0,
				"equipment": ["fire_truck", "aerial_ladder", "breathing_apparatus"],
				"name": "消防",
			},
			"flood_rescue": {
				"base_response": 18.0,
				"equipment": ["rubber_boat", "life_jacket", "pump"],
				"name": "洪水救援",
			},
			"mountain_rescue": {
				"base_response": 30.0,
				"equipment": ["rope_kit", "helicopter", "thermal_drone"],
				"name": "山地救援",
			},
		},
		"EM_SECONDARY_BASE_RISK": 0.15,
		"EM_SURVIVAL_TREATED": 0.9,
		"EM_SURVIVAL_UNTREATED": 0.35,
	},
	"engineering": {
		"ENGINEERING_ACCEPTANCE_QUALITY_THRESHOLD": 0.6,
		"ENGINEERING_CHAIN": ["survey", "design", "cost_estimation", "construction", "supervision", "acceptance"],
		"ENGINEERING_PROCUREMENT_MODES": {
			"government_tender": {"name": "政府招投标"},
			"private": {"name": "私人工程"},
		},
		"ENGINEERING_QUALIFICATIONS": {
			"first": {"bid_bonus": 0.08, "max_scale": 300000000, "min_capital": 10000000, "name": "一级"},
			"second": {"bid_bonus": 0.0, "max_scale": 80000000, "min_capital": 2000000, "name": "二级"},
			"special": {"bid_bonus": 0.15, "max_scale": 1000000000, "min_capital": 50000000, "name": "特级"},
		},
		"ENGINEERING_STAGES": {
			"acceptance": {"cost_ratio": 0.01, "duration_ratio": 0.03, "name": "验收", "quality_weight": 0.1},
			"construction": {"cost_ratio": 0.7, "duration_ratio": 0.55, "name": "施工", "quality_weight": 0.4},
			"cost_estimation": {"cost_ratio": 0.02, "duration_ratio": 0.04, "name": "造价", "quality_weight": 0.05},
			"design": {"cost_ratio": 0.07, "duration_ratio": 0.15, "name": "设计", "quality_weight": 0.2},
			"supervision": {"cost_ratio": 0.03, "duration_ratio": 0.1, "name": "监理", "quality_weight": 0.15},
			"survey": {"cost_ratio": 0.03, "duration_ratio": 0.08, "name": "勘察", "quality_weight": 0.1},
		},
		"ENGINEERING_ZONE_TYPES": {
			"commercial": {"land_mult": 1.8, "name": "商业区", "population_pull": 0.3, "traffic_demand": 1.0},
			"green": {"land_mult": 0.5, "name": "绿地", "population_pull": 0.2, "traffic_demand": 0.2},
			"industrial": {"land_mult": 0.7, "name": "工业区", "population_pull": 0.4, "traffic_demand": 0.8},
			"mixed": {"land_mult": 1.3, "name": "综合区", "population_pull": 0.8, "traffic_demand": 0.9},
			"residential": {"land_mult": 1.0, "name": "居住区", "population_pull": 1.0, "traffic_demand": 0.6},
		},
	},
	"entertainment": {"ENT_ADDICTION_THRESHOLD": 60.0},
	"environment": {"ENV_CARBON_FINE_MULTIPLIER": 3.0, "ENV_DEFAULT_CARBON_PRICE": 100, "ENV_ESG_EMISSION_PENALTY": 0.5, "ENV_ESG_FINE_DIVISOR": 100000.0, "ENV_ESG_FRAUD_PENALTY": 30.0, "ENV_ESG_GRADE_A": 80.0, "ENV_ESG_GRADE_B": 65.0, "ENV_ESG_GRADE_C": 50.0, "ENV_ESG_GREEN_INVESTMENT_CAP": 15.0, "ENV_ESG_GREEN_INVESTMENT_UNIT": 1e+06, "ENV_ESG_ILLEGAL_PENALTY": 20.0, "ENV_ESG_SCORE_MAX": 100.0, "ENV_FOOTPRINT_SCOPE1": 0.5, "ENV_FOOTPRINT_SCOPE2": 0.3, "ENV_FOOTPRINT_SCOPE3": 0.2},
	"epidemic": {
		"SEIR_ALERT_ALERT_OCCUPANCY": 1.0,
		"SEIR_ALERT_ALERT_PREVALENCE": 0.005,
		"SEIR_ALERT_EMERGENCY_OCCUPANCY": 1.5,
		"SEIR_ALERT_EMERGENCY_PREVALENCE": 0.02,
		"SEIR_ALERT_WATCH_PREVALENCE": 0.0005,
		"SEIR_BEDS_DIVISOR": 1000.0,
		"SEIR_BETA_REDUCTION_CAP": 0.95,
		"SEIR_DEFAULT_PARAMS": {"beta": 0.5, "gamma": 0.1, "immunity_days": 180.0, "mortality": 0.01, "mutation_rate": 0.001, "sigma": 0.2},
		"SEIR_DEFAULT_VACCINE_HESITANCY": 0.2,
		"SEIR_DOCTORS_DIVISOR": 500.0,
		"SEIR_IMMUNITY_WANE_RATE": 0.1,
		"SEIR_POLICY_BETA_REDUCTION": {"lockdown": 0.6, "mask": 0.15, "quarantine": 0.3, "school_closure": 0.2, "travel_restriction": 0.25, "vaccine_mandate": 0.1},
		"SEIR_POLICY_ECONOMY_COST": {"lockdown": 0.05, "mask": 0.002, "quarantine": 0.02, "school_closure": 0.02, "travel_restriction": 0.03, "vaccine_mandate": 0.004},
		"SEIR_POLICY_TRUST_PENALTY": 0.02,
		"SEIR_STAGE_DECLINING_RATIO": 0.01,
		"SEIR_STAGE_PEAK_RATIO": 0.98,
		"SEIR_STAGE_RESOLVED_INFECTIOUS": 0.5,
		"SEIR_SURGE_EXTRA_SLOPE": 0.5,
		"SEIR_TEST_KITS_DIVISOR": 100.0,
		"SEIR_VACCINE_ACCEPTANCE_NOISE": 0.1,
		"SEIR_VACCINE_STOCK_DIVISOR": 250.0,
		"SEIR_VENTILATORS_DIVISOR": 20000.0,
	},
	"era": {
		"ERA_COUNT": 9,
		"ERA_DEFINITIONS": [
			{
				"description": "以采集、狩猎与打制石器为生。",
				"forecast_accuracy": 0.3,
				"key": "stone",
				"name": "石器",
				"start_year": -10000,
				"tags": ["fire", "stone_tools", "tribe"],
			},
			{
				"description": "定居耕作、陶器与早期文字。",
				"forecast_accuracy": 0.4,
				"key": "agrarian",
				"name": "农业",
				"start_year": -3000,
				"tags": ["agriculture", "pottery", "early_writing"],
			},
			{
				"description": "城邦与帝国、哲学与铸币。",
				"forecast_accuracy": 0.46,
				"key": "classical",
				"name": "古典",
				"start_year": -800,
				"tags": ["philosophy", "empire", "coinage"],
			},
			{
				"description": "封建秩序、远洋航行与火药初现。",
				"forecast_accuracy": 0.52,
				"key": "medieval",
				"name": "中世纪",
				"start_year": 500,
				"tags": ["feudalism", "compass", "gunpowder_early"],
			},
			{
				"description": "蒸汽、工厂与铁路。",
				"forecast_accuracy": 0.62,
				"key": "industrial",
				"name": "工业",
				"start_year": 1700,
				"tags": ["steam", "factory", "railway"],
			},
			{
				"description": "电力、电话与汽车。",
				"forecast_accuracy": 0.7,
				"key": "electric",
				"name": "电气",
				"start_year": 1870,
				"tags": ["electricity", "telephone", "automobile"],
			},
			{
				"description": "计算机、互联网与卫星。",
				"forecast_accuracy": 0.85,
				"key": "information",
				"name": "信息",
				"start_year": 1970,
				"tags": ["computer", "internet", "satellite"],
			},
			{
				"description": "人工智能、生物科技与新能源。",
				"forecast_accuracy": 0.93,
				"key": "intelligent",
				"name": "智能",
				"start_year": 2020,
				"tags": ["ai", "biotech", "renewable"],
			},
			{
				"description": "聚变、星际航行与外星殖民。",
				"forecast_accuracy": 0.98,
				"key": "interstellar",
				"name": "星际",
				"start_year": 2100,
				"tags": ["fusion", "spacefaring", "colony"],
			},
		],
	},
	"events": {"EVENT_DEFAULT_GLOBAL_DAILY_CAP": 3, "EVENT_MINUTES_PER_DAY": 1440},
	"events_expo": {"EXPO_BASE_LIABILITY": 500000, "EXPO_EXP_PER_EVENT": 20, "EXPO_SECURITY_SAFE_LEVEL": 0.6},
	"family": {"FAM_CHILD_DAILY_EXPENSE": 10000, "FAM_CONFESS_BASE": 0.25, "FAM_DIVORCE_ASSET_SPLIT": 0.5, "FAM_DIVORCE_MOOD_PENALTY": 25.0, "FAM_ELDER_DAILY_EXPENSE": 8000, "FAM_GENE_NOISE": 10.0, "FAM_HEREDITY_WEIGHT": 0.5, "FAM_MARRIAGE_FAVOR_MIN": 70.0, "FAM_MARRIAGE_INTIMACY_MIN": 70.0},
	"fashion": {"FASHION_BASE_ORDER_VALUE": 5000, "FASHION_BUBBLE_THRESHOLD": 1.8, "FASHION_INSPIRATION_WEIGHT": 0.2, "FASHION_PLAGIARISM_PENALTY": 35.0, "FASHION_SKILL_WEIGHT": 0.45, "FASHION_TREND_WEIGHT": 0.35},
	"financing": {"FIN_ANNUALIZE_DAYS": 365, "FIN_CONTROL_THRESHOLD": 0.34, "FIN_GROWTH_BONUS_CAP": 2.0, "FIN_MIN_VALUATION": 10000000, "FIN_REVENUE_MULTIPLE": 8.0, "FIN_SENTIMENT_MAX": 3.0, "FIN_SENTIMENT_MIN": 0.1, "FIN_VAM_CONTROL_TRANSFER": 0.2, "FIN_VAM_REPURCHASE_RATIO": 0.2},
	"geo_transport": {
		"EARTH_RADIUS_KM": 6371.0,
		"GEO_MIN_TOTAL_LOCATIONS": 1000,
		"TRANSPORT_CONGESTION_CATEGORIES": ["road", "urban"],
		"TRANSPORT_CONGESTION_PEAK_FACTOR": 1.5,
		"TRANSPORT_MODES": {
			"airplane": {
				"base_fare": 320.0,
				"category": "air",
				"comfort": 88.0,
				"headway_minutes": 120.0,
				"hub_type": "airport",
				"name": "飞机",
				"per_km": 0.55,
				"per_minute": 0.0,
				"requires": ["passport"],
				"speed_kmh": 800.0,
				"wait_minutes": 90.0,
			},
			"bicycle": {
				"base_fare": 1.0,
				"category": "urban",
				"comfort": 50.0,
				"headway_minutes": 0.0,
				"hub_type": "",
				"name": "自行车",
				"per_km": 0.0,
				"per_minute": 0.05,
				"requires": [],
				"speed_kmh": 15.0,
				"wait_minutes": 1.0,
			},
			"bus": {
				"base_fare": 2.0,
				"category": "urban",
				"comfort": 55.0,
				"headway_minutes": 12.0,
				"hub_type": "bus_stop",
				"name": "公交",
				"per_km": 0.1,
				"per_minute": 0.0,
				"requires": [],
				"speed_kmh": 25.0,
				"wait_minutes": 6.0,
			},
			"coach": {
				"base_fare": 4.0,
				"category": "coach",
				"comfort": 60.0,
				"headway_minutes": 45.0,
				"hub_type": "coach_station",
				"name": "长途汽车",
				"per_km": 0.22,
				"per_minute": 0.0,
				"requires": ["id_card"],
				"speed_kmh": 70.0,
				"wait_minutes": 15.0,
			},
			"high_speed_rail": {
				"base_fare": 10.0,
				"category": "rail",
				"comfort": 90.0,
				"headway_minutes": 30.0,
				"hub_type": "hsr_station",
				"name": "高铁",
				"per_km": 0.45,
				"per_minute": 0.0,
				"requires": ["id_card"],
				"speed_kmh": 250.0,
				"wait_minutes": 25.0,
			},
			"metro": {
				"base_fare": 3.0,
				"category": "urban",
				"comfort": 70.0,
				"headway_minutes": 6.0,
				"hub_type": "metro_station",
				"name": "地铁",
				"per_km": 0.15,
				"per_minute": 0.0,
				"requires": [],
				"speed_kmh": 40.0,
				"wait_minutes": 3.0,
			},
			"ride_hailing": {
				"base_fare": 9.0,
				"category": "road",
				"comfort": 80.0,
				"headway_minutes": 0.0,
				"hub_type": "",
				"name": "网约车",
				"per_km": 2.2,
				"per_minute": 0.3,
				"requires": [],
				"speed_kmh": 35.0,
				"wait_minutes": 5.0,
			},
			"self_drive": {
				"base_fare": 0.0,
				"category": "road",
				"comfort": 85.0,
				"headway_minutes": 0.0,
				"hub_type": "",
				"name": "自驾",
				"per_km": 0.7,
				"per_minute": 0.0,
				"requires": ["driver_license", "vehicle"],
				"speed_kmh": 50.0,
				"wait_minutes": 0.0,
			},
			"ship": {
				"base_fare": 8.0,
				"category": "water",
				"comfort": 82.0,
				"headway_minutes": 180.0,
				"hub_type": "port",
				"name": "轮船",
				"per_km": 0.18,
				"per_minute": 0.0,
				"requires": [],
				"speed_kmh": 40.0,
				"wait_minutes": 30.0,
			},
			"taxi": {
				"base_fare": 13.0,
				"category": "road",
				"comfort": 80.0,
				"headway_minutes": 0.0,
				"hub_type": "",
				"name": "出租",
				"per_km": 2.6,
				"per_minute": 0.0,
				"requires": [],
				"speed_kmh": 35.0,
				"wait_minutes": 3.0,
			},
			"train": {
				"base_fare": 5.0,
				"category": "rail",
				"comfort": 75.0,
				"headway_minutes": 60.0,
				"hub_type": "train_station",
				"name": "火车",
				"per_km": 0.28,
				"per_minute": 0.0,
				"requires": ["id_card"],
				"speed_kmh": 90.0,
				"wait_minutes": 20.0,
			},
			"walk": {
				"base_fare": 0.0,
				"category": "urban",
				"comfort": 40.0,
				"headway_minutes": 0.0,
				"hub_type": "",
				"name": "步行",
				"per_km": 0.0,
				"per_minute": 0.0,
				"requires": [],
				"speed_kmh": 5.0,
				"wait_minutes": 0.0,
			},
		},
		"TRANSPORT_MODE_ORDER": ["walk", "bicycle", "bus", "metro", "taxi", "ride_hailing", "self_drive", "train", "high_speed_rail", "coach", "airplane", "ship"],
		"TRANSPORT_TRANSFER_MINUTES_DEFAULT": 8.0,
	},
	"goldfinger": {"GOLDFINGER_DEFAULT_DAILY_CAP": 1000, "GOLDFINGER_FREE_REROLLS": 3, "GOLDFINGER_PITY_EPIC_AT": 20, "GOLDFINGER_PITY_LEGENDARY_AT": 60},
	"gray_market": {"GRAY_GAMBLING_ADDICTION_THRESHOLD": 60.0, "GRAY_LOAN_INTEREST_DAILY": 0.01},
	"gregorian": {"CALENDAR_EPOCH_UNIX_DAYS": 10957, "CALENDAR_MINUTES_PER_DAY": 1440},
	"happiness": {"HAPPY_EXTREME_LOW": 15.0, "HAPPY_LOW_DAYS_FOR_RISK": 30, "HAPPY_LOW_THRESHOLD": 30.0, "HAPPY_MIDLIFE_AGE_MAX": 55.0, "HAPPY_MIDLIFE_AGE_MIN": 40.0},
	"honors": {"HONOR_BIAS_BONUS": 0.1, "HONOR_ENSHRINE_MIN_PRESTIGE": 80.0, "HONOR_TIE_EPSILON": 0.01},
	"immigration": {"IMMIG_MINUTES_PER_YEAR": 525960, "IMMIG_NATURALIZE_YEARS": 5},
	"infrastructure": {"INFRA_BILL_GRACE_DAYS": 30.0, "INFRA_CREDIT_PENALTY": 30.0, "INFRA_RECONNECT_FEE": 5000},
	"inheritance": {"INHERIT_DISPUTE_BASE": 0.2, "INHERIT_DISPUTE_MULTI_HEIR_BONUS": 0.25, "INHERIT_DISPUTE_WILL_REDUCTION": 0.1},
	"jobs": {"JOB_DAYS_PER_MONTH": 30.0, "JOB_INTERVIEW_CHARM_WEIGHT": 0.15, "JOB_INTERVIEW_LUCK_WEIGHT": 0.1, "JOB_MOOD_THRESHOLD": 40.0, "JOB_PERFORMANCE_DECAY_PER_DAY": 0.1, "JOB_PERFORMANCE_GAIN_PER_HOUR": 0.25, "JOB_PROBATION_DAYS": 90, "JOB_PROMOTION_BASE_CHANCE": 0.55, "JOB_PROMOTION_INTERNAL_REP_MIN": 60.0, "JOB_PROMOTION_PERFORMANCE_MIN": 70.0, "JOB_RETIREMENT_PENSION_RATE": 0.02, "JOB_RETIREMENT_YEARS_REQUIRED": 20.0, "JOB_WORK_MOOD_PER_HOUR": 1.5, "JOB_WORK_STAMINA_PER_HOUR": 6.0},
	"justice": {"JUSTICE_LAWYER_FEE_PER_LEVEL": 200000},
	"language": {"LANG_BASE_STUDY_GAIN": 1.2, "LANG_MAX_LEVEL": 100.0},
	"legacy": {"LEGACY_ASSET_CARRY_RATIO": 0.3, "LEGACY_BLOODLINE_PER_GEN": 0.05, "LEGACY_MAX_BLOODLINE": 1.0, "LEGACY_SKILL_MEMORY_RATIO": 0.5, "LEGACY_TALENT_SLOTS": 3},
	"manufacturing": {"MFG_DEFECT_SHARE": 0.5, "MFG_REFERENCE_LABOR": 20.0},
	"market": {"MARKET_FX_EPSILON": 1e-09, "MARKET_MIN_SUPPLY": 0.01},
	"medical": {
		"MEDICAL_FACILITIES": {
			"clinic": {
				"cost_mult": 0.7,
				"medical_level": 0.8,
				"name": "诊所",
				"reimburse": 0.5,
				"services": ["register", "consult", "medicine"],
			},
			"dental": {
				"cost_mult": 1.2,
				"medical_level": 0.9,
				"name": "牙科",
				"reimburse": 0.4,
				"services": ["register", "consult", "dental", "surgery"],
			},
			"hospital": {
				"cost_mult": 1.0,
				"medical_level": 1.0,
				"name": "综合医院",
				"reimburse": 0.7,
				"services": ["register", "consult", "admit", "surgery", "checkup"],
			},
			"pharmacy": {
				"cost_mult": 1.0,
				"medical_level": 0.7,
				"name": "药店",
				"reimburse": 0.0,
				"services": ["medicine"],
			},
			"psych_clinic": {
				"cost_mult": 1.0,
				"medical_level": 0.8,
				"name": "心理诊所",
				"reimburse": 0.3,
				"services": ["register", "consult", "therapy"],
			},
		},
		"MEDICAL_MISDIAGNOSIS_CHANCE": 0.1,
		"MEDICAL_SERVICE_COST": {"admit": 200000, "checkup": 50000, "consult": 20000, "dental": 100000, "medicine": 30000, "register": 5000, "surgery": 500000, "therapy": 30000},
		"MEDICAL_UNTREATED_FREE_DAYS": 7.0,
		"MEDICAL_UNTREATED_HEALTH_DECAY_PER_DAY": 1.0,
	},
	"mental_health": {
		"MH_EVENTS": {
			"breakup": {"mood": -15.0, "stress": 16.0},
			"debt": {"mood": -8.0, "stress": 14.0},
			"illness": {"mood": -10.0, "stress": 12.0},
			"marriage": {"mood": 12.0, "stress": 4.0},
			"praise": {"mood": 6.0, "stress": -4.0},
			"promotion": {"mood": 10.0, "stress": 6.0},
			"stay_up": {"mood": -5.0, "stress": 8.0},
			"unemployment": {"mood": -12.0, "stress": 18.0},
		},
		"MH_STRESS_DISORDER_THRESHOLD": 70.0,
		"MH_TREATMENTS": {
			"cbt": {"adherence": 0.7, "cost": 50000, "cure": 0.35, "minutes": 120, "name": "认知行为治疗", "remit": 0.45, "side_effect": 0.03},
			"crisis_intervention": {"adherence": 0.85, "cost": 80000, "cure": 0.05, "minutes": 240, "name": "重症干预", "remit": 0.75, "side_effect": 0.08},
			"hospitalization": {"adherence": 0.9, "cost": 300000, "cure": 0.2, "minutes": 14400, "name": "住院治疗", "remit": 0.6, "side_effect": 0.1},
			"medication": {"adherence": 0.65, "cost": 20000, "cure": 0.15, "minutes": 30, "name": "药物治疗", "remit": 0.6, "side_effect": 0.35},
			"psychotherapy": {"adherence": 0.8, "cost": 30000, "cure": 0.25, "minutes": 90, "name": "心理咨询", "remit": 0.5, "side_effect": 0.02},
		},
	},
	"metaphysics": {"META_CONFIRMATION_BIAS": 0.15, "META_PLACEBO_MOOD": 5.0},
	"military": {"MILITARY_DISCHARGE_PAY_PER_YEAR": 2.0, "MILITARY_ENLIST_MAX_AGE": 24.0, "MILITARY_ENLIST_MIN_AGE": 18.0, "MILITARY_ENLIST_MIN_HEALTH": 60.0, "MILITARY_GARRISON_MERIT_PER_YEAR": 2.0, "MILITARY_MISSION_BASE_CASUALTY": 0.05, "MILITARY_MISSION_MERIT_BASE": 4.0, "MILITARY_TRAINING_MERIT_PER_DAY": 0.1},
	"mining_energy": {"MINING_CONCESSION_MIN_CAPITAL": 50000000},
	"municipal": {"MUNICIPAL_FACILITY_GRADE_THRESHOLD": 0.5, "MUNICIPAL_NEGLECT_CONDITION": 0.4, "MUNICIPAL_NEGLECT_MAINTENANCE_DAYS": 365, "MUNICIPAL_ROAD_REOPEN_WINDOW_DAYS": 365},
	"npc": {"NPC_MASK": -1},
	"npc_memory": {"NPCMEM_BASE_HALF_LIFE_YEARS": 1.0, "NPCMEM_MAX_ENTRIES": 50, "NPCMEM_MAX_HALF_LIFE_YEARS": 10.0, "NPCMEM_REINFORCE_AMOUNT": 5.0},
	"orders": {"ORDER_AUTO_COMPLETE_DAYS": 3, "ORDER_MONTH_DAYS": 30, "ORDER_RETURN_WINDOW_DAYS": 7},
	"organizations": {"ORG_EXPOSE_HEAT_MAX": 200.0, "ORG_EXPOSE_HEAT_THRESHOLD": 100.0},
	"parenting": {
		"PARENT_CARE_WEIGHT": 0.2,
		"PARENT_DAILY_COST": {
			"child": {"minutes": 180, "money": 10000},
			"infant": {"minutes": 300, "money": 15000},
			"teen": {"minutes": 120, "money": 12000},
			"toddler": {"minutes": 240, "money": 12000},
		},
		"PARENT_EARLY_DEATH_RATE": 0.002,
		"PARENT_EDU_WEIGHT": 0.2,
		"PARENT_EVENTS": {
			"academic_pressure": {
				"ability": {"intelligence": 3.0},
				"personality": {"neuroticism": 2.0},
			},
			"bullying": {
				"personality": {"neuroticism": 4.0},
			},
			"illness": {
				"ability": {"physique": -3.0},
			},
			"injury": {
				"ability": {"physique": -5.0},
			},
			"rebellion": {
				"personality": {"agreeableness": -4.0, "extraversion": 2.0},
			},
			"talent_emerge": {
				"ability": {"intelligence": 5.0},
			},
		},
		"PARENT_GENE_WEIGHT": 0.5,
		"PARENT_RANDOM_WEIGHT": 0.1,
		"PARENT_STAGE_RANGE": {
			"child": [6, 12],
			"infant": [0, 3],
			"teen": [12, 18],
			"toddler": [3, 6],
		},
	},
	"personality": {"PERSONALITY_ADULT_AGE": 25.0, "PERSONALITY_ADULT_DRIFT_FACTOR": 0.25, "PERSONALITY_HEREDITY_WEIGHT": 0.5, "PERSONALITY_LIFETIME_DRIFT_CAP": 20.0, "PERSONALITY_NOISE_RANGE": 12.0, "PERSONALITY_POPULATION_BASELINE": 50.0},
	"pet": {
		"PET_DEATH_HAPPINESS_DELTA": -15.0,
		"PET_DEATH_MOOD_DELTA": -20.0,
		"PET_HUNGER_DECAY_PER_DAY": 12.0,
		"PET_LOST_BASE_RISK": 0.01,
		"PET_SPECIES": {
			"bird": {"buy_cost": 80000, "daily_minutes": 20, "feed_cost": 1000, "lifespan": 10.0, "name": "鸟", "trainability": 0.6},
			"cat": {"buy_cost": 150000, "daily_minutes": 30, "feed_cost": 2500, "lifespan": 15.0, "name": "猫", "trainability": 0.5},
			"dog": {"buy_cost": 200000, "daily_minutes": 60, "feed_cost": 3000, "lifespan": 13.0, "name": "狗", "trainability": 0.9},
			"fish": {"buy_cost": 20000, "daily_minutes": 10, "feed_cost": 500, "lifespan": 5.0, "name": "鱼", "trainability": 0.1},
			"hamster": {"buy_cost": 30000, "daily_minutes": 10, "feed_cost": 800, "lifespan": 3.0, "name": "仓鼠", "trainability": 0.2},
			"rabbit": {"buy_cost": 60000, "daily_minutes": 20, "feed_cost": 1200, "lifespan": 8.0, "name": "兔", "trainability": 0.3},
			"reptile": {"buy_cost": 500000, "daily_minutes": 15, "feed_cost": 2000, "lifespan": 20.0, "name": "爬宠", "trainability": 0.2},
		},
		"PET_STARVATION_HEALTH_LOSS": 8.0,
	},
	"police": {"POLICE_MISJUDGMENT_EVIDENCE_LINE": 0.4},
	"primary_industry": {"PRIMARY_FIRE_BASE_RISK": 0.02, "PRIMARY_FISHING_CLOSED_DAYS": 90.0},
	"prison": {"PRISON_ESCAPE_BASE": 0.05, "PRISON_PAROLE_BEHAVIOR_MIN": 60.0, "PRISON_RECIDIVISM_BASE": 0.3},
	"property": {"PROP_DEED_TAX_RATE": 0.015, "PROP_DEFAULT_TERM_YEARS": 30, "PROP_DEPRECIATION_RATE_ANNUAL": 0.02, "PROP_DOWN_PAYMENT_RATIO": 0.3, "PROP_FORECLOSE_ARREARS_MONTHS": 3, "PROP_MAINTENANCE_RATE_ANNUAL": 0.005, "PROP_MORTGAGE_RATE_ANNUAL": 0.045, "PROP_PRICE_CEIL_RATIO": 3.0, "PROP_PRICE_FLOOR_RATIO": 0.5, "PROP_RENT_YIELD_ANNUAL": 0.02},
	"region": {"REGION_BIRTH_RATE_ANNUAL": 0.012, "REGION_DAYS_PER_YEAR": 365.25, "REGION_DEATH_RATE_ANNUAL": 0.009, "REGION_ECONOMY_GROWTH_ANNUAL": 0.02, "REGION_EVENT_RATE_ANNUAL": 1.0, "REGION_INFLATION_RATE_ANNUAL": 0.02, "REGION_MIGRATION_RATE_ANNUAL": 0.0},
	"region_manager": {"REGION_ACTIVE_POP_CAP": 2000},
	"relations": {"RELATION_INTERACTION_CAP": 15.0, "RELATION_MAJOR_CAP": 60.0},
	"reputation": {"REPUTATION_HOSTILE_THRESHOLD": 40.0, "REPUTATION_MAX_REPUTATION": 100.0, "REPUTATION_MINUTES_PER_DAY": 1440.0, "REPUTATION_REACH_CIRCLE": 0.3, "REPUTATION_REACH_REGION": 0.7, "REPUTATION_REFUSE_SERVICE_THRESHOLD": 60.0},
	"research": {"RESEARCH_ERA_UNLOCK_QUALITY": 90.0, "RESEARCH_EXPERIMENT_COST": 500000, "RESEARCH_INNOVATION_WEIGHT": 0.2, "RESEARCH_INVESTMENT_WEIGHT": 0.3, "RESEARCH_LUCK_WEIGHT": 0.1, "RESEARCH_PATENT_MIN_QUALITY": 70.0, "RESEARCH_PEER_REVIEW_THRESHOLD": 50.0, "RESEARCH_PUBLISH_INCOME_PER_QUALITY": 5000, "RESEARCH_PUBLISH_PRESTIGE_FACTOR": 0.5, "RESEARCH_SKILL_WEIGHT": 0.4, "RESEARCH_STARTUP_COST": 1000000},
	"skills": {"SKILL_DIMINISH_RATE": 0.9, "SKILL_DIMINISH_START": 10, "SKILL_FORGET_PER_DAY": 0.02, "SKILL_IDLE_GRACE_DAYS": 30.0, "SKILL_INNATE_CAP": 8, "SKILL_MAX_LEVEL": 20, "SKILL_PRACTICE_BASE": 10.0, "SKILL_XP_BASE": 100.0, "SKILL_XP_EXPONENT": 1.5},
	"social_network": {"SOCNET_REACH_CIRCLE": 0.3, "SOCNET_REACH_REGION": 0.7},
	"social_welfare": {"WELFARE_DIBAO_INCOME_CEILING": 12000.0},
	"sports": {"SPORTS_AGE_DECLINE_RATE": 0.97, "SPORTS_AGE_FLOOR": 0.3, "SPORTS_DOPING_BAN_CHANCE": 0.3, "SPORTS_DOPING_BOOST": 10.0, "SPORTS_INJURY_BASE_RISK": 0.02, "SPORTS_INJURY_PENALTY": 8.0, "SPORTS_PEAK_MAX_AGE": 28, "SPORTS_PEAK_MIN_AGE": 22, "SPORTS_TRAIN_RATE": 0.4},
	"sports_industry": {"SPORTSI_AGENT_FEE_RATE": 0.1, "SPORTSI_BASE_MARKET_VALUE": 5000000, "SPORTSI_BROADCAST_BASE": 8000000, "SPORTSI_CLUB_BASE_SPONSOR": 5000000, "SPORTSI_HOME_ADVANTAGE": 5.0, "SPORTSI_PEAK_AGE_MAX": 30, "SPORTSI_PEAK_AGE_MIN": 24, "SPORTSI_TICKET_BASE_PRICE": 10000},
	"survival": {
		"ADDICTION_CRAVING_DECAY_PER_DAY": 0.5,
		"ADDICTION_DEPENDENT_MIN": 20.0,
		"ADDICTION_SEVERE_MIN": 60.0,
		"ADDICTION_SPECIES": {
			"alcohol": {"dose_gain": 4.0, "physiological": true, "relapse_rate": 0.45, "tolerance_growth": 0.03, "treatment_days": 30.0, "withdrawal_days": 10.0, "withdrawal_intensity": 8.0},
			"drug": {"dose_gain": 6.0, "physiological": true, "relapse_rate": 0.6, "tolerance_growth": 0.05, "treatment_days": 60.0, "withdrawal_days": 14.0, "withdrawal_intensity": 12.0},
			"gambling": {"dose_gain": 2.5, "physiological": false, "relapse_rate": 0.5, "tolerance_growth": 0.02, "treatment_days": 45.0, "withdrawal_days": 14.0, "withdrawal_intensity": 5.0},
			"internet": {"dose_gain": 2.0, "physiological": false, "relapse_rate": 0.35, "tolerance_growth": 0.02, "treatment_days": 30.0, "withdrawal_days": 14.0, "withdrawal_intensity": 4.0},
			"tobacco": {"dose_gain": 3.0, "physiological": true, "relapse_rate": 0.4, "tolerance_growth": 0.02, "treatment_days": 30.0, "withdrawal_days": 7.0, "withdrawal_intensity": 6.0},
		},
		"ADDICTION_TREATMENT": {
			"counseling": {"reduction": 0.2, "success_bonus": 0.15},
			"inpatient": {"reduction": 0.5, "success_bonus": 0.4},
			"substitution": {"reduction": 0.3, "success_bonus": 0.25},
		},
		"ADDICTION_WITHDRAWAL_TRIGGER_HOURS": 12.0,
		"CLEANLINESS_DECAY_PER_MIN": 0.06944444444444445,
		"DEHYDRATE_HEALTH_PER_HOUR": 4.0,
		"DYING_HEALTH_MARGIN": 30.0,
		"DYING_HEALTH_THRESHOLD": 10.0,
		"DYING_LIFESPAN_MARGIN_YEARS": 2.0,
		"HEALTH_REGEN_AGE_DECAY_PER_YEAR": 0.01,
		"HEALTH_REGEN_PER_HOUR": 1.0,
		"HUNGER_DECAY_PER_MIN": 0.21,
		"LIFESPAN_BASE_YEARS": 78.0,
		"MOOD_RECOVER_PER_HOUR": 1.0,
		"NUTRITION_AGE_BASE_YEARS": 20.0,
		"NUTRITION_AGE_SCALE_PER_YEAR": 0.01,
		"NUTRITION_DECAY_PER_DAY": {"carbs": 6.0, "fat": 3.0, "minerals": 4.0, "protein": 4.0, "vitamins": 5.0},
		"NUTRITION_EXCESS_DAYS_REQUIRED": 30.0,
		"NUTRITION_EXCESS_THRESHOLD": 85.0,
		"NUTRITION_LABOR_SCALE": 0.3,
		"NUTRITION_LIGHT_THRESHOLD": 30.0,
		"NUTRITION_SEVERE_THRESHOLD": 15.0,
		"SLEEP_DEBT_GAIN_PER_HOUR": 4.166666666666667,
		"SLEEP_DEBT_INTELLIGENCE_PENALTY_PER_HOUR": 2.0,
		"SLEEP_DEBT_MOOD_PENALTY_PER_HOUR": 3.0,
		"SLEEP_DEBT_RECOVER_PER_HOUR": 12.5,
		"SLEEP_DEBT_THRESHOLD": 60.0,
		"STAMINA_DRAIN_PER_HOUR": 20.0,
		"STAMINA_REGEN_ASLEEP_PER_HOUR": 12.5,
		"STAMINA_REGEN_AWAKE_PER_HOUR": 5.0,
		"STARVE_HEALTH_PER_HOUR": 2.0,
		"THIRST_DECAY_PER_MIN": 0.42,
	},
	"trade": {"TRADE_DEFAULT_TARIFF_RATE": 0.08, "TRADE_DEFAULT_VAT_RATE": 0.13},
	"war": {"WAR_BLACK_MARKET_PER_MOBILIZATION": 0.1, "WAR_DEBT_PER_YEAR_PER_MOBILIZATION": 500000000, "WAR_DECLARE_WAR_MIN_TENSION": 70.0, "WAR_DEFENSE_JOBS_PER_MOBILIZATION": 1e+06, "WAR_DRAFT_MAX_AGE": 35.0, "WAR_DRAFT_MIN_AGE": 18.0, "WAR_DRAFT_MIN_HEALTH": 50.0, "WAR_LIMITED_CONFLICT_TENSION": 50.0, "WAR_PRICE_SHOCK_PER_MOBILIZATION": 0.15, "WAR_RATIONING_MOBILIZATION_THRESHOLD": 0.5, "WAR_TENSION_THRESHOLD": 20.0, "WAR_TOTAL_WAR_TENSION": 80.0},
	"wishes": {"WISH_MAX_WISHES": 3},
	"workplace": {
		"WORK_DIM_MAX": 100.0,
		"WORK_EVENT_WEIGHTS": {"blame": 0.3, "credit_grab": 0.3, "report": 0.2, "take_sides": 0.2},
		"WORK_FACTION_POWER_MAX": 100.0,
		"WORK_PROMOTION_INDUSTRY_WEIGHT": 0.05,
		"WORK_PROMOTION_LUCK_WEIGHT": 0.1,
		"WORK_PROMOTION_PERFORMANCE_WEIGHT": 0.4,
		"WORK_PROMOTION_REPUTATION_WEIGHT": 0.2,
		"WORK_PROMOTION_SUPERVISOR_WEIGHT": 0.25,
		"WORK_PROMOTION_THRESHOLD": 65.0,
	},
	"world_memory": {"WMEM_BASE_HALF_LIFE_DAYS": 30.0, "WMEM_FADE_THRESHOLD": 1.0},
}
