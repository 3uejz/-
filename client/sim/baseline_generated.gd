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

const BANK_CREDIT_MAX: int = 1000

const BANK_CREDIT_MIN: int = 0

const BANK_CREDIT_OVERDUE_PENALTY: int = 100

const BANK_CREDIT_START: int = 700

const BANK_DEFAULT_OVERDUE_DAYS: int = 0

const BANK_DEMAND_RATE_ANNUAL: float = 0.003

const BANK_FIXED_RATE_ANNUAL: float = 0.02

const BANK_LOAN_RATE_ANNUAL: float = 0.05

const BANK_OVERDUE_DAYS_DOWNGRADE: int = 30

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

const HEALTH_REGEN_AGE_DECAY_PER_YEAR: float = 0.01

const HEALTH_REGEN_PER_HOUR: float = 1.0

const HUNGER_DECAY_PER_MIN: float = 0.21

const INDIVIDUAL_TRADE_INFLUENCE: float = 1e-06

const INSURANCE_PAYOUT_RATE: float = 1.0

const INSURANCE_PREMIUM_RATE: float = 0.02

const LIFESPAN_BASE_YEARS: float = 78.0

const LOTTERY_PAYOUT_MINOR: int = 10000

const LOTTERY_TICKET_PRICE_MINOR: int = 200

const LOTTERY_WIN_CHANCE: float = 0.001

const MACRO_BASE_INFLATION: float = 0.02

const MACRO_BASE_RATE: float = 0.03

const MACRO_CYCLE_GDP_EFFECT: Dictionary = {"boom": 0.05, "recession": -0.04, "recovery": 0.02, "slowdown": 0.01}

const MACRO_CYCLE_MAX_QUARTERS: int = 16

const MACRO_CYCLE_MIN_QUARTERS: int = 4

const MACRO_CYCLE_PHASES: Array = ["recession", "recovery", "boom", "slowdown"]

const MACRO_GDP_GROWTH_BASE: float = 0.03

const MACRO_INFLATION_MAX: float = 3.0

const MACRO_INFLATION_MIN: float = -0.05

const MACRO_INFLATION_UNEMPLOYMENT_TRADEOFF: float = 0.4

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

const MONEY_MINOR_SCALE: int = 100

const MOOD_RECOVER_PER_HOUR: float = 1.0

const NUTRITION_AGE_BASE_YEARS: float = 20.0

const NUTRITION_AGE_SCALE_PER_YEAR: float = 0.01

const NUTRITION_DECAY_PER_DAY: Dictionary = {"carbs": 6.0, "fat": 3.0, "minerals": 4.0, "protein": 4.0, "vitamins": 5.0}

const NUTRITION_EXCESS_DAYS_REQUIRED: float = 30.0

const NUTRITION_EXCESS_THRESHOLD: float = 85.0

const NUTRITION_LABOR_SCALE: float = 0.3

const NUTRITION_LIGHT_THRESHOLD: float = 30.0

const NUTRITION_SEVERE_THRESHOLD: float = 15.0

const ORG_TRADE_INFLUENCE: float = 0.001

const PRICE_CEIL_RATIO: float = 5.0

const PRICE_DEMAND_TO_PRICE: float = 0.5

const PRICE_ELASTICITY: Dictionary = {"daily": 0.35, "financial": 1.2, "luxury": 0.9, "necessity": 0.15}

const PRICE_FLOOR_RATIO: float = 0.2

const PRICE_SEASONAL_FACTORS: Dictionary = {"autumn": 1.05, "spring": 1.0, "summer": 1.0, "winter": 1.1}

const REGION_BIRTH_RATE_ANNUAL: float = 0.012

const REGION_DAYS_PER_YEAR: float = 365.25

const REGION_DEATH_RATE_ANNUAL: float = 0.009

const REGION_ECONOMY_GROWTH_ANNUAL: float = 0.02

const REGION_EVENT_RATE_ANNUAL: float = 1.0

const REGION_INFLATION_RATE_ANNUAL: float = 0.02

const REGION_MIGRATION_RATE_ANNUAL: float = 0.0

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

const SLEEP_DEBT_GAIN_PER_HOUR: float = 4.166666666666667

const SLEEP_DEBT_INTELLIGENCE_PENALTY_PER_HOUR: float = 2.0

const SLEEP_DEBT_MOOD_PENALTY_PER_HOUR: float = 3.0

const SLEEP_DEBT_RECOVER_PER_HOUR: float = 12.5

const SLEEP_DEBT_THRESHOLD: float = 60.0

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
