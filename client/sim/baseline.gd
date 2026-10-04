class_name Baseline
extends RefCounted
## 全局数值基线（默认值）。共享规格见 shared/consistency/vectors/baseline.json。
## 所有变量可由远程配置覆盖；属性统一 clamp 到定义区间（design.md Numeric Models）。

const ATTRIBUTE_MIN: int = 0
const ATTRIBUTE_MAX: int = 100
const PERSONALITY_MIN: int = 0
const PERSONALITY_MAX: int = 100
const VALUES_AXIS_MIN: int = 0
const VALUES_AXIS_MAX: int = 100
const SKILL_MIN: int = 0
const SKILL_MAX: int = 20
const FAVOR_MIN: int = -100
const FAVOR_MAX: int = 100
const GRUDGE_MIN: int = -100
const GRUDGE_MAX: int = 100
const TRUST_MIN: int = 0
const TRUST_MAX: int = 100
const AWE_MIN: int = 0
const AWE_MAX: int = 100
const INTIMACY_MIN: int = 0
const INTIMACY_MAX: int = 100

const RELATION_ANNUAL_DECAY_K: float = 0.05

# --- 生理生存、营养、成瘾与死亡基线（R7、R12、R43；design D3 / Numeric Models）---
# design 已明确的速率直接采用；design 只给方向性描述的速率给出可配置的平衡默认值，均可远程覆盖。
const HUNGER_DECAY_PER_MIN: float = 0.21         # design D3：约 8 游戏小时清空 → −0.21/分钟
const THIRST_DECAY_PER_MIN: float = 0.42         # design D3：约 4 游戏小时清空 → −0.42/分钟
const CLEANLINESS_DECAY_PER_MIN: float = 100.0 / 1440.0  # design：约 24 小时下降 100
# design 未给具体速率：按「清醒 24 小时积满、睡眠 8 小时清空」标定。
const SLEEP_DEBT_GAIN_PER_HOUR: float = 100.0 / 24.0
const SLEEP_DEBT_RECOVER_PER_HOUR: float = 100.0 / 8.0
const SLEEP_DEBT_THRESHOLD: float = 60.0         # design：超过 60 降低智力与心情
const SLEEP_DEBT_INTELLIGENCE_PENALTY_PER_HOUR: float = 2.0  # 超阈后智力下降速率（平衡默认）
const SLEEP_DEBT_MOOD_PENALTY_PER_HOUR: float = 3.0          # 超阈后心情下降速率（平衡默认）
const MOOD_RECOVER_PER_HOUR: float = 1.0         # 睡眠充足时心情缓慢恢复（平衡默认）
# design 未给具体速率：静息/睡眠恢复与满强度劳动消耗的平衡默认值。
const STAMINA_REGEN_AWAKE_PER_HOUR: float = 5.0
const STAMINA_REGEN_ASLEEP_PER_HOUR: float = 12.5
const STAMINA_DRAIN_PER_HOUR: float = 20.0
# design Numeric Models 的 starve_dps 为每秒扣血，这里统一为小时口径并取可玩速率。
const STARVE_HEALTH_PER_HOUR: float = 2.0        # 饱食归零后扣血
const DEHYDRATE_HEALTH_PER_HOUR: float = 4.0     # R7.3：口渴扣血高于饥饿
const HEALTH_REGEN_PER_HOUR: float = 1.0         # design：温饱且未临终时恢复，随年龄递减
const HEALTH_REGEN_AGE_DECAY_PER_YEAR: float = 0.01

# 五项营养储备每日衰减（design D3 明确给出数值）。
const NUTRITION_DECAY_PER_DAY: Dictionary = {
	"protein": 4.0, "carbs": 6.0, "fat": 3.0, "vitamins": 5.0, "minerals": 4.0,
}
const NUTRITION_AGE_SCALE_PER_YEAR: float = 0.01  # design：随年龄上调（超 20 岁起算）
const NUTRITION_AGE_BASE_YEARS: float = 20.0
const NUTRITION_LABOR_SCALE: float = 0.3          # design：随劳动强度上调
const NUTRITION_LIGHT_THRESHOLD: float = 30.0     # design：低于 30 为轻度失衡
const NUTRITION_SEVERE_THRESHOLD: float = 15.0    # design：低于 15 为重度失衡
const NUTRITION_EXCESS_THRESHOLD: float = 85.0    # design：长期 >85 判过量
const NUTRITION_EXCESS_DAYS_REQUIRED: float = 30.0  # design「达阈值日」未定值，取连续 30 日

# 成瘾五类参数（烟、酒、药物、赌博、网络）。design 明确五参数：单次累积、耐受增速、
# 戒断强度、复发率、治疗周期；具体数值为可远程覆盖的平衡默认。withdrawal_days 为戒断持续日数。
const ADDICTION_SPECIES: Dictionary = {
	"tobacco": {"dose_gain": 3.0, "tolerance_growth": 0.02, "withdrawal_intensity": 6.0, "relapse_rate": 0.40, "treatment_days": 30.0, "withdrawal_days": 7.0, "physiological": true},
	"alcohol": {"dose_gain": 4.0, "tolerance_growth": 0.03, "withdrawal_intensity": 8.0, "relapse_rate": 0.45, "treatment_days": 30.0, "withdrawal_days": 10.0, "physiological": true},
	"drug": {"dose_gain": 6.0, "tolerance_growth": 0.05, "withdrawal_intensity": 12.0, "relapse_rate": 0.60, "treatment_days": 60.0, "withdrawal_days": 14.0, "physiological": true},
	"gambling": {"dose_gain": 2.5, "tolerance_growth": 0.02, "withdrawal_intensity": 5.0, "relapse_rate": 0.50, "treatment_days": 45.0, "withdrawal_days": 14.0, "physiological": false},
	"internet": {"dose_gain": 2.0, "tolerance_growth": 0.02, "withdrawal_intensity": 4.0, "relapse_rate": 0.35, "treatment_days": 30.0, "withdrawal_days": 14.0, "physiological": false},
}
const ADDICTION_CRAVING_DECAY_PER_DAY: float = 0.5    # 未接触时 craving 自然消退
const ADDICTION_DEPENDENT_MIN: float = 20.0           # design：依赖阶段 20–59
const ADDICTION_SEVERE_MIN: float = 60.0              # design：重度阶段 60–100
const ADDICTION_WITHDRAWAL_TRIGGER_HOURS: float = 12.0  # 停用多久进入戒断中（平衡默认）
const ADDICTION_TREATMENT: Dictionary = {
	"counseling": {"reduction": 0.20, "success_bonus": 0.15},
	"substitution": {"reduction": 0.30, "success_bonus": 0.25},
	"inpatient": {"reduction": 0.50, "success_bonus": 0.40},
}

# 临终与寿命（R12、design D3）。
const LIFESPAN_BASE_YEARS: float = 78.0            # design：基础寿命约 78 岁
const DYING_HEALTH_THRESHOLD: float = 10.0         # design：健康 ≤ 10 且无治疗
const DYING_LIFESPAN_MARGIN_YEARS: float = 2.0     # design：年龄 ≥ 预估寿命 − 2
const DYING_HEALTH_MARGIN: float = 30.0            # design：且健康 < 30

# --- 区域统计快进基线（R5、R50）---
# 休眠区域唤醒时按统计模型批量补算，默认值集中于此，均可由远程配置覆盖（键名即小写常量名）。
const REGION_BIRTH_RATE_ANNUAL: float = 0.012   # 区域年出生率
const REGION_DEATH_RATE_ANNUAL: float = 0.009   # 区域年死亡率
const REGION_MIGRATION_RATE_ANNUAL: float = 0.0 # 区域年净迁移率
const REGION_ECONOMY_GROWTH_ANNUAL: float = 0.02   # 区域经济年增长率
const REGION_INFLATION_RATE_ANNUAL: float = 0.02   # 区域物价年通胀率
const REGION_EVENT_RATE_ANNUAL: float = 1.0        # 区域年均事件次数（统计快进采样用）
# 统计快进的时间换算基准：1 年按 365.25 日计，避免闰年逐日回放（R5.4 近似线性）。
const REGION_DAYS_PER_YEAR: float = 365.25

# --- 地理、场所、交通与混合地图基线（R3、R4、R42；design D2）---
# 数值默认集中于此，均可由远程配置覆盖（effective_param / effective_transport_mode）。
const EARTH_RADIUS_KM: float = 6371.0            # 真实地球平均半径（Haversine 球面距离）
const GEO_MIN_TOTAL_LOCATIONS: int = 1000        # R3.2：全球不少于 1000 个地点

# 十二种交通方式（R4.1）。speed_kmh 为平均巡航速度；
# 费用 = base_fare + per_km * 距离 + per_minute * 时长；wait_minutes 为默认候车/等待；
# headway_minutes 为班次间隔（0 表示招手即停）；comfort 0..100；
# requires 为所需证件/车辆键（R4.4）；category 用于聚合与拥堵修正。
const TRANSPORT_MODES: Dictionary = {
	"walk": {"name": "步行", "speed_kmh": 5.0, "base_fare": 0.0, "per_km": 0.0, "per_minute": 0.0, "wait_minutes": 0.0, "headway_minutes": 0.0, "comfort": 40.0, "category": "urban", "hub_type": "", "requires": []},
	"bicycle": {"name": "自行车", "speed_kmh": 15.0, "base_fare": 1.0, "per_km": 0.0, "per_minute": 0.05, "wait_minutes": 1.0, "headway_minutes": 0.0, "comfort": 50.0, "category": "urban", "hub_type": "", "requires": []},
	"bus": {"name": "公交", "speed_kmh": 25.0, "base_fare": 2.0, "per_km": 0.1, "per_minute": 0.0, "wait_minutes": 6.0, "headway_minutes": 12.0, "comfort": 55.0, "category": "urban", "hub_type": "bus_stop", "requires": []},
	"metro": {"name": "地铁", "speed_kmh": 40.0, "base_fare": 3.0, "per_km": 0.15, "per_minute": 0.0, "wait_minutes": 3.0, "headway_minutes": 6.0, "comfort": 70.0, "category": "urban", "hub_type": "metro_station", "requires": []},
	"taxi": {"name": "出租", "speed_kmh": 35.0, "base_fare": 13.0, "per_km": 2.6, "per_minute": 0.0, "wait_minutes": 3.0, "headway_minutes": 0.0, "comfort": 80.0, "category": "road", "hub_type": "", "requires": []},
	"ride_hailing": {"name": "网约车", "speed_kmh": 35.0, "base_fare": 9.0, "per_km": 2.2, "per_minute": 0.3, "wait_minutes": 5.0, "headway_minutes": 0.0, "comfort": 80.0, "category": "road", "hub_type": "", "requires": []},
	"self_drive": {"name": "自驾", "speed_kmh": 50.0, "base_fare": 0.0, "per_km": 0.7, "per_minute": 0.0, "wait_minutes": 0.0, "headway_minutes": 0.0, "comfort": 85.0, "category": "road", "hub_type": "", "requires": ["driver_license", "vehicle"]},
	"train": {"name": "火车", "speed_kmh": 90.0, "base_fare": 5.0, "per_km": 0.28, "per_minute": 0.0, "wait_minutes": 20.0, "headway_minutes": 60.0, "comfort": 75.0, "category": "rail", "hub_type": "train_station", "requires": ["id_card"]},
	"high_speed_rail": {"name": "高铁", "speed_kmh": 250.0, "base_fare": 10.0, "per_km": 0.45, "per_minute": 0.0, "wait_minutes": 25.0, "headway_minutes": 30.0, "comfort": 90.0, "category": "rail", "hub_type": "hsr_station", "requires": ["id_card"]},
	"coach": {"name": "长途汽车", "speed_kmh": 70.0, "base_fare": 4.0, "per_km": 0.22, "per_minute": 0.0, "wait_minutes": 15.0, "headway_minutes": 45.0, "comfort": 60.0, "category": "coach", "hub_type": "coach_station", "requires": ["id_card"]},
	"airplane": {"name": "飞机", "speed_kmh": 800.0, "base_fare": 320.0, "per_km": 0.55, "per_minute": 0.0, "wait_minutes": 90.0, "headway_minutes": 120.0, "comfort": 88.0, "category": "air", "hub_type": "airport", "requires": ["passport"]},
	"ship": {"name": "轮船", "speed_kmh": 40.0, "base_fare": 8.0, "per_km": 0.18, "per_minute": 0.0, "wait_minutes": 30.0, "headway_minutes": 180.0, "comfort": 82.0, "category": "water", "hub_type": "port", "requires": []},
}
const TRANSPORT_MODE_ORDER: Array = ["walk", "bicycle", "bus", "metro", "taxi", "ride_hailing", "self_drive", "train", "high_speed_rail", "coach", "airplane", "ship"]
# 道路/城市出行受实时拥堵影响；高峰时段按此系数放大耗时（R4.6、R42.6）。
const TRANSPORT_CONGESTION_PEAK_FACTOR: float = 1.5
const TRANSPORT_CONGESTION_CATEGORIES: Array = ["road", "urban"]
const TRANSPORT_TRANSFER_MINUTES_DEFAULT: float = 8.0  # 默认换乘等待（R42.6）

# --- 气候带、天气状态、气象变量、灾害与时代基线（R2、R41；design D1）---
# 10 气候带字段：base_temp 年均温；amp_temp 年振幅；amp_diurnal 昼夜振幅；phase 季节相位（弧度）；
# humidity 基准湿度；precip_scale 降水缩放；pressure 基准气压；wind 基准风速；visibility 基准能见度；
# can_snow 是否可降雪；arid 干旱程度 0..1；monsoon 季风性（夏季多雨）。
const CLIMATE_ZONES: Dictionary = {
	"tropical_rainforest": {"name": "热带雨林", "base_temp": 26.0, "amp_temp": 2.0, "amp_diurnal": 6.0, "phase": 0.0, "humidity": 85.0, "precip_scale": 12.0, "pressure": 1008.0, "wind": 2.0, "visibility": 15.0, "can_snow": false, "arid": 0.0, "monsoon": true},
	"tropical_monsoon": {"name": "热带季风", "base_temp": 26.0, "amp_temp": 6.0, "amp_diurnal": 8.0, "phase": -1.0, "humidity": 75.0, "precip_scale": 8.0, "pressure": 1008.0, "wind": 3.0, "visibility": 15.0, "can_snow": false, "arid": 0.1, "monsoon": true},
	"tropical_savanna": {"name": "热带草原", "base_temp": 27.0, "amp_temp": 5.0, "amp_diurnal": 12.0, "phase": 0.5, "humidity": 55.0, "precip_scale": 4.0, "pressure": 1010.0, "wind": 3.0, "visibility": 20.0, "can_snow": false, "arid": 0.4, "monsoon": false},
	"tropical_desert": {"name": "热带沙漠", "base_temp": 30.0, "amp_temp": 12.0, "amp_diurnal": 18.0, "phase": 0.0, "humidity": 20.0, "precip_scale": 0.3, "pressure": 1005.0, "wind": 4.0, "visibility": 25.0, "can_snow": false, "arid": 0.95, "monsoon": false},
	"subtropical_monsoon": {"name": "亚热带季风", "base_temp": 17.0, "amp_temp": 12.0, "amp_diurnal": 9.0, "phase": -0.5, "humidity": 70.0, "precip_scale": 5.0, "pressure": 1010.0, "wind": 3.0, "visibility": 12.0, "can_snow": true, "arid": 0.1, "monsoon": true},
	"mediterranean": {"name": "地中海", "base_temp": 17.0, "amp_temp": 9.0, "amp_diurnal": 9.0, "phase": 0.0, "humidity": 55.0, "precip_scale": 3.0, "pressure": 1013.0, "wind": 3.5, "visibility": 18.0, "can_snow": false, "arid": 0.5, "monsoon": false},
	"temperate_oceanic": {"name": "温带海洋", "base_temp": 11.0, "amp_temp": 7.0, "amp_diurnal": 6.0, "phase": 0.2, "humidity": 78.0, "precip_scale": 3.5, "pressure": 1012.0, "wind": 4.5, "visibility": 12.0, "can_snow": true, "arid": 0.05, "monsoon": false},
	"temperate_continental": {"name": "温带大陆", "base_temp": 8.0, "amp_temp": 16.0, "amp_diurnal": 11.0, "phase": 0.0, "humidity": 55.0, "precip_scale": 2.0, "pressure": 1014.0, "wind": 3.5, "visibility": 15.0, "can_snow": true, "arid": 0.3, "monsoon": false},
	"subarctic_conifer": {"name": "亚寒带针叶林", "base_temp": -4.0, "amp_temp": 18.0, "amp_diurnal": 9.0, "phase": 0.0, "humidity": 65.0, "precip_scale": 1.5, "pressure": 1012.0, "wind": 3.0, "visibility": 12.0, "can_snow": true, "arid": 0.2, "monsoon": false},
	"polar_highland": {"name": "极地高原", "base_temp": -20.0, "amp_temp": 15.0, "amp_diurnal": 8.0, "phase": 0.0, "humidity": 45.0, "precip_scale": 0.8, "pressure": 1008.0, "wind": 6.0, "visibility": 10.0, "can_snow": true, "arid": 0.6, "monsoon": false},
}
const CLIMATE_ZONE_ORDER: Array = ["tropical_rainforest", "tropical_monsoon", "tropical_savanna", "tropical_desert", "subtropical_monsoon", "mediterranean", "temperate_oceanic", "temperate_continental", "subarctic_conifer", "polar_highland"]

# 20 天气状态字段：precip_mm 代表日降水；humidity_mod/pressure_delta/wind_mod/visibility_mod/temp_delta
# 为相对气候带基准的修正；family 供马尔可夫链同族延续；affinity 为按气候与季节打分的倾向权重；
# snow/freezing/dust/hot/cold 为气候门闩（不满足时权重被压制）。
const WEATHER_STATES: Dictionary = {
	"clear": {"name": "晴", "precip_mm": 0.0, "humidity_mod": -20.0, "pressure_delta": 8.0, "wind_mod": -1.0, "visibility_mod": 15.0, "temp_delta": 2.0, "family": "clear", "affinity": {"dry": 1.2, "hot": 0.3, "cold": 0.1}},
	"partly_cloudy": {"name": "多云", "precip_mm": 0.0, "humidity_mod": -5.0, "pressure_delta": 3.0, "wind_mod": 0.0, "visibility_mod": 8.0, "temp_delta": 1.0, "family": "cloud", "affinity": {"cloud": 0.6, "dry": 0.4}},
	"overcast": {"name": "阴", "precip_mm": 0.0, "humidity_mod": 8.0, "pressure_delta": -3.0, "wind_mod": 0.0, "visibility_mod": -3.0, "temp_delta": -1.0, "family": "cloud", "affinity": {"cloud": 1.0, "wet": 0.3}},
	"light_rain": {"name": "小雨", "precip_mm": 3.0, "humidity_mod": 15.0, "pressure_delta": -5.0, "wind_mod": 0.5, "visibility_mod": -5.0, "temp_delta": -1.0, "family": "rain", "affinity": {"wet": 1.0}},
	"moderate_rain": {"name": "中雨", "precip_mm": 12.0, "humidity_mod": 22.0, "pressure_delta": -8.0, "wind_mod": 1.0, "visibility_mod": -8.0, "temp_delta": -2.0, "family": "rain", "affinity": {"wet": 1.3}},
	"heavy_rain": {"name": "大雨", "precip_mm": 30.0, "humidity_mod": 28.0, "pressure_delta": -12.0, "wind_mod": 2.0, "visibility_mod": -12.0, "temp_delta": -3.0, "family": "rain", "affinity": {"wet": 1.5}},
	"rainstorm": {"name": "暴雨", "precip_mm": 70.0, "humidity_mod": 33.0, "pressure_delta": -18.0, "wind_mod": 4.0, "visibility_mod": -18.0, "temp_delta": -4.0, "family": "storm", "affinity": {"wet": 1.8}},
	"thunderstorm": {"name": "雷阵雨", "precip_mm": 25.0, "humidity_mod": 25.0, "pressure_delta": -15.0, "wind_mod": 5.0, "visibility_mod": -14.0, "temp_delta": -1.0, "family": "storm", "affinity": {"wet": 1.4, "hot": 0.5}},
	"hail": {"name": "冰雹", "precip_mm": 15.0, "humidity_mod": 20.0, "pressure_delta": -14.0, "wind_mod": 6.0, "visibility_mod": -16.0, "temp_delta": -3.0, "family": "storm", "affinity": {"wet": 1.0, "cold": 0.4}},
	"freezing_rain": {"name": "冻雨", "precip_mm": 8.0, "humidity_mod": 22.0, "pressure_delta": -10.0, "wind_mod": 1.5, "visibility_mod": -12.0, "temp_delta": -2.0, "family": "storm", "freezing": true, "affinity": {"wet": 0.9, "cold": 1.2}},
	"light_snow": {"name": "小雪", "precip_mm": 2.0, "humidity_mod": 12.0, "pressure_delta": -4.0, "wind_mod": 0.5, "visibility_mod": -4.0, "temp_delta": -1.0, "family": "snow", "snow": true, "affinity": {"wet": 0.6, "cold": 1.0}},
	"moderate_snow": {"name": "中雪", "precip_mm": 8.0, "humidity_mod": 18.0, "pressure_delta": -7.0, "wind_mod": 1.0, "visibility_mod": -8.0, "temp_delta": -2.0, "family": "snow", "snow": true, "affinity": {"wet": 0.8, "cold": 1.2}},
	"heavy_snow": {"name": "大雪", "precip_mm": 18.0, "humidity_mod": 24.0, "pressure_delta": -11.0, "wind_mod": 2.0, "visibility_mod": -14.0, "temp_delta": -3.0, "family": "snow", "snow": true, "affinity": {"wet": 1.0, "cold": 1.4}},
	"snowstorm": {"name": "暴雪", "precip_mm": 35.0, "humidity_mod": 30.0, "pressure_delta": -16.0, "wind_mod": 6.0, "visibility_mod": -22.0, "temp_delta": -4.0, "family": "storm", "snow": true, "affinity": {"wet": 1.1, "cold": 1.5, "wind": 0.6}},
	"fog": {"name": "雾", "precip_mm": 0.0, "humidity_mod": 30.0, "pressure_delta": 1.0, "wind_mod": -2.0, "visibility_mod": -35.0, "temp_delta": -1.0, "family": "fog", "affinity": {"wet": 0.5, "cloud": 0.7}},
	"haze": {"name": "霾", "precip_mm": 0.0, "humidity_mod": 10.0, "pressure_delta": 2.0, "wind_mod": -2.5, "visibility_mod": -28.0, "temp_delta": 0.0, "family": "haze", "affinity": {"dry": 0.4, "cloud": 0.5}},
	"dust": {"name": "沙尘", "precip_mm": 0.0, "humidity_mod": -15.0, "pressure_delta": -2.0, "wind_mod": 6.0, "visibility_mod": -30.0, "temp_delta": 0.0, "family": "dust", "dust": true, "affinity": {"dry": 1.6, "wind": 0.8}},
	"heat": {"name": "高温", "precip_mm": 0.0, "humidity_mod": -5.0, "pressure_delta": 2.0, "wind_mod": -0.5, "visibility_mod": 2.0, "temp_delta": 8.0, "family": "heat", "hot_gate": true, "affinity": {"hot": 2.0, "dry": 0.7}},
	"cold_wave": {"name": "寒潮", "precip_mm": 0.0, "humidity_mod": -6.0, "pressure_delta": 6.0, "wind_mod": 4.0, "visibility_mod": 2.0, "temp_delta": -10.0, "family": "cold", "cold_gate": true, "affinity": {"cold": 2.0, "dry": 0.8}},
	"gale": {"name": "大风", "precip_mm": 0.0, "humidity_mod": -5.0, "pressure_delta": -4.0, "wind_mod": 12.0, "visibility_mod": -6.0, "temp_delta": -1.0, "family": "wind", "affinity": {"wind": 2.0}},
}
const WEATHER_STATE_ORDER: Array = ["clear", "partly_cloudy", "overcast", "light_rain", "moderate_rain", "heavy_rain", "rainstorm", "thunderstorm", "hail", "freezing_rain", "light_snow", "moderate_snow", "heavy_snow", "snowstorm", "fog", "haze", "dust", "heat", "cold_wave", "gale"]
const WEATHER_SEASON_KEYS: Array = ["spring", "summer", "autumn", "winter"]

# 气象变量区间（design D1 明确给出）。
const WEATHER_TEMP_MIN: float = -60.0
const WEATHER_TEMP_MAX: float = 60.0
const WEATHER_HUMIDITY_MIN: float = 0.0
const WEATHER_HUMIDITY_MAX: float = 100.0
const WEATHER_PRESSURE_MIN: float = 950.0
const WEATHER_PRESSURE_MAX: float = 1050.0
const WEATHER_WIND_MIN: float = 0.0
const WEATHER_WIND_MAX: float = 60.0
const WEATHER_VISIBILITY_MIN: float = 0.0
const WEATHER_VISIBILITY_MAX: float = 50.0
const WEATHER_PRECIP_MIN: float = 0.0
const WEATHER_PRECIP_MAX: float = 200.0

# 天气生成与预报参数（均为可远程覆盖的平衡默认）。
const WEATHER_TEMP_NOISE_SIGMA: float = 2.0      # 温度随机扰动 N(0,σ)
const WEATHER_DERIVED_NOISE_SIGMA: float = 1.5   # 湿度/气压/风速/能见度/降水扰动
const WEATHER_SNOW_TEMP_THRESHOLD: float = 2.0   # 季节均温高于此值则雪态被压制
const WEATHER_MARKOV_PERSISTENCE: float = 2.5    # 马尔可夫链自持权重
const WEATHER_MARKOV_FAMILY_CONTINUITY: float = 1.3  # 同族延续权重
const WEATHER_MIN_STATE_WEIGHT: float = 0.001
const WEATHER_MAX_HISTORY_DAYS: int = 4096       # 每区域天气历史上限（LRU 裁剪）
const WEATHER_FORECAST_DAYS: int = 7
const WEATHER_FORECAST_ACCURACY_DECAY: float = 0.82  # 逐日准确率衰减
const WEATHER_FORECAST_ACCURACY_MIN: float = 0.05
const WEATHER_DISASTER_WARNING_MIN_DAYS: int = 1
const WEATHER_DISASTER_WARNING_MAX_DAYS: int = 3
const WEATHER_DAYS_PER_YEAR: float = 365.25

# 10 类灾害。annual_rate 为年均期望频率；zones 为空表示全气候带；seasons 为空表示全年；
# warning_min/max_days 为预警窗口（design：触发前 1–3 日）。
const WEATHER_DISASTERS: Dictionary = {
	"earthquake": {"name": "地震", "annual_rate": 0.008, "zones": [], "seasons": [], "warning_min_days": 1, "warning_max_days": 1},
	"flood": {"name": "洪水", "annual_rate": 0.020, "zones": ["tropical_rainforest", "tropical_monsoon", "subtropical_monsoon", "temperate_oceanic", "tropical_savanna"], "seasons": ["summer", "autumn"], "warning_min_days": 1, "warning_max_days": 3},
	"typhoon": {"name": "台风", "annual_rate": 0.015, "zones": ["tropical_monsoon", "tropical_savanna", "subtropical_monsoon", "temperate_oceanic"], "seasons": ["summer", "autumn"], "warning_min_days": 1, "warning_max_days": 3},
	"drought": {"name": "干旱", "annual_rate": 0.020, "zones": ["tropical_desert", "tropical_savanna", "mediterranean", "subtropical_monsoon"], "seasons": ["summer"], "warning_min_days": 1, "warning_max_days": 3},
	"wildfire": {"name": "野火", "annual_rate": 0.012, "zones": ["tropical_desert", "tropical_savanna", "mediterranean", "temperate_continental"], "seasons": ["summer", "autumn"], "warning_min_days": 1, "warning_max_days": 2},
	"mudslide": {"name": "泥石流", "annual_rate": 0.005, "zones": ["tropical_rainforest", "tropical_monsoon", "subtropical_monsoon"], "seasons": ["summer", "autumn"], "warning_min_days": 1, "warning_max_days": 2},
	"tsunami": {"name": "海啸", "annual_rate": 0.002, "zones": ["tropical_monsoon", "temperate_oceanic", "mediterranean", "subtropical_monsoon"], "seasons": [], "warning_min_days": 1, "warning_max_days": 2},
	"blizzard": {"name": "暴雪", "annual_rate": 0.012, "zones": ["subarctic_conifer", "polar_highland", "temperate_continental"], "seasons": ["winter"], "warning_min_days": 1, "warning_max_days": 3},
	"hailstorm": {"name": "冰雹", "annual_rate": 0.008, "zones": ["temperate_continental", "mediterranean", "subtropical_monsoon"], "seasons": ["spring", "summer"], "warning_min_days": 1, "warning_max_days": 2},
	"locust": {"name": "蝗灾", "annual_rate": 0.006, "zones": ["tropical_savanna", "mediterranean", "subtropical_monsoon"], "seasons": ["summer", "autumn"], "warning_min_days": 1, "warning_max_days": 3},
}
const WEATHER_DISASTER_ORDER: Array = ["earthquake", "flood", "typhoon", "drought", "wildfire", "mudslide", "tsunami", "blizzard", "hailstorm", "locust"]

# 9 时代阶段（design D1）。start_year 为进入该时代的公历年阈值（闭下界）；
# forecast_accuracy 为第 1 日预报基准准确率；tags 供科技/职业/物品/政策时代门闩。
const ERA_DEFINITIONS: Array = [
	{"key": "stone", "name": "石器", "start_year": -10000, "forecast_accuracy": 0.30, "tags": ["fire", "stone_tools", "tribe"], "description": "以采集、狩猎与打制石器为生。"},
	{"key": "agrarian", "name": "农业", "start_year": -3000, "forecast_accuracy": 0.40, "tags": ["agriculture", "pottery", "early_writing"], "description": "定居耕作、陶器与早期文字。"},
	{"key": "classical", "name": "古典", "start_year": -800, "forecast_accuracy": 0.46, "tags": ["philosophy", "empire", "coinage"], "description": "城邦与帝国、哲学与铸币。"},
	{"key": "medieval", "name": "中世纪", "start_year": 500, "forecast_accuracy": 0.52, "tags": ["feudalism", "compass", "gunpowder_early"], "description": "封建秩序、远洋航行与火药初现。"},
	{"key": "industrial", "name": "工业", "start_year": 1700, "forecast_accuracy": 0.62, "tags": ["steam", "factory", "railway"], "description": "蒸汽、工厂与铁路。"},
	{"key": "electric", "name": "电气", "start_year": 1870, "forecast_accuracy": 0.70, "tags": ["electricity", "telephone", "automobile"], "description": "电力、电话与汽车。"},
	{"key": "information", "name": "信息", "start_year": 1970, "forecast_accuracy": 0.85, "tags": ["computer", "internet", "satellite"], "description": "计算机、互联网与卫星。"},
	{"key": "intelligent", "name": "智能", "start_year": 2020, "forecast_accuracy": 0.93, "tags": ["ai", "biotech", "renewable"], "description": "人工智能、生物科技与新能源。"},
	{"key": "interstellar", "name": "星际", "start_year": 2100, "forecast_accuracy": 0.98, "tags": ["fusion", "spacefaring", "colony"], "description": "聚变、星际航行与外星殖民。"},
]
const ERA_COUNT: int = 9

# =======================================================================
# 经济、金融、税制与宏观默认值（R15、R17、R48；design 经济系统、D8）。
# 金额一律以最小货币单位（分）的整数处理，避免浮点漂移；
# 价格与汇率等比率用 float，可由远程配置逐项覆盖。
# =======================================================================

const MONEY_MINOR_SCALE: int = 100  # 1 主币单位 = 100 最小单位

# 多国货币：rate 为「1 个世界记账单位（USD）可兑换的该币单位数」。
const CURRENCIES: Dictionary = {
	"USD": {"name": "美元", "rate": 1.0},
	"CNY": {"name": "人民币", "rate": 7.0},
	"EUR": {"name": "欧元", "rate": 0.92},
	"JPY": {"name": "日元", "rate": 150.0},
	"GBP": {"name": "英镑", "rate": 0.80},
	"KRW": {"name": "韩元", "rate": 1350.0},
}
const CURRENCY_BASE: String = "USD"

# 浮动汇率与换汇：GBM + 向基准均值回归；价差与手续费。
const FX_ANNUAL_VOLATILITY: float = 0.08
const FX_MEAN_REVERSION: float = 0.15
const FX_SPREAD_BPS: float = 50.0     # 买卖价差，万分之 50 = 0.5%
const FX_FEE_RATE: float = 0.001      # 换汇手续费 0.1%

# 物价分层：价格 = 基础价 × 供需 × 季节/事件 × 通胀累积，clamp 到上下限。
const PRICE_FLOOR_RATIO: float = 0.2
const PRICE_CEIL_RATIO: float = 5.0
const PRICE_DEMAND_TO_PRICE: float = 0.5
const PRICE_ELASTICITY: Dictionary = {
	"necessity": 0.15,   # 必需品刚性
	"daily": 0.35,
	"luxury": 0.90,      # 奢侈品弹性大
	"financial": 1.20,
}
const INDIVIDUAL_TRADE_INFLUENCE: float = 1e-6  # 个体交易对价格影响微弱
const ORG_TRADE_INFLUENCE: float = 1e-3         # 组织/大额交易才显著推动
const PRICE_SEASONAL_FACTORS: Dictionary = {
	"spring": 1.0, "summer": 1.0, "autumn": 1.05, "winter": 1.10,
}

# 通胀与宏观：季度 tick；指标与周期阶段。
const MACRO_QUARTERS_PER_YEAR: int = 4
const MACRO_BASE_INFLATION: float = 0.02
const MACRO_BASE_RATE: float = 0.03
const MACRO_UNEMPLOYMENT_BASE: float = 0.05
const MACRO_GDP_GROWTH_BASE: float = 0.03
const MACRO_INFLATION_MIN: float = -0.05
const MACRO_INFLATION_MAX: float = 3.0
const MACRO_UNEMPLOYMENT_MIN: float = 0.0
const MACRO_UNEMPLOYMENT_MAX: float = 1.0
const MACRO_RATE_MIN: float = 0.0
const MACRO_RATE_MAX: float = 0.5
const MACRO_PMI_MIN: float = 0.0
const MACRO_PMI_MAX: float = 100.0
const MACRO_PMI_BASE: float = 50.0
const MACRO_CYCLE_PHASES: Array = ["recession", "recovery", "boom", "slowdown"]
const MACRO_CYCLE_GDP_EFFECT: Dictionary = {
	"recession": -0.04, "recovery": 0.02, "boom": 0.05, "slowdown": 0.01,
}
const MACRO_CYCLE_MIN_QUARTERS: int = 4
const MACRO_CYCLE_MAX_QUARTERS: int = 16
const MACRO_RATE_UNEMPLOYMENT_SENSITIVITY: float = 0.8
const MACRO_INFLATION_UNEMPLOYMENT_TRADEOFF: float = 0.4
const MACRO_WAGE_LAG_QUARTERS: int = 1

# GBM 金融品种（股票/基金/外汇/大宗/加密）。
const GBM_DRIFT_DEFAULT: float = 0.08
const GBM_VOLATILITY_DEFAULT: float = 0.30
const GBM_DRIFT_MIN: float = 0.05
const GBM_DRIFT_MAX: float = 0.15
const GBM_VOLATILITY_MIN: float = 0.20
const GBM_VOLATILITY_MAX: float = 0.50
const GBM_CRYPTO_VOLATILITY: float = 0.80
const GBM_PRICE_FLOOR: float = 1e-6

# 银行存贷与信贷。
const BANK_DEMAND_RATE_ANNUAL: float = 0.003
const BANK_FIXED_RATE_ANNUAL: float = 0.02
const BANK_LOAN_RATE_ANNUAL: float = 0.05
const BANK_OVERDUE_DAYS_DOWNGRADE: int = 30
const BANK_DEFAULT_OVERDUE_DAYS: int = 0
const BANK_CREDIT_MIN: int = 0
const BANK_CREDIT_MAX: int = 1000
const BANK_CREDIT_START: int = 700
const BANK_CREDIT_OVERDUE_PENALTY: int = 100

# 保险与彩票（最小货币单位）。
const INSURANCE_PREMIUM_RATE: float = 0.02
const INSURANCE_PAYOUT_RATE: float = 1.0
const LOTTERY_TICKET_PRICE_MINOR: int = 200
const LOTTERY_PAYOUT_MINOR: int = 10000
const LOTTERY_WIN_CHANCE: float = 1.0 / 1000.0

# 杠杆与保证金。
const MARGIN_INITIAL_RATIO: float = 0.5
const MARGIN_MAINTENANCE_RATIO: float = 0.25
const MARGIN_LIQUIDATION_FEE: float = 0.01

# 税制：个人所得税 7 级超额累进（3%–45%，upper<0 表示无上限）；
# 遗产税累进；其余为比例税。
const TAX_STANDARD_DEDUCTION: float = 6000.0
const TAX_INCOME_BRACKETS: Array = [
	{"upper": 36000.0, "rate": 0.03},
	{"upper": 144000.0, "rate": 0.10},
	{"upper": 300000.0, "rate": 0.20},
	{"upper": 420000.0, "rate": 0.25},
	{"upper": 660000.0, "rate": 0.30},
	{"upper": 960000.0, "rate": 0.35},
	{"upper": -1.0, "rate": 0.45},
]
const TAX_CORPORATE_RATE: float = 0.25
const TAX_VAT_RATE: float = 0.13
const TAX_CONSUMPTION_RATE: float = 0.10
const TAX_PROPERTY_RATE_ANNUAL: float = 0.012
const TAX_STAMP_RATE: float = 0.001
const TAX_SOCIAL_SECURITY_RATE: float = 0.08
const TAX_INHERITANCE_BRACKETS: Array = [
	{"upper": 500000.0, "rate": 0.0},
	{"upper": 1000000.0, "rate": 0.10},
	{"upper": 3000000.0, "rate": 0.20},
	{"upper": 10000000.0, "rate": 0.30},
	{"upper": -1.0, "rate": 0.45},
]
const TAX_TYPES: Array = [
	"income", "corporate", "vat", "consumption",
	"property", "inheritance", "stamp", "social_security",
]
const TAX_EVASION_AUDIT_CHANCE: float = 0.15  # 逃税被稽查的基础概率

# 就业市场：失业率越高求职越难，工资随宏观滞后调整。
const EMPLOYMENT_BASE_HIRE_DIFFICULTY: float = 0.7
const EMPLOYMENT_UNEMPLOYMENT_SENSITIVITY: float = 3.0
const EMPLOYMENT_WAGE_UNEMPLOYMENT_SENSITIVITY: float = 1.5

static var _overrides: Dictionary = {}

## 应用远程配置覆盖（design.md：所有公式由远程配置覆盖默认值）。
## config 形如 {"ranges": {"skill": [0, 30]}, "relation_annual_decay_k": 0.04}。
static func apply_remote_config(config: Dictionary) -> void:
	_overrides = config.duplicate(true)

static func clear_overrides() -> void:
	_overrides = {}

## 取某属性的有效区间（远程覆盖优先）。
static func effective_range(key: String) -> Array:
	var override_ranges: Variant = _overrides.get("ranges", {})
	if override_ranges is Dictionary and override_ranges.has(key):
		return override_ranges[key]
	return ranges()[key]

static func effective_relation_decay_k() -> float:
	return float(_overrides.get("relation_annual_decay_k", RELATION_ANNUAL_DECAY_K))

## 取区域统计快进参数的有效值（远程覆盖优先）。
static func effective_region_param(key: String, default_value: float) -> float:
	return float(_overrides.get(key, default_value))

## 通用标量/字典参数覆盖（数值默认集中在 baseline，可被远程配置覆盖）。
static func effective_param(key: String, default_value: Variant) -> Variant:
	return _overrides.get(key, default_value)

## 与 shared/consistency/vectors/baseline.json 的 ranges 一一对应。
static func ranges() -> Dictionary:
	return {
		"attribute": [ATTRIBUTE_MIN, ATTRIBUTE_MAX],
		"personality": [PERSONALITY_MIN, PERSONALITY_MAX],
		"values_axis": [VALUES_AXIS_MIN, VALUES_AXIS_MAX],
		"skill": [SKILL_MIN, SKILL_MAX],
		"favor": [FAVOR_MIN, FAVOR_MAX],
		"grudge": [GRUDGE_MIN, GRUDGE_MAX],
		"trust": [TRUST_MIN, TRUST_MAX],
		"awe": [AWE_MIN, AWE_MAX],
		"intimacy": [INTIMACY_MIN, INTIMACY_MAX],
	}

static func clamp_attribute(value: int) -> int:
	var r := effective_range("attribute")
	return clampi(value, int(r[0]), int(r[1]))

static func clamp_skill(value: int) -> int:
	var r := effective_range("skill")
	return clampi(value, int(r[0]), int(r[1]))

static func clamp_favor(value: int) -> int:
	var r := effective_range("favor")
	return clampi(value, int(r[0]), int(r[1]))

static func clamp_grudge(value: int) -> int:
	var r := effective_range("grudge")
	return clampi(value, int(r[0]), int(r[1]))

static func clamp_intimacy(value: int) -> int:
	var r := effective_range("intimacy")
	return clampi(value, int(r[0]), int(r[1]))

## 关系强度按闲置年数指数衰减：dim *= exp(-k * idle_years)。
static func apply_relation_decay(value: float, idle_years: float) -> float:
	return value * exp(-effective_relation_decay_k() * idle_years)

## 取某交通方式的有效定义（远程配置可覆盖单个字段，如 transport.walk.speed_kmh）。
static func effective_transport_mode(mode_key: String) -> Dictionary:
	var base: Dictionary = (TRANSPORT_MODES.get(mode_key, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	var override: Variant = _overrides.get("transport." + mode_key, null)
	if override is Dictionary:
		for key in (override as Dictionary).keys():
			base[key] = (override as Dictionary)[key]
	return base

## 取某交通方式的有效标量字段（远程覆盖优先）。
static func effective_transport_field(mode_key: String, field: String, default_value: Variant) -> Variant:
	var mode := effective_transport_mode(mode_key)
	return mode.get(field, default_value)

static func effective_earth_radius_km() -> float:
	return float(_overrides.get("earth_radius_km", EARTH_RADIUS_KM))

## 取某气候带的有效定义（远程配置可覆盖单字段，如 climate_zone.mediterranean.base_temp）。
static func effective_zone(zone_key: String) -> Dictionary:
	var base: Dictionary = (CLIMATE_ZONES.get(zone_key, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	_merge_override(base, "climate_zone." + zone_key)
	return base

## 取某天气状态的有效定义（远程配置可覆盖单字段，如 weather_state.fog.precip_mm）。
static func effective_weather_state(state_key: String) -> Dictionary:
	var base: Dictionary = (WEATHER_STATES.get(state_key, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	_merge_override(base, "weather_state." + state_key)
	return base

## 取某灾害的有效定义（远程配置可覆盖单字段，如 disaster.flood.annual_rate）。
static func effective_disaster(disaster_key: String) -> Dictionary:
	var base: Dictionary = (WEATHER_DISASTERS.get(disaster_key, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	_merge_override(base, "disaster." + disaster_key)
	return base

## 取某时代阶段的有效定义（整体可覆盖 era_definitions，单条可覆盖 era.<key>）。
static func effective_era(index: int) -> Dictionary:
	var defs: Variant = _overrides.get("era_definitions", ERA_DEFINITIONS)
	var list: Array = defs if defs is Array else ERA_DEFINITIONS
	if list.is_empty():
		return {}
	var i: int = clampi(index, 0, list.size() - 1)
	var base: Dictionary = (list[i] as Dictionary).duplicate(true)
	_merge_override(base, "era." + str(base.get("key", "")))
	return base

## 取完整的时代阶段列表（含远程覆盖：整体 era_definitions 优先，否则逐条合并 era.<key>）。
static func effective_era_definitions() -> Array:
	var defs: Variant = _overrides.get("era_definitions", null)
	if defs is Array and not (defs as Array).is_empty():
		return (defs as Array).duplicate(true)
	var out: Array = []
	for i in ERA_DEFINITIONS.size():
		out.append(effective_era(i))
	return out

## 把远程覆盖合并进目标字典。支持两种写法（见 remote-config.schema.json 点分键约定）：
##   1) 嵌套对象：{"climate_zone.mediterranean": {"base_temp": 18.0}}
##   2) 点分标量：{"climate_zone.mediterranean.base_temp": 18.0}
static func _merge_override(base: Dictionary, override_key: String) -> void:
	var override: Variant = _overrides.get(override_key, null)
	if override is Dictionary:
		for key in (override as Dictionary).keys():
			base[key] = (override as Dictionary)[key]
	var prefix: String = override_key + "."
	for k in _overrides.keys():
		var sk := str(k)
		if sk.begins_with(prefix):
			var field := sk.substr(prefix.length())
			if not field.contains("."):
				base[field] = _overrides[k]

# --- 经济辅助（远程覆盖优先）---

## 取经济标量参数：先查 "economy.<key>"，再退回跨域键，最后用默认值。
static func effective_economy_param(key: String, default_value: Variant) -> Variant:
	if _overrides.has("economy." + key):
		return _overrides["economy." + key]
	if _overrides.has(key):
		return _overrides[key]
	return default_value

## 取某货币的有效定义（远程可覆盖 currency.<code> 整体或点分字段）。
static func effective_currency(code: String) -> Dictionary:
	var base: Dictionary = (CURRENCIES.get(code, {}) as Dictionary).duplicate(true)
	if base.is_empty():
		return {}
	_merge_override(base, "currency." + code)
	return base

## 取某品类的价格弹性（支持点分键与技术/嵌套覆盖）。
static func effective_elasticity(category: String) -> float:
	for key in ["economy.elasticity." + category, "elasticity." + category]:
		if _overrides.has(key):
			return float(_overrides[key])
	for dict_key in ["economy", ""]:
		var block: Variant = _overrides.get(dict_key, null)
		if block is Dictionary and (block as Dictionary).has("elasticity"):
			var table: Variant = (block as Dictionary)["elasticity"]
			if table is Dictionary and (table as Dictionary).has(category):
				return float((table as Dictionary)[category])
	var key2: String = category if PRICE_ELASTICITY.has(category) else "daily"
	return float(PRICE_ELASTICITY.get(key2, 0.35))

## 取累进税表（整体可覆盖，支持 economy.tax_*_brackets 与扁平键）。
static func _effective_brackets(key: String, nested_key: String, defaults: Array) -> Array:
	for k in ["economy." + key, key]:
		if _overrides.has(k):
			var v: Variant = _overrides[k]
			if v is Array and not (v as Array).is_empty():
				return (v as Array).duplicate(true)
	var block: Variant = _overrides.get("economy", null)
	if block is Dictionary and (block as Dictionary).has(nested_key):
		var nv: Variant = (block as Dictionary)[nested_key]
		if nv is Array and not (nv as Array).is_empty():
			return (nv as Array).duplicate(true)
	return defaults.duplicate(true)

## 取个人所得税累进税表。
static func effective_income_brackets() -> Array:
	return _effective_brackets("tax_income_brackets", "tax_income_brackets", TAX_INCOME_BRACKETS)

## 取遗产税累进税表。
static func effective_inheritance_brackets() -> Array:
	return _effective_brackets("tax_inheritance_brackets", "tax_inheritance_brackets", TAX_INHERITANCE_BRACKETS)

