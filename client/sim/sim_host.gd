class_name SimHost
extends RefCounted
## 玩法接线层：把 GameState 与各领域系统连接起来，供指令执行与时间推进使用。
## 纯逻辑、不依赖节点树或 Autoload，headless 测试可直接实例化。
##
## 职责边界：
## - 游戏内时钟（state.clock.absolute_minutes）随 advance() 推进，是存档里的时间字段；
##   UI 日历由 main 镜像到 WorldClock 展示，避免双份时间源。
## - 货币权威是 EconomySystem；player.finances 作为展示镜像，由 sync_finances() 回写。
## - 系统按需惰性实例化，起步目录（技能/职业/物品）在构造时注册，保证离线可玩。

const SurvivalScript = preload("res://sim/survival.gd")
const SkillsScript = preload("res://sim/skills.gd")
const JobsScript = preload("res://sim/jobs.gd")
const ItemsScript = preload("res://sim/items.gd")
const EconomyScript = preload("res://sim/economy.gd")
const RelationsScript = preload("res://sim/relations.gd")
const HappinessScript = preload("res://sim/happiness.gd")
const WeatherScript = preload("res://sim/weather.gd")
const BankScript = preload("res://sim/bank.gd")
const TaxScript = preload("res://sim/tax.gd")
const RngScript = preload("res://sim/rng.gd")
const BaselineScript = preload("res://sim/baseline.gd")
const GeoScript = preload("res://sim/geo.gd")
const RegionManagerScript = preload("res://sim/region_manager.gd")
const DomainWakeScript = preload("res://sim/domain_wake.gd")
const GregorianScript = preload("res://sim/gregorian.gd")
const NpcScript = preload("res://sim/npc.gd")
const FamilyScript = preload("res://sim/family.gd")
const PropertyScript = preload("res://sim/property.gd")
const InheritanceScript = preload("res://sim/inheritance.gd")
const PetScript = preload("res://sim/pet.gd")
const ParentingScript = preload("res://sim/parenting.gd")
const MentalHealthScript = preload("res://sim/mental_health.gd")
const PersonalityScript = preload("res://sim/personality.gd")
const SpiritualityScript = preload("res://sim/spirituality.gd")
const OrganizationScript = preload("res://sim/organizations.gd")
const LanguageScript = preload("res://sim/language.gd")
const DisabilityElderlyScript = preload("res://sim/disability_elderly.gd")
const AgricultureScript = preload("res://sim/agriculture.gd")
const DigitalScript = preload("res://sim/digital.gd")
const LateTechScript = preload("res://sim/late_tech.gd")
const IpMediaScript = preload("res://sim/ip_media.gd")
const ManufacturingScript = preload("res://sim/manufacturing.gd")
const TradeScript = preload("res://sim/trade.gd")
const MiningScript = preload("res://sim/mining_energy.gd")
const PrimaryScript = preload("res://sim/primary_industry.gd")
const DiningScript = preload("res://sim/dining.gd")
const FashionScript = preload("res://sim/fashion.gd")
const SportsIndustryScript = preload("res://sim/sports_industry.gd")
const EventsExpoScript = preload("res://sim/events_expo.gd")
const HonorsScript = preload("res://sim/honors.gd")
const PoliceScript = preload("res://sim/police.gd")
const CrimeScript = preload("res://sim/crime.gd")
const PrisonScript = preload("res://sim/prison.gd")
## 犯罪罪名 → 判定技能（犯罪技能树）。
const CRIME_SKILLS: Dictionary = {
	"theft": "theft", "robbery": "robbery", "fraud": "fraud", "assault": "crime_disguise",
	"injury": "crime_disguise", "smuggling": "smuggling", "tax_evasion": "forgery",
	"corruption": "bribery", "bribery": "bribery", "framing": "forgery",
	"deceive": "fraud", "disturbance": "crime_disguise",
}
const EmergencyScript = preload("res://sim/emergency.gd")
const EnvironmentScript = preload("res://sim/environment.gd")
const MunicipalScript = preload("res://sim/municipal.gd")
const DebtServiceScript = preload("res://sim/debt_service.gd")
const ConsumerProtectionScript = preload("res://sim/consumer_protection.gd")
const SocialWelfareScript = preload("res://sim/social_welfare.gd")
const FuneralScript = preload("res://sim/funeral.gd")
const MetaphysicsScript = preload("res://sim/metaphysics.gd")
const AnomalyScript = preload("res://sim/anomaly.gd")
const MedicalScript = preload("res://sim/medical.gd")
const MedTechScript = preload("res://sim/medtech.gd")
const ContentIndustryScript = preload("res://sim/content_industry.gd")
const EngineeringScript = preload("res://sim/engineering.gd")
const ProfessionalServicesScript = preload("res://sim/professional_services.gd")
const LifeServicesScript = preload("res://sim/life_services.gd")
const TransportInfraScript = preload("res://sim/transport_infra.gd")
const ResearchScript = preload("res://sim/research.gd")
const CivilScript = preload("res://sim/civil.gd")
const AppearanceScript = preload("res://sim/appearance.gd")
const AestheticScript = preload("res://sim/aesthetics.gd")
const MilitaryScript = preload("res://sim/military.gd")
const WorkplaceScript = preload("res://sim/workplace.gd")
const CompanyScript = preload("res://sim/company.gd")
const FinancingScript = preload("res://sim/financing.gd")

const MINUTES_PER_DAY: int = 1440
## 所在城市熟人名册容量（首发单城社交/婚恋链接）。
const ACQUAINTANCE_COUNT: int = 8
## 所在城市在售房源数量（确定性生成，供看房/买房）。
const PROPERTY_LISTING_COUNT: int = 5
## 所在城市可加入组织类型（确定性生成，供加入组织）。
const ORG_TYPES_SEED: Array = ["union", "club", "ngo", "trade_association", "religious"]
## 妊娠天数（自受孕至分娩）。
const GESTATION_DAYS: int = 280
## 持有房产按月结算的间隔（天）。
const SETTLE_INTERVAL_DAYS: int = 30

## 每游戏年分钟数（用于子女成长/早夭按年结算）。
const MINUTES_PER_YEAR: float = 365.25 * 1440.0

## 子女成年年龄（R51.4）。
const ADULT_AGE: int = 18

## 收养子女 NPC 的独立序号段基址，避免与熟人（1..N）及亲生子女（100000 段）id 冲突。
const ADOPT_SEQ_BASE: int = 200000
## 首发默认国家（无有效 nation 时降级，见 design「首发单城」）。
const DEFAULT_COUNTRY: String = "CN"
## 地理气候带（GeoData）→ 天气气候带（baseline CLIMATE_ZONES）的确定性映射。
const CLIMATE_TO_ZONE: Dictionary = {
	"tropical": "tropical_monsoon",
	"subtropical": "subtropical_monsoon",
	"temperate": "temperate_continental",
	"cold": "subarctic_conifer",
	"polar": "polar_highland",
}

var state                       ## 需暴露 player / clock / world_delta / legacy / meta
var rng                         ## 确定性随机源（供面试、暴击等消费）
var survival
var skills
var jobs
var items
var economy
var relations
var happiness
var weather
var bank
var tax
var _last_finance_day: int = -1
var geo                         ## 六级地理（种子确定性生成，不入档）
var regions                     ## 分区休眠/唤醒与全人口（RegionManager）
var domain_wake                 ## 领域状态休眠补算（DomainWake）
var npcs                        ## NPC 个体生成（NpcSystem）
var family                      ## 恋爱/婚姻/繁衍（FamilySystem）
var property                    ## 房产（PropertySystem）
var inheritance                ## 继承（InheritanceSystem）
var pet                         ## 宠物（PetSystem）
var parenting                   ## 育儿与成长（ParentingSystem）
var mental                      ## 精神疾病与情绪（MentalHealthSystem）
var personality                 ## 大五人格与标签（PersonalitySystem）
var spirituality                ## 价值观三轴/精神追求/信仰（SpiritualitySystem）
var _spirit: Dictionary = {}    ## 精神追求运行时（深度/信仰/危机），入档 sim_runtime.spirituality
var organizations               ## 组织与社团（OrganizationSystem）
var _orgs: Array = []           ## 所在城市可加入组织（确定性生成，运行时叠加存档增量）
var language                    ## 语言与文化（LanguageSystem）
var _lang_profile: Dictionary = {}   ## 语言档案（分项/证书/适应），入档 sim_runtime.language
var _culture: Dictionary = {}        ## 文化适应状态（适应度/冲击），入档 sim_runtime.culture
var disability                  ## 残障与养老（DisabilityElderlySystem）
var _disability: Dictionary = {}     ## 残障/养老运行时（残障/辅具/养老/监护），入档 sim_runtime.disability
var _care_incident: Dictionary = {}  ## 最近一次护工事件（供追责）
var agriculture                 ## 农业与乡土（AgricultureSystem）
var _farm: Dictionary = {}           ## 农场运行时（土地/地块/牲畜/仓储/订单），入档 sim_runtime.farm
var digital                     ## 数字生活与黑客（DigitalSystem）
var _identity: Dictionary = {}       ## 数字身份运行时（账号/隐私/数据/数字资产），入档 sim_runtime.digital
var _creator: Dictionary = {}        ## 内容创作者运行时（粉丝/打赏/带货），入档 sim_runtime.digital
var _esports: Dictionary = {}        ## 电竞生涯运行时（战队/技能/伤病），入档 sim_runtime.digital
var late_tech                   ## 后期科技（LateTechSystem）
var _late_tech: Dictionary = {}      ## 后期科技运行时（阶段/解锁/失业/延寿），入档 sim_runtime.late_tech
var ip_media                    ## 知识产权与媒体（IpMediaSystem）
var _ips: Array = []                 ## 已登记知识产权，入档 sim_runtime.ip_media.ips
var _outlets: Array = []             ## 媒体机构，入档 sim_runtime.ip_media.outlets
var manufacturing                ## 制造业与供应链（ManufacturingSystem）
var _factory: Dictionary = {}        ## 玩家工厂运行时（工厂为纯数据字典），入档 sim_runtime.manufacturing
var trade                        ## 国际贸易、海关与物流（TradeSystem）
var _shipments: Array = []           ## 外贸单据列表，入档 sim_runtime.trade.shipments
var mining_energy                ## 矿业、能源与资源（MiningEnergySystem）
var _mine: Dictionary = {}           ## 玩家矿场运行时，入档 sim_runtime.mining.mine
var _energy: Dictionary = {}         ## 能源市场运行时（价格/期货/项目），入档 sim_runtime.mining.energy
var primary_industry             ## 农林牧渔深化（PrimaryIndustrySystem）
var _fishery: Dictionary = {}        ## 渔场运行时，入档 sim_runtime.primary.fishery
var _forest: Dictionary = {}         ## 林场运行时，入档 sim_runtime.primary.forest
var _hunter: Dictionary = {}         ## 狩猎运行时，入档 sim_runtime.primary.hunter
var _ecology: Dictionary = {}        ## 生态可持续运行时，入档 sim_runtime.primary.ecology
var dining                      ## 餐饮与食品工业（DiningSystem）
var _restaurant: Dictionary = {}     ## 玩家餐厅运行时（门店为纯数据字典），入档 sim_runtime.dining
var fashion                     ## 时尚、设计与奢侈品（FashionSystem）
var _brand: Dictionary = {}          ## 时尚品牌运行时，入档 sim_runtime.fashion.brand
var _trend: Dictionary = {}          ## 时尚潮流周期，入档 sim_runtime.fashion.trend
var sports_industry             ## 体育产业与赛事（SportsIndustrySystem）
var _pro_player: Dictionary = {}     ## 玩家职业运动员生涯，入档 sim_runtime.sports.player
var _sports_club: Dictionary = {}    ## 玩家所属球会，入档 sim_runtime.sports.club
var _sports_rival: Dictionary = {}   ## 联赛对手球会，入档 sim_runtime.sports.rival
var _sports_league: Dictionary = {}  ## 地区联赛，入档 sim_runtime.sports.league
var events_expo                 ## 会展、演出与大型活动（EventsExpoSystem）
var _event: Dictionary = {}          ## 当前筹办中的活动，入档 sim_runtime.events.event
var _planner: Dictionary = {}        ## 活动策划职业，入档 sim_runtime.events.planner
var honors                      ## 荣誉、奖项与名人堂（HonorsSystem）
var _honor_candidate: Dictionary = {} ## 玩家荣誉候选人档案，入档 sim_runtime.honors.candidate
var _hall: Dictionary = {}           ## 名人堂，入档 sim_runtime.honors.hall
var police                      ## 安保、警务与刑侦（PoliceSystem）
var _police_case: Dictionary = {}     ## 当前经办案件，入档 sim_runtime.police.case
var _security_firm: Dictionary = {}   ## 民营安保公司，入档 sim_runtime.police.firm
var crime_sys                    ## 玩家犯罪、案底与通缉（CrimeSystem）
var prison_sys                   ## 监狱生活与社会融入（PrisonSystem）
var _crime_state: Dictionary = {}  ## 玩家犯罪运行态（records/wanted/aliases），入档 sim_runtime.crime
var _prison: Dictionary = {}       ## 在押/出狱运行态，入档 sim_runtime.prison
var _prison_last_day: int = -1     ## 上次监狱刑期结算日
var emergency                    ## 应急、消防与灾害救援（EmergencySystem）
var _incident: Dictionary = {}        ## 当前处置中的应急事件，入档 sim_runtime.emergency.incident
var _volunteer_org: Dictionary = {}   ## 志愿救援组织，入档 sim_runtime.emergency.org
var environment_sys              ## 环保、碳排与可持续发展（EnvironmentSystem）
var _city_env: Dictionary = {}        ## 城市环保状态，入档 sim_runtime.environment.city
var _env_enterprise: Dictionary = {}  ## 玩家企业碳排账户，入档 sim_runtime.environment.enterprise
var _env_org: Dictionary = {}         ## 环保从业组织，入档 sim_runtime.environment.org
var municipal                    ## 市政公用与邮政（MunicipalSystem）
var _city_municipal: Dictionary = {}  ## 城市市政状态，入档 sim_runtime.municipal.city
var _postal_hub: Dictionary = {}      ## 邮政枢纽，入档 sim_runtime.municipal.hub
var _courier: Dictionary = {}         ## 快递员职业，入档 sim_runtime.municipal.courier
var _municipal_license: bool = false  ## 公用事业特许资质，入档 sim_runtime.municipal.license
var debt                         ## 债务服务、当铺与小贷（DebtServiceSystem）
var _debt_lender: Dictionary = {}    ## 玩家作为放贷人，入档 sim_runtime.debt.lender
var _debt_loan: Dictionary = {}      ## 玩家当前借款（兼容单笔视图），入档 sim_runtime.debt.loan
var _debt_lend: Dictionary = {}      ## 玩家当前放贷（兼容单笔视图），入档 sim_runtime.debt.lend
var _debt_loans: Array = []          ## 借款人贷款台账，入档 sim_runtime.debt.loans
var _debt_lends: Array = []          ## 放贷人贷款台账，入档 sim_runtime.debt.lends
var _debt_pawns: Array = []          ## 典当物，入档 sim_runtime.debt.pawns
var consumer                     ## 消费者保护与产品质量（ConsumerProtectionSystem）
var _consumer_order: Dictionary = {}    ## 当前消费订单，入档 sim_runtime.consumer.order
var _consumer_product: Dictionary = {}  ## 当前商品，入档 sim_runtime.consumer.product
var _consumer_merchant: Dictionary = {} ## 涉事商家，入档 sim_runtime.consumer.merchant
var social_welfare                ## 社会救助、收养寄养与慈善（SocialWelfareSystem）
var _welfare_application: Dictionary = {}  ## 当前救助/收养申请，入档 sim_runtime.welfare.application
var _welfare_fund: Dictionary = {}         ## 慈善基金，入档 sim_runtime.welfare.fund
var _welfare_worker: Dictionary = {}       ## 社工，入档 sim_runtime.welfare.worker
var _welfare_case: Dictionary = {}         ## 当前个案，入档 sim_runtime.welfare.case
var _welfare_child: Dictionary = {}        ## 变故儿童，入档 sim_runtime.welfare.child
var _welfare_recognition: Dictionary = {}  ## 跨区资格互认凭证，入档 sim_runtime.welfare.recognition
var funeral                       ## 殡葬、器官捐献与纪念（FuneralSystem）
var _funeral_state: Dictionary = {}        ## 殡葬运行态，入档 sim_runtime.funeral.state
var _funeral_home: Dictionary = {}         ## 殡葬行业经营体，入档 sim_runtime.funeral.home
var metaphysics                    ## 玄学、命理与民俗信仰（MetaphysicsSystem）
var _meta_client: Dictionary = {}          ## 求测者心理状态，入档 sim_runtime.metaphysics.client
var _meta_practitioner: Dictionary = {}    ## 从业者（大师）人设，入档 sim_runtime.metaphysics.practitioner
var _meta_business: Dictionary = {}        ## 玄学经营体，入档 sim_runtime.metaphysics.business
var anomaly                       ## 隐秘异常收容体系（AnomalySystem）
var _anomaly_state: Dictionary = {}        ## 异常隔离状态树（默认 hidden），入档 sim_runtime.anomaly
var medical                       ## 疾病库与就医流程（MedicalSystem）
var medtech                       ## 医疗、生命科技与医药产业（MedTechSystem）
var _medical_region: Dictionary = {}       ## 区域医疗资源，入档 sim_runtime.medical.region
var _pharma_company: Dictionary = {}       ## 医药公司管线，入档 sim_runtime.medical.pharma
var content_industry                ## 文娱内容产业（ContentIndustrySystem）
var _content_studio: Dictionary = {}       ## 玩家文娱工作室，入档 sim_runtime.content.studio
var _content_work: Dictionary = {}         ## 当前在研作品，入档 sim_runtime.content.work
var _content_rival: Dictionary = {}        ## 对手工作室（挖角目标），入档 sim_runtime.content.rival
var _content_ip_id: String = ""            ## 当前 IP 标识，入档 sim_runtime.content.ip_id
var _content_seq: int = 0                  ## 作品序号，入档 sim_runtime.content.seq
var engineering                     ## 建筑、工程与城市规划（EngineeringSystem）
var _eng_contractor: Dictionary = {}       ## 玩家施工/工程公司，入档 sim_runtime.engineering.contractor
var _eng_project: Dictionary = {}          ## 当前在建工程，入档 sim_runtime.engineering.project
var _eng_city: Dictionary = {}             ## 当前城市（规划载体），入档 sim_runtime.engineering.city
var _eng_developer: Dictionary = {}        ## 玩家地产开发商，入档 sim_runtime.engineering.developer
var _eng_rivals: Array = []                ## 招标对手承包商（确定性生成，不入档）
var professional                    ## 专业服务业（ProfessionalServicesSystem）
var _prof_firm: Dictionary = {}            ## 玩家专业事务所，入档 sim_runtime.professional.firm
var _prof_project: Dictionary = {}         ## 当前项目，入档 sim_runtime.professional.project
var life_services                 ## 家庭与生活服务业（LifeServicesSystem）
var _life_provider: Dictionary = {}        ## 玩家服务者，入档 sim_runtime.life_services.provider
var _life_order: Dictionary = {}           ## 当前服务单，入档 sim_runtime.life_services.order
var transport_infra                ## 交通基建与航运（TransportInfraSystem）
var _tin_project: Dictionary = {}          ## 当前基建项目，入档 sim_runtime.transport_infra.project
var _tin_route: Dictionary = {}            ## 当前运营线路，入档 sim_runtime.transport_infra.route
var _tin_region: Dictionary = {}           ## 受影响区域（最小实现），入档 sim_runtime.transport_infra.region
var research_sys                 ## 科研流程与成果转化（ResearchSystem）
var _research: Dictionary = {}       ## 科研运行时（项目/实验室资源/累计成果），入档 sim_runtime.research
var civil_sys                    ## 民事纠纷与诉讼（CivilSystem）
var _civil: Dictionary = {}          ## 民事案件运行时（纠纷/判决/执行），入档 sim_runtime.civil
var appearance_sys               ## 形象属性与魅力（AppearanceSystem）
var aesthetic_sys                ## 医美项目与风险（AestheticSystem）
var _appearance: Dictionary = {}     ## 形象档案（外貌/气质/体型等），入档 sim_runtime.appearance.profile
var _aesthetic: Dictionary = {}      ## 医美运行态（项目记录/僵硬/证件照），入档 sim_runtime.appearance.aesthetics
var military_sys                 ## 军旅生涯（MilitarySystem）
var workplace_sys                ## 职场关系与派系（WorkplaceSystem）
var company_sys                  ## 创业经营（CompanySystem）
var financing_sys                ## 创业融资（FinancingSystem）
var _workplace: Dictionary = {}      ## 职场状态（关系/派系/事件），入档 sim_runtime.workplace
var _company: Dictionary = {}        ## 玩家公司，入档 sim_runtime.company.company
var _cap_table: Dictionary = {}      ## 股权结构，入档 sim_runtime.company.cap_table

var _seeded: bool = false
var _seed: int = 0
var _home_region_id: String = ""
var _acquaintances: Array = []  ## 所在城市熟人（确定性生成，供社交/婚恋链接）
var _listings: Array = []       ## 所在城市在售房源（确定性生成，不入档）
var _inheritance_settled: bool = false
var _child_seq: int = 0
var _adopt_seq: int = 0

func _init(state_obj = null, seed: int = 0) -> void:
	_seed = seed
	rng = RngScript.new(seed)
	survival = SurvivalScript.new(seed)
	skills = SkillsScript.new()
	jobs = JobsScript.new()
	items = ItemsScript.new()
	economy = EconomyScript.new()
	relations = RelationsScript.new()
	happiness = HappinessScript.new()
	weather = WeatherScript.new(seed)
	bank = BankScript.new(seed)
	tax = TaxScript.new()
	geo = GeoScript.new()
	regions = RegionManagerScript.new(null, seed)
	domain_wake = DomainWakeScript.new()
	regions.domain_wake = domain_wake
	npcs = NpcScript.new()
	family = FamilyScript.new(seed)
	property = PropertyScript.new()
	inheritance = InheritanceScript.new()
	pet = PetScript.new()
	parenting = ParentingScript.new()
	mental = MentalHealthScript.new()
	personality = PersonalityScript.new()
	spirituality = SpiritualityScript.new()
	_spirit = spirituality.new_state()
	organizations = OrganizationScript.new()
	language = LanguageScript.new()
	_lang_profile = language.new_profile()
	_culture = language.new_cultural_state()
	disability = DisabilityElderlyScript.new()
	_disability = disability.new_state()
	agriculture = AgricultureScript.new()
	_farm = agriculture.new_farm()
	digital = DigitalScript.new()
	_identity = digital.new_identity("player")
	late_tech = LateTechScript.new()
	_late_tech = late_tech.new_state()
	ip_media = IpMediaScript.new()
	manufacturing = ManufacturingScript.new()
	trade = TradeScript.new()
	mining_energy = MiningScript.new()
	_energy = mining_energy.new_energy_state()
	primary_industry = PrimaryScript.new()
	_ecology = primary_industry.new_ecology()
	dining = DiningScript.new()
	fashion = FashionScript.new()
	_trend = fashion.new_trend()
	sports_industry = SportsIndustryScript.new()
	events_expo = EventsExpoScript.new()
	honors = HonorsScript.new()
	_hall = honors.new_hall()
	police = PoliceScript.new()
	crime_sys = CrimeScript.new()
	prison_sys = PrisonScript.new()
	emergency = EmergencyScript.new()
	environment_sys = EnvironmentScript.new()
	_city_env = environment_sys.new_city_env(1000000)
	_env_enterprise = environment_sys.new_enterprise("我的企业")
	municipal = MunicipalScript.new()
	_city_municipal = municipal.new_city(1000000)
	_postal_hub = municipal.new_postal_hub()
	debt = DebtServiceScript.new()
	_debt_lender = debt.new_lender("player", {"name": "本人", "license": true})
	consumer = ConsumerProtectionScript.new()
	_consumer_merchant = {"id": "merchant", "name": "商家", "reputation": 0.5, "sales": 1.0, "fines": 0, "compensation_paid": 0}
	social_welfare = SocialWelfareScript.new()
	_welfare_fund = social_welfare.new_charity_fund("公益基金", {"balance": 0, "transparency": 1.0, "reputation": 0.5})
	funeral = FuneralScript.new()
	_funeral_state = funeral.new_state()
	metaphysics = MetaphysicsScript.new()
	_meta_client = metaphysics.new_client()
	_meta_practitioner = metaphysics.new_practitioner("player", {"name": "本人"})
	anomaly = AnomalyScript.new()
	_anomaly_state = anomaly.new_state()["anomaly"]
	medical = MedicalScript.new(seed)
	medtech = MedTechScript.new()
	_medical_region = medtech.new_region(1000000, {"medical_level": 1.5})
	medtech.region_metrics(_medical_region)
	content_industry = ContentIndustryScript.new()
	_content_rival = content_industry.new_studio({"id": "studio.rival", "name": "竞品工作室", "money": 8000000})
	content_industry.hire(_content_rival, "design", 2, {"skill": 0.8})
	content_industry.hire(_content_rival, "engineering", 2, {"skill": 0.8})
	engineering = EngineeringScript.new()
	_eng_rivals = [
		engineering.new_contractor({"id": "rival.a", "name": "宏图建设", "qualification": "first", "capital": 60000000, "workmanship": 0.7, "relationship": 0.6, "reputation": 0.7}),
		engineering.new_contractor({"id": "rival.b", "name": "恒基工程", "qualification": "second", "capital": 20000000, "workmanship": 0.5, "relationship": 0.4, "reputation": 0.5}),
		engineering.new_contractor({"id": "rival.c", "name": "远洋建工", "qualification": "special", "capital": 90000000, "workmanship": 0.8, "relationship": 0.3, "reputation": 0.8}),
	]
	professional = ProfessionalServicesScript.new()
	life_services = LifeServicesScript.new()
	transport_infra = TransportInfraScript.new()
	research_sys = ResearchScript.new()
	civil_sys = CivilScript.new()
	appearance_sys = AppearanceScript.new()
	aesthetic_sys = AestheticScript.new()
	military_sys = MilitaryScript.new()
	workplace_sys = WorkplaceScript.new()
	company_sys = CompanyScript.new()
	financing_sys = FinancingScript.new()
	skills.register_starter_catalog()
	jobs.register_starter_catalog()
	items.register_starter_catalog()
	if state_obj != null:
		bind(state_obj)

func bind(state_obj) -> void:
	state = state_obj
	_seeded = false
	_ensure_world()

func player() -> Dictionary:
	return state.player

func account_id() -> String:
	return String(player().get("id", "player"))

func now_minutes() -> int:
	return int(state.clock.get("absolute_minutes", 0))

func day_index() -> int:
	return now_minutes() / MINUTES_PER_DAY

## 惰性建立经济运行所需的账户，并用存档现金为玩家账户初始注资。
func _ensure_world() -> void:
	if _seeded or state == null:
		return
	var id := account_id()
	if not economy.has_account(id):
		var cash := float(player().get("finances", {}).get("cash", 0.0))
		economy.open_account(id, int(round(cash * float(BaselineScript.MONEY_MINOR_SCALE))))
	for external_id in ["employer", "bank", "market", "government"]:
		if not economy.has_account(external_id):
			economy.open_account(external_id, 100000000)
	_seeded = true
	_ensure_world_geo()
	if _last_finance_day < 0:
		_last_finance_day = now_minutes() / MINUTES_PER_DAY

## 建立世界运行时：种子确定性生成六级地理，载入存档中的区域增量，登记玩家所在城市为
## 活动区域并绑定气候带，使区域人口/经济与天气随游戏内时钟演化（R5/R50、D1/D2）。
## 地理不入档（同种子可复现）；区域增量写入 world_delta.regions（design：存档只记变化量）。
func _ensure_world_geo() -> void:
	if state == null:
		return
	# 恢复生存运行时（成瘾复发/营养过量天数/死亡标志/遗嘱）。
	if state.sim_runtime is Dictionary:
		var sr: Variant = (state.sim_runtime as Dictionary).get("survival", {})
		if sr is Dictionary and not (sr as Dictionary).is_empty():
			survival.from_dict(sr)
		# 恢复领域实体休眠补算运行时（案件/工程/贷款/灾害）。
		var dwr: Variant = (state.sim_runtime as Dictionary).get("domain_wake", {})
		if dwr is Dictionary and not (dwr as Dictionary).is_empty():
			domain_wake.from_dict(dwr)
		# 恢复精神疾病病程运行时（三维病程/复发/治疗标志）。
		var mr: Variant = (state.sim_runtime as Dictionary).get("mental", {})
		if mr is Dictionary and not (mr as Dictionary).is_empty():
			mental.from_dict(mr)
		# 恢复精神追求运行时（追求深度/信仰/危机）。
		var spr: Variant = (state.sim_runtime as Dictionary).get("spirituality", {})
		if spr is Dictionary and not (spr as Dictionary).is_empty():
			_spirit = spirituality.from_dict(spr)
		# 恢复语言档案（分项/证书）与文化适应状态。
		var lr: Variant = (state.sim_runtime as Dictionary).get("language", {})
		if lr is Dictionary and not (lr as Dictionary).is_empty():
			_lang_profile = language.from_dict(lr)
		var cr: Variant = (state.sim_runtime as Dictionary).get("culture", {})
		if cr is Dictionary and not (cr as Dictionary).is_empty():
			_culture = language.from_dict(cr)
		# 恢复残障/养老运行时（残障/辅具/养老模式/监护）。
		var dr: Variant = (state.sim_runtime as Dictionary).get("disability", {})
		if dr is Dictionary and not (dr as Dictionary).is_empty():
			_disability = disability.from_dict(dr)
		# 恢复农场运行时（土地/地块/牲畜/仓储/订单）。
		var fr: Variant = (state.sim_runtime as Dictionary).get("farm", {})
		if fr is Dictionary and not (fr as Dictionary).is_empty():
			_farm = agriculture.from_dict(fr)
		# 恢复数字身份/创作者/电竞运行时。
		var dig: Variant = (state.sim_runtime as Dictionary).get("digital", {})
		if dig is Dictionary and not (dig as Dictionary).is_empty():
			var dd: Dictionary = dig
			if dd.get("identity", null) is Dictionary:
				_identity = digital.from_dict(dd["identity"])
			if dd.get("creator", null) is Dictionary:
				_creator = (dd["creator"] as Dictionary).duplicate(true)
			if dd.get("esports", null) is Dictionary:
				_esports = (dd["esports"] as Dictionary).duplicate(true)
		# 恢复后期科技运行时（阶段/解锁/延寿）。
		var lt: Variant = (state.sim_runtime as Dictionary).get("late_tech", {})
		if lt is Dictionary and not (lt as Dictionary).is_empty():
			_late_tech = late_tech.from_dict(lt)
		# 恢复知识产权与媒体运行时（IP/媒体机构）。
		var im: Variant = (state.sim_runtime as Dictionary).get("ip_media", {})
		if im is Dictionary and not (im as Dictionary).is_empty():
			_ips = (im.get("ips", []) as Array).duplicate(true)
			_outlets = (im.get("outlets", []) as Array).duplicate(true)
		# 恢复制造业运行时（玩家工厂）。
		var mf: Variant = (state.sim_runtime as Dictionary).get("manufacturing", {})
		if mf is Dictionary and not (mf as Dictionary).is_empty():
			_factory = manufacturing.from_dict(mf)
		# 恢复国际贸易运行时（外贸单据）。
		var tr: Variant = (state.sim_runtime as Dictionary).get("trade", {})
		if tr is Dictionary and not (tr as Dictionary).is_empty():
			_shipments = ((tr as Dictionary).get("shipments", []) as Array).duplicate(true)
		# 恢复科研运行时（项目/实验室资源/累计成果）。
		var rs: Variant = (state.sim_runtime as Dictionary).get("research", {})
		if rs is Dictionary and not (rs as Dictionary).is_empty():
			_research = (rs as Dictionary).duplicate(true)
		# 恢复民事案件运行时（纠纷/判决/执行）。
		var cv: Variant = (state.sim_runtime as Dictionary).get("civil", {})
		if cv is Dictionary and not (cv as Dictionary).is_empty():
			_civil = (cv as Dictionary).duplicate(true)
		# 恢复玩家犯罪与监狱运行时。
		var crm: Variant = (state.sim_runtime as Dictionary).get("crime", {})
		if crm is Dictionary and not (crm as Dictionary).is_empty():
			_crime_state = (crm as Dictionary).duplicate(true)
		var prs: Variant = (state.sim_runtime as Dictionary).get("prison", {})
		if prs is Dictionary and not (prs as Dictionary).is_empty():
			_prison = (prs as Dictionary).duplicate(true)
		_prison_last_day = now_minutes() / MINUTES_PER_DAY
		# 恢复职场状态与公司/股权。
		var wp: Variant = (state.sim_runtime as Dictionary).get("workplace", {})
		if wp is Dictionary and not (wp as Dictionary).is_empty():
			_workplace = (wp as Dictionary).duplicate(true)
		var co: Variant = (state.sim_runtime as Dictionary).get("company", {})
		if co is Dictionary and not (co as Dictionary).is_empty():
			var cod: Dictionary = co
			if cod.get("company", null) is Dictionary:
				_company = (cod["company"] as Dictionary).duplicate(true)
			if cod.get("cap_table", null) is Dictionary:
				_cap_table = (cod["cap_table"] as Dictionary).duplicate(true)
		# 恢复银行信用、定期存款、证券持仓与报价。
		var fin_state: Variant = (state.sim_runtime as Dictionary).get("finance", {})
		if fin_state is Dictionary and not (fin_state as Dictionary).is_empty():
			bank.from_dict(fin_state)
			_last_finance_day = int((fin_state as Dictionary).get("last_settle_day", -1))
		# 恢复形象档案与医美运行态。
		var ap: Variant = (state.sim_runtime as Dictionary).get("appearance", {})
		if ap is Dictionary and not (ap as Dictionary).is_empty():
			var apd: Dictionary = ap
			if apd.get("profile", null) is Dictionary and not (apd["profile"] as Dictionary).is_empty():
				_appearance = (apd["profile"] as Dictionary).duplicate(true)
			if apd.get("aesthetics", null) is Dictionary:
				_aesthetic = (apd["aesthetics"] as Dictionary).duplicate(true)
		# 恢复矿业/能源运行时（矿场/能源市场）。
		var mn: Variant = (state.sim_runtime as Dictionary).get("mining", {})
		if mn is Dictionary and not (mn as Dictionary).is_empty():
			var mnd: Dictionary = mn
			if mnd.get("mine", null) is Dictionary and not (mnd["mine"] as Dictionary).is_empty():
				_mine = (mnd["mine"] as Dictionary).duplicate(true)
			if mnd.get("energy", null) is Dictionary and not (mnd["energy"] as Dictionary).is_empty():
				_energy = (mnd["energy"] as Dictionary).duplicate(true)
		# 恢复农林牧渔深化运行时（渔场/林场/狩猎/生态）。
		var pr: Variant = (state.sim_runtime as Dictionary).get("primary", {})
		if pr is Dictionary and not (pr as Dictionary).is_empty():
			var prd: Dictionary = pr
			if prd.get("fishery", null) is Dictionary and not (prd["fishery"] as Dictionary).is_empty():
				_fishery = (prd["fishery"] as Dictionary).duplicate(true)
			if prd.get("forest", null) is Dictionary and not (prd["forest"] as Dictionary).is_empty():
				_forest = (prd["forest"] as Dictionary).duplicate(true)
			if prd.get("hunter", null) is Dictionary and not (prd["hunter"] as Dictionary).is_empty():
				_hunter = (prd["hunter"] as Dictionary).duplicate(true)
			if prd.get("ecology", null) is Dictionary and not (prd["ecology"] as Dictionary).is_empty():
				_ecology = (prd["ecology"] as Dictionary).duplicate(true)
		# 恢复餐饮运行时（玩家餐厅）。
		var dn: Variant = (state.sim_runtime as Dictionary).get("dining", {})
		if dn is Dictionary and not (dn as Dictionary).is_empty():
			var dnd: Dictionary = dn
			if dnd.get("restaurant", null) is Dictionary and not (dnd["restaurant"] as Dictionary).is_empty():
				_restaurant = dining.from_dict(dnd["restaurant"])
		# 恢复时尚运行时（品牌/潮流）。
		var fa: Variant = (state.sim_runtime as Dictionary).get("fashion", {})
		if fa is Dictionary and not (fa as Dictionary).is_empty():
			var fad: Dictionary = fa
			if fad.get("brand", null) is Dictionary and not (fad["brand"] as Dictionary).is_empty():
				_brand = fashion.from_dict(fad["brand"])
			if fad.get("trend", null) is Dictionary and not (fad["trend"] as Dictionary).is_empty():
				_trend = (fad["trend"] as Dictionary).duplicate(true)
		# 恢复体育运行时（生涯/球会/联赛）。
		var sp: Variant = (state.sim_runtime as Dictionary).get("sports", {})
		if sp is Dictionary and not (sp as Dictionary).is_empty():
			var spd: Dictionary = sp
			if spd.get("player", null) is Dictionary and not (spd["player"] as Dictionary).is_empty():
				_pro_player = (spd["player"] as Dictionary).duplicate(true)
			if spd.get("club", null) is Dictionary and not (spd["club"] as Dictionary).is_empty():
				_sports_club = (spd["club"] as Dictionary).duplicate(true)
			if spd.get("rival", null) is Dictionary and not (spd["rival"] as Dictionary).is_empty():
				_sports_rival = (spd["rival"] as Dictionary).duplicate(true)
			if spd.get("league", null) is Dictionary and not (spd["league"] as Dictionary).is_empty():
				_sports_league = (spd["league"] as Dictionary).duplicate(true)
		# 恢复会展运行时（活动/策划）。
		var ev: Variant = (state.sim_runtime as Dictionary).get("events", {})
		if ev is Dictionary and not (ev as Dictionary).is_empty():
			var evd: Dictionary = ev
			if evd.get("event", null) is Dictionary and not (evd["event"] as Dictionary).is_empty():
				_event = events_expo.from_dict(evd["event"])
			if evd.get("planner", null) is Dictionary and not (evd["planner"] as Dictionary).is_empty():
				_planner = (evd["planner"] as Dictionary).duplicate(true)
		# 恢复荣誉运行时（候选人/名人堂）。
		var ho: Variant = (state.sim_runtime as Dictionary).get("honors", {})
		if ho is Dictionary and not (ho as Dictionary).is_empty():
			var hod: Dictionary = ho
			if hod.get("candidate", null) is Dictionary and not (hod["candidate"] as Dictionary).is_empty():
				_honor_candidate = honors.from_dict(hod["candidate"])
			if hod.get("hall", null) is Dictionary and not (hod["hall"] as Dictionary).is_empty():
				_hall = (hod["hall"] as Dictionary).duplicate(true)
		# 恢复警务运行时（经办案件/安保公司）。
		var po: Variant = (state.sim_runtime as Dictionary).get("police", {})
		if po is Dictionary and not (po as Dictionary).is_empty():
			var pod: Dictionary = po
			if pod.get("case", null) is Dictionary and not (pod["case"] as Dictionary).is_empty():
				_police_case = police.from_dict(pod["case"])
			if pod.get("firm", null) is Dictionary and not (pod["firm"] as Dictionary).is_empty():
				_security_firm = (pod["firm"] as Dictionary).duplicate(true)
		# 恢复应急运行时（处置事件/志愿组织）。
		var em: Variant = (state.sim_runtime as Dictionary).get("emergency", {})
		if em is Dictionary and not (em as Dictionary).is_empty():
			var emd: Dictionary = em
			if emd.get("incident", null) is Dictionary and not (emd["incident"] as Dictionary).is_empty():
				_incident = emergency.from_dict(emd["incident"])
			if emd.get("org", null) is Dictionary and not (emd["org"] as Dictionary).is_empty():
				_volunteer_org = (emd["org"] as Dictionary).duplicate(true)
		# 恢复环保运行时（城市环保/企业碳排/环保组织）。
		var en: Variant = (state.sim_runtime as Dictionary).get("environment", {})
		if en is Dictionary and not (en as Dictionary).is_empty():
			var end_: Dictionary = en
			if end_.get("city", null) is Dictionary and not (end_["city"] as Dictionary).is_empty():
				_city_env = environment_sys.from_dict(end_["city"])
			if end_.get("enterprise", null) is Dictionary and not (end_["enterprise"] as Dictionary).is_empty():
				_env_enterprise = environment_sys.from_dict(end_["enterprise"])
			if end_.get("org", null) is Dictionary and not (end_["org"] as Dictionary).is_empty():
				_env_org = (end_["org"] as Dictionary).duplicate(true)
		# 恢复市政运行时（城市市政/邮政枢纽/快递员/资质）。
		var mu: Variant = (state.sim_runtime as Dictionary).get("municipal", {})
		if mu is Dictionary and not (mu as Dictionary).is_empty():
			var mud: Dictionary = mu
			if mud.get("city", null) is Dictionary and not (mud["city"] as Dictionary).is_empty():
				_city_municipal = municipal.from_dict(mud["city"])
			if mud.get("hub", null) is Dictionary and not (mud["hub"] as Dictionary).is_empty():
				_postal_hub = municipal.from_dict(mud["hub"])
			if mud.get("courier", null) is Dictionary and not (mud["courier"] as Dictionary).is_empty():
				_courier = (mud["courier"] as Dictionary).duplicate(true)
			_municipal_license = bool(mud.get("license", false))
		# 恢复债务服务运行时（放贷人/借入贷款/放出贷款/典当物）。
		var db: Variant = (state.sim_runtime as Dictionary).get("debt", {})
		if db is Dictionary and not (db as Dictionary).is_empty():
			var dbd: Dictionary = db
			if dbd.get("lender", null) is Dictionary and not (dbd["lender"] as Dictionary).is_empty():
				_debt_lender = debt.from_dict(dbd["lender"])
			if dbd.get("loan", null) is Dictionary and not (dbd["loan"] as Dictionary).is_empty():
				_debt_loan = debt.from_dict(dbd["loan"])
			if dbd.get("lend", null) is Dictionary and not (dbd["lend"] as Dictionary).is_empty():
				_debt_lend = debt.from_dict(dbd["lend"])
			_debt_loans = (dbd.get("loans", []) as Array).duplicate(true)
			_debt_lends = (dbd.get("lends", []) as Array).duplicate(true)
			if _debt_loans.is_empty() and not _debt_loan.is_empty():
				_debt_loans.append(_debt_loan.duplicate(true))
			if _debt_lends.is_empty() and not _debt_lend.is_empty():
				_debt_lends.append(_debt_lend.duplicate(true))
			_debt_pawns = (dbd.get("pawns", []) as Array).duplicate(true)
		# 恢复消费者保护运行时（订单/商品/商家）。
		var cs: Variant = (state.sim_runtime as Dictionary).get("consumer", {})
		if cs is Dictionary and not (cs as Dictionary).is_empty():
			var csd: Dictionary = cs
			if csd.get("order", null) is Dictionary and not (csd["order"] as Dictionary).is_empty():
				_consumer_order = consumer.from_dict(csd["order"])
			if csd.get("product", null) is Dictionary and not (csd["product"] as Dictionary).is_empty():
				_consumer_product = consumer.from_dict(csd["product"])
			if csd.get("merchant", null) is Dictionary and not (csd["merchant"] as Dictionary).is_empty():
				_consumer_merchant = (csd["merchant"] as Dictionary).duplicate(true)
		# 恢复社会救助运行时（申请/基金/社工/个案/变故儿童）。
		var wf: Variant = (state.sim_runtime as Dictionary).get("welfare", {})
		if wf is Dictionary and not (wf as Dictionary).is_empty():
			var wfd: Dictionary = wf
			if wfd.get("application", null) is Dictionary and not (wfd["application"] as Dictionary).is_empty():
				_welfare_application = social_welfare.from_dict(wfd["application"])
			if wfd.get("fund", null) is Dictionary and not (wfd["fund"] as Dictionary).is_empty():
				_welfare_fund = social_welfare.from_dict(wfd["fund"])
			if wfd.get("worker", null) is Dictionary and not (wfd["worker"] as Dictionary).is_empty():
				_welfare_worker = social_welfare.from_dict(wfd["worker"])
			if wfd.get("case", null) is Dictionary and not (wfd["case"] as Dictionary).is_empty():
				_welfare_case = social_welfare.from_dict(wfd["case"])
			if wfd.get("child", null) is Dictionary and not (wfd["child"] as Dictionary).is_empty():
				_welfare_child = social_welfare.from_dict(wfd["child"])
			if wfd.get("recognition", null) is Dictionary and not (wfd["recognition"] as Dictionary).is_empty():
				_welfare_recognition = (wfd["recognition"] as Dictionary).duplicate(true)
		# 恢复殡葬运行时（殡葬状态/经营体）。
		var fn: Variant = (state.sim_runtime as Dictionary).get("funeral", {})
		if fn is Dictionary and not (fn as Dictionary).is_empty():
			var fnd: Dictionary = fn
			if fnd.get("state", null) is Dictionary and not (fnd["state"] as Dictionary).is_empty():
				_funeral_state = funeral.from_dict(fnd["state"])
			if fnd.get("home", null) is Dictionary and not (fnd["home"] as Dictionary).is_empty():
				_funeral_home = funeral.from_dict(fnd["home"])
		# 恢复玄学运行时（求测者/从业者/经营体）。
		var mt: Variant = (state.sim_runtime as Dictionary).get("metaphysics", {})
		if mt is Dictionary and not (mt as Dictionary).is_empty():
			var mtd: Dictionary = mt
			if mtd.get("client", null) is Dictionary and not (mtd["client"] as Dictionary).is_empty():
				_meta_client = metaphysics.from_dict(mtd["client"])
			if mtd.get("practitioner", null) is Dictionary and not (mtd["practitioner"] as Dictionary).is_empty():
				_meta_practitioner = metaphysics.from_dict(mtd["practitioner"])
			if mtd.get("business", null) is Dictionary and not (mtd["business"] as Dictionary).is_empty():
				_meta_business = metaphysics.from_dict(mtd["business"])
		# 恢复异常隔离状态树（默认 hidden，不入常规结算）。
		var an: Variant = (state.sim_runtime as Dictionary).get("anomaly", {})
		if an is Dictionary and not (an as Dictionary).is_empty():
			_anomaly_state = anomaly.from_dict(an)
		# 恢复医疗与医药运行时（病程/手术/区域医疗/医药管线）。
		var md: Variant = (state.sim_runtime as Dictionary).get("medical", {})
		if md is Dictionary and not (md as Dictionary).is_empty():
			var mdd: Dictionary = md
			if mdd.get("cases", null) is Dictionary:
				medical._cases = (mdd["cases"] as Dictionary).duplicate(true)
			if mdd.get("surgeries", null) is Array:
				medical._surgeries = (mdd["surgeries"] as Array).duplicate(true)
			if mdd.get("region", null) is Dictionary and not (mdd["region"] as Dictionary).is_empty():
				_medical_region = medtech.from_dict(mdd["region"])
			if mdd.get("pharma", null) is Dictionary and not (mdd["pharma"] as Dictionary).is_empty():
				_pharma_company = medtech.from_dict(mdd["pharma"])
		# 恢复文娱内容产业运行态（工作室/在研作品/对手/当前 IP）。
		var ct: Variant = (state.sim_runtime as Dictionary).get("content", {})
		if ct is Dictionary and not (ct as Dictionary).is_empty():
			var ctd: Dictionary = ct
			if ctd.get("studio", null) is Dictionary:
				_content_studio = content_industry.from_dict(ctd["studio"])
			if ctd.get("work", null) is Dictionary:
				_content_work = content_industry.from_dict(ctd["work"])
			if ctd.get("rival", null) is Dictionary and not (ctd["rival"] as Dictionary).is_empty():
				_content_rival = content_industry.from_dict(ctd["rival"])
			_content_ip_id = String(ctd.get("ip_id", ""))
			_content_seq = int(ctd.get("seq", 0))
		# 恢复建筑、工程与城市规划运行态（公司/在建工程/城市/开发商）。
		var eg: Variant = (state.sim_runtime as Dictionary).get("engineering", {})
		if eg is Dictionary and not (eg as Dictionary).is_empty():
			var egd: Dictionary = eg
			if egd.get("contractor", null) is Dictionary and not (egd["contractor"] as Dictionary).is_empty():
				_eng_contractor = engineering.from_dict(egd["contractor"])
			if egd.get("project", null) is Dictionary and not (egd["project"] as Dictionary).is_empty():
				_eng_project = engineering.from_dict(egd["project"])
			if egd.get("city", null) is Dictionary and not (egd["city"] as Dictionary).is_empty():
				_eng_city = engineering.from_dict(egd["city"])
			if egd.get("developer", null) is Dictionary and not (egd["developer"] as Dictionary).is_empty():
				_eng_developer = engineering.from_dict(egd["developer"])
		# 恢复专业服务业运行态（事务所/项目）。
		var pf: Variant = (state.sim_runtime as Dictionary).get("professional", {})
		if pf is Dictionary and not (pf as Dictionary).is_empty():
			var pfd: Dictionary = pf
			if pfd.get("firm", null) is Dictionary and not (pfd["firm"] as Dictionary).is_empty():
				_prof_firm = professional.from_dict(pfd["firm"])
			if pfd.get("project", null) is Dictionary and not (pfd["project"] as Dictionary).is_empty():
				_prof_project = professional.from_dict(pfd["project"])
		# 恢复家庭与生活服务业运行态（服务者/服务单）。
		var lf: Variant = (state.sim_runtime as Dictionary).get("life_services", {})
		if lf is Dictionary and not (lf as Dictionary).is_empty():
			var lfd: Dictionary = lf
			if lfd.get("provider", null) is Dictionary and not (lfd["provider"] as Dictionary).is_empty():
				_life_provider = life_services.from_dict(lfd["provider"])
			if lfd.get("order", null) is Dictionary and not (lfd["order"] as Dictionary).is_empty():
				_life_order = life_services.from_dict(lfd["order"])
		# 恢复交通基建运行态（项目/线路/区域）。
		var ti: Variant = (state.sim_runtime as Dictionary).get("transport_infra", {})
		if ti is Dictionary and not (ti as Dictionary).is_empty():
			var tid: Dictionary = ti
			if tid.get("project", null) is Dictionary and not (tid["project"] as Dictionary).is_empty():
				_tin_project = transport_infra.from_dict(tid["project"])
			if tid.get("route", null) is Dictionary and not (tid["route"] as Dictionary).is_empty():
				_tin_route = transport_infra.from_dict(tid["route"])
			if tid.get("region", null) is Dictionary and not (tid["region"] as Dictionary).is_empty():
				_tin_region = transport_infra.from_dict(tid["region"])
	if geo.count() == 0:
		geo.generate(_seed)
	regions.configure_population(_seed)
	# 载入存档中的区域增量（地理由种子重建，存档只存变化量）。
	var saved: Array = _saved_regions()
	if not saved.is_empty() and regions.region_ids().is_empty():
		regions.load_deltas(saved)
	_home_region_id = _resolve_home_region_id()
	if _home_region_id != "" and not regions.has_region(_home_region_id):
		regions.register_region(_home_region_id, _geo_region_opts(_home_region_id))
	if _home_region_id != "":
		regions.enter(_home_region_id, now_minutes())
		_write_player_region(_home_region_id)
	# 补齐气候（存档不持久化气候，按地理重建）并为每个区域绑定天气气候带。
	for rid in regions.region_ids():
		var region = regions.get_region(rid)
		if region != null and String(region.climate) == "":
			region.climate = _climate_for_region(String(rid))
		if not weather.has_region(String(rid)):
			weather.register_region(String(rid), _zone_for_region(String(rid)))
	_ensure_acquaintances()
	_ensure_property_market()
	_ensure_organizations()
	# 读档后补一次领域回写：休眠期间已结算但尚未消费的结果在同一次载入生效。
	_apply_wake_results()

## 生成所在城市的熟人名册（确定性），建立初始关系并恢复婚姻状态。
## 名册由（种子, 区域, 序号）确定，不入档；关系随 player.relations 持久化。
func _ensure_acquaintances() -> void:
	if not _acquaintances.is_empty() or _home_region_id == "":
		return
	for i in ACQUAINTANCE_COUNT:
		var npc: Dictionary = npcs.generate(i, {
			"world_seed": _seed, "region_id": _home_region_id,
			"now_minute": now_minutes(), "individualized": true, "lod_tier": 0,
		})
		_acquaintances.append(npc)
		relations.ensure_relation(player(), String(npc.get("id", "")))
	var sid := String(player().get("family", {}).get("spouse_id", ""))
	if sid != "":
		var spouse := find_person(sid)
		if not spouse.is_empty():
			family.marry(spouse)

## 所在城市熟人名册（供解析目录与社交/婚恋链接）。
func acquaintances() -> Array:
	return _acquaintances

func find_person(person_id: String) -> Dictionary:
	for a in _acquaintances:
		if String((a as Dictionary).get("id", "")) == person_id:
			return a
	if state != null and state.world_delta is Dictionary:
		for n in (state.world_delta as Dictionary).get("npcs", []):
			if typeof(n) == TYPE_DICTIONARY and String(n.get("id", "")) == person_id:
				return n
	return {}

## 名下子女（存档于 world_delta.npcs，按 player.family.children_ids 引用）。
func children() -> Array:
	var out: Array = []
	var fam: Dictionary = player().get("family", {})
	for cid in fam.get("children_ids", []):
		var c := find_person(String(cid))
		if not c.is_empty():
			out.append(c)
	return out

## 是否处于妊娠中。
func is_pregnant() -> bool:
	return not (player().get("family", {}).get("pregnancy", {}) as Dictionary).is_empty()

## 尝试受孕：需已婚且无进行中的妊娠，写入 family.pregnancy（schema 字段）。
func try_conceive() -> Dictionary:
	var fam: Dictionary = player().get("family", {})
	var sid := String(fam.get("spouse_id", ""))
	if sid == "":
		return {"ok": false, "reason": "not_married"}
	if is_pregnant():
		return {"ok": false, "reason": "already_pregnant"}
	var preg: Dictionary = {
		"partner_id": sid,
		"conceived_minutes": now_minutes(),
		"due_minutes": now_minutes() + GESTATION_DAYS * MINUTES_PER_DAY,
	}
	fam["pregnancy"] = preg
	player()["family"] = fam
	return {"ok": true, "pregnancy": preg}

func _write_player_region(region_id: String) -> void:
	if state == null or not (state.player is Dictionary):
		return
	(state.player as Dictionary)["region_id"] = region_id

func _saved_regions() -> Array:
	if state == null or not (state.world_delta is Dictionary):
		return []
	var raw: Variant = (state.world_delta as Dictionary).get("regions", [])
	return raw if raw is Array else []

func _climate_for_region(region_id: String) -> String:
	var node = geo.get_node(region_id)
	return String(node.attributes.get("climate", "")) if node != null else ""

## 区域增量（world_delta.regions，符合 region_delta schema）：仅持久化契约允许的字段，
## 经济/气候等附加量收进 snapshot（additionalProperties=true）。
func regions_delta() -> Array:
	var out: Array = []
	if regions == null:
		return out
	for id in regions.region_ids():
		var r = regions.get_region(id)
		if r == null:
			continue
		var snap: Dictionary = r.snapshot.duplicate(true)
		snap["economy"] = r.economy
		snap["climate"] = r.climate
		out.append({
			"region_key": String(id),
			"population": int(r.population),
			"price_index": float(r.price_index),
			"safety": float(r.safety),
			"last_simulated_minute": int(r.last_simulated_minute),
			"snapshot": snap,
		})
	return out

## 把当前区域增量写回 world_delta.regions（供存档与面板读取）。
func _persist_regions() -> void:
	if state == null or not (state.world_delta is Dictionary):
		return
	(state.world_delta as Dictionary)["regions"] = regions_delta()

## 把领域实体补算运行态写回 sim_runtime.domain_wake。
func _persist_domain_wake() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["domain_wake"] = domain_wake.to_dict()

## 由地理节点派生区域初始状态（人口/经济/物价/治安/气候），并锚定到当前时刻。
func _geo_region_opts(region_id: String) -> Dictionary:
	var opts: Dictionary = {"last_simulated_minute": now_minutes()}
	var node = geo.get_node(region_id)
	if node != null:
		opts["population"] = int(node.attributes.get("population", 0))
		opts["economy"] = float(node.attributes.get("economy", 0.5))
		opts["price_index"] = float(node.attributes.get("price_index", 1.0))
		opts["safety"] = float(node.attributes.get("safety", 50.0))
		opts["climate"] = String(node.attributes.get("climate", ""))
	return opts

## 玩家所在区域：优先取存档中的 player.region_id（旅行/搬迁写入），其次由 player.nation 解析
## 国家取其首个核心城市；均无效时降级默认国家。
func _resolve_home_region_id() -> String:
	var saved: String = String(player().get("region_id", ""))
	if saved != "" and geo.has_node(saved):
		return saved
	var code: String = _nation_country_code()
	var profile = geo.country_profile(code)
	if profile == null or profile.city_ids.is_empty():
		return ""
	return String(profile.city_ids[0])

func _nation_country_code() -> String:
	var nation: String = String(player().get("nation", "")).to_lower()
	if nation.begins_with("nation."):
		nation = nation.substr("nation.".length())
	if nation.length() == 2:
		for code in geo.countries():
			if String(code).to_lower() == nation:
				return String(code)
	return DEFAULT_COUNTRY

func _zone_for_region(region_id: String) -> String:
	var node = geo.get_node(region_id)
	if node != null:
		var climate: String = String(node.attributes.get("climate", ""))
		if CLIMATE_TO_ZONE.has(climate):
			return String(CLIMATE_TO_ZONE[climate])
	return "temperate_continental"

## 当前区域标识（首发固定在所在城市；旅行/搬迁经 set_home_region 覆盖）。
func current_region_id() -> String:
	return _home_region_id

## 当前所在区域的物价指数（相对全国基准，1.0 为基准）；无区域时返回 1.0。
func region_price_index() -> float:
	var rid: String = current_region_id()
	if rid == "" or regions == null or not regions.has_region(rid):
		return 1.0
	var idx: float = float(regions.get_region(rid).price_index)
	return idx if idx > 0.0 else 1.0

## 注册领域实体（案件/工程/灾害/催收/异常/手术）以供离线补算；见 DomainWake。
func domain_register(entry_id: String, kind: String, opts: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = domain_wake.register(entry_id, kind, opts)
	_persist_domain_wake()
	return entry

## 领域补算结果回写：已结算且未消费的条目更新对应领域状态，并标记 applied 保证幂等。
func _apply_wake_results() -> Array:
	var applied: Array = []
	for entry_id in domain_wake.all_entries():
		var e: Dictionary = domain_wake.get_entry(String(entry_id))
		if e.is_empty():
			continue
		var result: Dictionary = e.get("result", {})
		var kind: String = String(e.get("kind", ""))
		var params: Dictionary = e.get("params", {})
		# 贷款利息随休眠持续累计，反复同步且不消费结果。
		if kind == DomainWakeScript.KIND_LOAN:
			var target_loan: Dictionary = _debt_loan if String(params.get("side", "borrow")) == "borrow" else _debt_lend
			if not target_loan.is_empty() and String(params.get("loan_id", "")) == String(target_loan.get("id", "")):
				target_loan["accrued_interest"] = float(result.get("interest", 0.0))
				target_loan["overdue_days"] = float(result.get("overdue_days", 0.0))
				_persist_debt()
				applied.append(String(entry_id))
			continue
		if not domain_wake.is_resolved(String(entry_id)):
			continue
		if bool(result.get("applied", false)):
			continue
		if kind == DomainWakeScript.KIND_PROJECT and not _eng_project.is_empty() \
				and String(_eng_project.get("id", "")) == String(params.get("project_id", "")):
			_eng_project["stage_index"] = engineering.CHAIN.size()
			_eng_project["stage"] = "completed"
			_persist_engineering()
		elif kind == DomainWakeScript.KIND_CASE and not _civil.is_empty():
			var claim: Dictionary = _civil.get("claim", {})
			if not claim.is_empty() and String(params.get("civil_id", "")) == String(e.get("id", "")) \
					and (_civil.get("judgment", {}) as Dictionary).is_empty():
				claim["stage"] = "cold"
				_persist_civil()
		elif kind == DomainWakeScript.KIND_CASE and not _police_case.is_empty() \
				and String(params.get("case_id", "")) == String(e.get("id", "")):
			if String(_police_case.get("stage", "")) != police.STAGE_SOLVED:
				_police_case["stage"] = police.STAGE_COLD
				_persist_police()
		elif kind == DomainWakeScript.KIND_DISASTER and not _incident.is_empty() \
				and String(params.get("incident_at", "")) == String(e.get("id", "")):
			if String(_incident.get("stage", "")) != emergency.STAGE_AFTERMATH:
				_incident["stage"] = emergency.STAGE_AFTERMATH
				_persist_emergency()
		domain_wake.mark_applied(String(entry_id))
		applied.append(String(entry_id))
	_persist_domain_wake()
	return applied


## 与指定熟人结婚：纳入家庭并持久化到 player.family.spouse_id。
func marry_with(person_id: String) -> Dictionary:
	var npc := find_person(person_id)
	if npc.is_empty():
		return {"ok": false, "reason": "unknown_person"}
	family.marry(npc)
	var p: Dictionary = player()
	var fam: Dictionary = p.get("family", {})
	fam["spouse_id"] = String(npc.get("id", ""))
	p["family"] = fam
	var rel: Dictionary = relations.ensure_relation(p, person_id)
	rel["romance"] = true
	relations.set_circle(rel, "family")
	return {"ok": true, "spouse": npc}

## 离婚：结算家庭状态并清除存档婚姻字段。
func divorce() -> Dictionary:
	var r: Dictionary = family.divorce(rng)
	if not bool(r.get("ok", false)):
		return r
	var p: Dictionary = player()
	var fam: Dictionary = p.get("family", {})
	fam.erase("spouse_id")
	p["family"] = fam
	return r

## 当前配偶档案（无则空）。
func spouse() -> Dictionary:
	var sid := String(player().get("family", {}).get("spouse_id", ""))
	return find_person(sid) if sid != "" else {}

## 生成所在城市在售房源（确定性，不入档）；已购入的房源不再挂牌。
func _ensure_property_market() -> void:
	if not _listings.is_empty() or _home_region_id == "":
		return
	var rid := _home_region_id
	var city := rid
	var node = geo.get_node(rid)
	if node != null:
		city = String(node.name)
	var r = RngScript.new(_seed * 1000003 + rid.hash())
	var mult := region_price_index()
	var districts := ["城区", "城郊", "老城", "新区", "湖畔"]
	var layouts := ["1室1厅", "2室1厅", "3室2厅", "4室2厅"]
	for i in PROPERTY_LISTING_COUNT:
		var area := 40 + _rand_int(r, 13) * 10
		var layout: String = layouts[_rand_int(r, layouts.size())]
		var base := int(round(float(area) * (80000.0 + float(_rand_int(r, 60)) * 1000.0) * mult))
		var p: Dictionary = property.make_property({
			"id": "prop:%s:%d" % [rid, i],
			"name": "%s%s房" % [city, districts[i % districts.size()]],
			"city": city,
			"district": districts[i % districts.size()],
			"area_sqm": area,
			"layout": layout,
			"base_price": base,
			"property_fee_month": int(round(float(area) * 2.0)),
			"monthly_rent": int(round(float(base) * 0.0025)),
		})
		if p.is_empty() or not find_owned(String(p.get("id", ""))).is_empty():
			continue
		_listings.append(p)

## 生成所在城市的可加入组织（确定性），载入存档运行时增量。
## 组织由（种子, 区域, 类型序号）确定，不入确定性世界；成员资格随 player.org_memberships
## 持久化，组织运行态（成员数/影响力/热度/派系）随 sim_runtime.organizations 持久化。
func _ensure_organizations() -> void:
	if not _orgs.is_empty() or _home_region_id == "":
		return
	var rid := _home_region_id
	var city := rid
	var node = geo.get_node(rid)
	if node != null:
		city = String(node.name)
	var r = RngScript.new(_seed * 2000003 + rid.hash())
	for i in ORG_TYPES_SEED.size():
		var t: String = ORG_TYPES_SEED[i]
		var def: Dictionary = organizations.type_def(t)
		if def.is_empty():
			continue
		var members := int(def.get("min_members", 5)) + _rand_int(r, 200)
		var created: Dictionary = organizations.create_org(t, members, {
			"id": "org:%s:%d" % [rid, i],
			"name": "%s%s" % [city, String(def.get("name", t))],
		})
		if not bool(created.get("ok", false)):
			continue
		_orgs.append(created["org"])
	if state != null and state.sim_runtime is Dictionary:
		var saved: Variant = (state.sim_runtime as Dictionary).get("organizations", [])
		if saved is Array:
			for so in saved:
				if not (so is Dictionary):
					continue
				var target := find_org(String((so as Dictionary).get("id", "")))
				if target.is_empty():
					continue
				for k in (so as Dictionary).keys():
					target[k] = (so as Dictionary)[k]

func _rand_int(r, bound: int) -> int:
	if bound <= 0:
		return 0
	return mini(bound - 1, int(r.next_float() * float(bound)))

## 在售房源视图（含市场估值报价）。
func property_listings() -> Array:
	var out: Array = []
	for p in _listings:
		var v: Dictionary = property.view(p)
		v["price"] = property.market_value(p, {"rate": PropertyScript.MORTGAGE_RATE_ANNUAL})
		v["monthly_payment"] = property.mortgage_payment(
			int(round(float(v["price"]) * (1.0 - PropertyScript.DOWN_PAYMENT_RATIO))))
		out.append(v)
	return out

## 名下房产视图。
func property_owned() -> Array:
	var out: Array = []
	for p in property.owned_properties(player()):
		var v: Dictionary = property.view(p)
		v["price"] = property.market_value(p)
		v["rented"] = bool(p.get("rented", false))
		v["has_mortgage"] = not (p.get("mortgage", {}) as Dictionary).is_empty()
		out.append(v)
	return out

## 解析目录用房源清单（在售 + 名下），供「买房/卖房/出租 <房源>」链接。
func property_catalog() -> Array:
	var out: Array = []
	for p in _listings:
		out.append({"id": String(p.get("id", "")), "name": String(p.get("name", "")), "owned": false})
	for p in property.owned_properties(player()):
		out.append({"id": String(p.get("id", "")), "name": String(p.get("name", "")), "owned": true})
	return out

func find_listing(prop_id: String) -> Dictionary:
	for p in _listings:
		if String((p as Dictionary).get("id", "")) == prop_id:
			return p
	return {}

func find_owned(prop_id: String) -> Dictionary:
	for p in property.owned_properties(player()):
		if String((p as Dictionary).get("id", "")) == prop_id:
			return p
	return {}

## 购买房源：扣首付/契税、形成房贷并计入名下资产，从挂牌移除。
func property_purchase(prop_id: String, opts: Dictionary = {}) -> Dictionary:
	var prop := find_listing(prop_id)
	if prop.is_empty():
		return {"ok": false, "reason": "not_listed"}
	var r: Dictionary = property.purchase(player(), economy, account_id(), prop, day_index(), opts)
	if bool(r.get("ok", false)):
		_listings.erase(prop)
		sync_finances()
	return r

## 出售名下房产。
func property_sell(prop_id: String, opts: Dictionary = {}) -> Dictionary:
	var prop := find_owned(prop_id)
	if prop.is_empty():
		return {"ok": false, "reason": "not_owned"}
	var r: Dictionary = property.sell(player(), economy, account_id(), prop, opts)
	if bool(r.get("ok", false)):
		sync_finances()
	return r

## 出租名下房产（设定月租并按月收租）。
func property_rent(prop_id: String, monthly_rent: int = -1) -> Dictionary:
	var prop := find_owned(prop_id)
	if prop.is_empty():
		return {"ok": false, "reason": "not_owned"}
	var rent: int = monthly_rent if monthly_rent >= 0 else int(property.estimated_monthly_rent(prop))
	property.set_rent(prop, rent, true)
	return {"ok": true, "monthly_rent": rent}

# --- 组织与社团（D19） ---

## 可加入组织目录（供解析器链接「加入组织 <组织>」）。
func organizations_catalog() -> Array:
	var out: Array = []
	for org in _orgs:
		out.append({"id": String((org as Dictionary).get("id", "")), "name": String((org as Dictionary).get("name", ""))})
	return out

func find_org(org_id: String) -> Dictionary:
	for org in _orgs:
		if (org is Dictionary) and String((org as Dictionary).get("id", "")) == org_id:
			return org
	return {}

## 加入组织：写入成员契约并扣除首次会费（不足则回滚）。
func join_organization(org_id: String) -> Dictionary:
	var org := find_org(org_id)
	if org.is_empty():
		return {"ok": false, "reason": "not_found"}
	var r: Dictionary = organizations.join(player(), org, {"minute": now_minutes()})
	if not bool(r.get("ok", false)):
		return r
	var fee := int(r.get("dues", 0))
	if fee > 0:
		if economy.cash(account_id()) < fee:
			organizations.leave(player(), org, {"approved": true})
			return {"ok": false, "reason": "insufficient_funds", "dues": fee}
		economy.add_money(account_id(), -fee, "org_dues:%s" % org_id)
		sync_finances()
		var entry: Dictionary = organizations.membership(player(), org_id)
		if not entry.is_empty():
			organizations.pay_dues(entry, fee)
	_persist_organizations()
	r["name"] = String(org.get("name", ""))
	return r

## 退出组织：结算退出成本与叛逃/法律风险。
func leave_organization(org_id: String, approved: bool = false) -> Dictionary:
	var org := find_org(org_id)
	if org.is_empty():
		return {"ok": false, "reason": "not_found"}
	var r: Dictionary = organizations.leave(player(), org, {"approved": approved})
	if bool(r.get("ok", false)):
		_persist_organizations()
	r["name"] = String(org.get("name", ""))
	return r

## 缴纳组织会费（缺省清欠全部）。
func pay_org_dues(org_id: String, amount: int = -1) -> Dictionary:
	var entry: Dictionary = organizations.membership(player(), org_id)
	if entry.is_empty():
		return {"ok": false, "reason": "not_member"}
	var owed := int(entry.get("dues_owed", 0))
	var pay := owed if amount < 0 else mini(amount, owed)
	if pay <= 0:
		return {"ok": false, "reason": "nothing_due"}
	if economy.cash(account_id()) < pay:
		return {"ok": false, "reason": "insufficient_funds", "dues": pay}
	economy.add_money(account_id(), -pay, "org_dues:%s" % org_id)
	sync_finances()
	var r: Dictionary = organizations.pay_dues(entry, pay)
	_persist_organizations()
	return r

## 承接并完成一次组织任务：成功计任务数并可能晋升（晋升发放津贴）。
func do_org_task(org_id: String) -> Dictionary:
	var org := find_org(org_id)
	if org.is_empty():
		return {"ok": false, "reason": "not_found"}
	var entry: Dictionary = organizations.membership(player(), org_id)
	if entry.is_empty():
		return {"ok": false, "reason": "not_member"}
	if String(entry.get("pending_task", "")).is_empty():
		organizations.assign_task(org, entry, "organizing")
	var success: bool = rng.next_float() < 0.6
	var r: Dictionary = organizations.complete_task(org, entry, success)
	var promoted := false
	if success and organizations.evaluate_promotion(org, entry):
		var pr: Dictionary = organizations.promote(org, entry)
		promoted = bool(pr.get("ok", false))
		if promoted:
			var stip: int = organizations.stipend(entry)
			if stip > 0:
				economy.add_money(account_id(), stip, "org_stipend:%s" % org_id)
				sync_finances()
	r["promoted"] = promoted
	r["rank_name"] = String((organizations.rank(int(entry.get("rank_index", 0))) as Dictionary).get("name", ""))
	_persist_organizations()
	return r

## 发起集体行动（罢工/请愿/募捐/游行/抵制）；秘密组织可能因失败抬升热度而暴露。
func org_collective_action(org_id: String, action: String) -> Dictionary:
	var org := find_org(org_id)
	if org.is_empty():
		return {"ok": false, "reason": "not_found"}
	var entry: Dictionary = organizations.membership(player(), org_id)
	if entry.is_empty():
		return {"ok": false, "reason": "not_member"}
	var r: Dictionary = organizations.collective_action(org, action, {}, rng)
	if not bool(r.get("ok", false)):
		return r
	if organizations.is_secret(org):
		var ex: Dictionary = organizations.attempt_expose(org, {}, rng)
		if bool(ex.get("exposed", false)):
			var hx: Dictionary = organizations.handle_exposure(player(), org)
			r["exposed"] = true
			r["wanted_level"] = int(hx.get("wanted_level", 0))
	_persist_organizations()
	return r

## 组织面板数据（已加入成员资格 + 可加入组织）。
func organizations_panel_data() -> Dictionary:
	var memberships: Array = []
	for entry in organizations.memberships(player()):
		if not (entry is Dictionary):
			continue
		var org := find_org(String((entry as Dictionary).get("org_id", "")))
		if org.is_empty():
			continue
		var type_def: Dictionary = organizations.type_def(String(org.get("type", "")))
		var rank_def: Dictionary = organizations.rank(int((entry as Dictionary).get("rank_index", 0)))
		memberships.append({
			"id": String(org.get("id", "")),
			"name": String(org.get("name", "")),
			"type": String(type_def.get("name", "")),
			"legality": String(org.get("legality", "")),
			"rank": String(rank_def.get("name", "")),
			"members": int(org.get("members", 0)),
			"influence": "%s%%" % str(snappedf(float(org.get("influence", 0.0)) * 100.0, 0.1)),
			"dues_owed": int((entry as Dictionary).get("dues_owed", 0)),
			"tasks_completed": int((entry as Dictionary).get("tasks_completed", 0)),
		})
	var available: Array = []
	for org in _orgs:
		if not organizations.membership(player(), String((org as Dictionary).get("id", ""))).is_empty():
			continue
		var td: Dictionary = organizations.type_def(String((org as Dictionary).get("type", "")))
		available.append({
			"id": String((org as Dictionary).get("id", "")),
			"name": String((org as Dictionary).get("name", "")),
			"type": String(td.get("name", "")),
			"fee": int(td.get("base_fee", 0)),
			"legality": String((org as Dictionary).get("legality", "")),
		})
	return {"memberships": memberships, "available": available}

## 持久化组织运行态到 state.sim_runtime.organizations。
func _persist_organizations() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	var arr: Array = []
	for org in _orgs:
		arr.append((org as Dictionary).duplicate(true))
	(state.sim_runtime as Dictionary)["organizations"] = arr

# --- 语言与文化（D20） ---

## 可学语言目录（供解析器链接「学语言 <语言>」）。
func languages_catalog() -> Array:
	var out: Array = []
	for lang in language.languages():
		var def: Dictionary = language.language_def(String(lang))
		out.append({"id": String(lang), "name": String(def.get("name", lang))})
	return out

func language_state() -> Dictionary:
	return _lang_profile

## 学习语言：按课程/沉浸/自学推进分项等级。opts 可含 aptitude。
func study_language(lang: String, method: String, hours: float, opts: Dictionary = {}) -> Dictionary:
	if not language.has_language(lang):
		return {"ok": false, "reason": "unknown_language"}
	if not language.STUDY_METHODS.has(method):
		return {"ok": false, "reason": "unknown_method"}
	var o: Dictionary = opts.duplicate()
	o["day"] = day_index()
	var r: Dictionary = language.study(_lang_profile, lang, method, hours, o)
	if bool(r.get("ok", false)):
		_persist_language()
	return r

## 环境沉浸：以沉浸法按天学习。
func immerse_language(lang: String, days: float) -> Dictionary:
	if not language.has_language(lang):
		return {"ok": false, "reason": "unknown_language"}
	var o: Dictionary = {"day": day_index()}
	var r: Dictionary = language.immerse(_lang_profile, lang, days, o)
	if bool(r.get("ok", false)):
		_persist_language()
	return r

## 参加语言考试：达到目标等级颁发证书。
func take_language_exam(lang: String, target_level: float) -> Dictionary:
	if not language.has_language(lang):
		return {"ok": false, "reason": "unknown_language"}
	var r: Dictionary = language.take_exam(_lang_profile, lang, target_level, {}, rng)
	if bool(r.get("ok", false)):
		_persist_language()
	return r

## 文化适应：按天推进对某文化的适应度并降低文化冲击。
func adapt_culture(culture: String, days: float) -> Dictionary:
	if language.culture_def(culture).is_empty():
		return {"ok": false, "reason": "unknown_culture"}
	var r: Dictionary = language.adapt(_culture, culture, days)
	if bool(r.get("ok", false)):
		_persist_language()
	return r

## 当日节日效果（基于日历，用于商铺/交通/社交/心情联动）。
func today_festival_effects() -> Dictionary:
	var cal: Dictionary = GregorianScript.from_absolute_minutes(now_minutes())
	return language.festival_effects(int(cal.get("month", 1)), int(cal.get("day", 1)))

## 语言与文化面板数据（语言分项/证书/文化适应/今日节日）。
func language_panel_data() -> Dictionary:
	var langs: Array = []
	for lang in language.languages():
		var key := String(lang)
		var def: Dictionary = language.language_def(key)
		langs.append({
			"id": key,
			"name": String(def.get("name", key)),
			"overall": snappedf(language.overall(_lang_profile, key), 0.1),
			"speaking": snappedf(language.component(_lang_profile, key, "speaking"), 0.1),
			"listening": snappedf(language.component(_lang_profile, key, "listening"), 0.1),
			"literacy": snappedf(language.component(_lang_profile, key, "literacy"), 0.1),
		})
	var certs: Array = []
	for c in language.certificates(_lang_profile):
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		var ldef: Dictionary = language.language_def(String(cd.get("lang", "")))
		certs.append({"label": "%s 等级 %.0f" % [String(ldef.get("name", cd.get("lang", ""))), float(cd.get("level", 0.0))], "value": "已获证书"})
	var cults: Array = []
	for ck in language.CULTURES.keys():
		var key := String(ck)
		cults.append({
			"name": String((language.CULTURES[ck] as Dictionary).get("name", key)),
			"adaptation": snappedf(language.current_adaptation(_culture, key), 0.01),
		})
	return {
		"languages": langs,
		"certificates": certs,
		"cultures": cults,
		"shock": snappedf(float(_culture.get("shock", 0.0)), 0.01),
		"festival": today_festival_effects(),
	}

## 语言遗忘：跨日推进时对长期未用语言按闲置天数衰减。
func _decay_languages(before_minutes: int, after_minutes: int) -> void:
	if after_minutes / MINUTES_PER_DAY <= before_minutes / MINUTES_PER_DAY:
		return
	var langs: Variant = _lang_profile.get("languages", {})
	if not (langs is Dictionary):
		return
	for lang in (langs as Dictionary).keys():
		var entry: Dictionary = (langs as Dictionary)[lang]
		var last_day: float = float(entry.get("last_used_day", 0.0))
		var idle: float = float(day_index()) - last_day
		if idle > 0.0:
			language.decay(_lang_profile, String(lang), idle)

func _persist_language() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["language"] = language.to_dict(_lang_profile)
	(state.sim_runtime as Dictionary)["culture"] = language.to_dict(_culture)


# --- 残障与养老（D21） ---

func disability_state() -> Dictionary:
	return _disability

## 辅具目录（供解析器链接「装辅具 <辅具>」）。
func disability_devices_catalog() -> Array:
	var out: Array = []
	for key in disability.DEVICES.keys():
		var d: Dictionary = disability.DEVICES[key]
		out.append({"id": String(key), "name": String(d.get("name", key)), "cost": int(d.get("cost", 0))})
	return out

## 养老模式目录（供解析器链接「选养老 <模式>」）。
func care_modes_catalog() -> Array:
	var out: Array = []
	for key in disability.CARE_MODES.keys():
		var d: Dictionary = disability.CARE_MODES[key]
		out.append({"id": String(key), "name": String(d.get("name", key)), "cost_per_month": int(d.get("cost_per_month", 0))})
	return out

## 获得残障（事件/叙事驱动；运行时可调用）。
func acquire_disability(d_type: String, source: String, severity: String) -> Dictionary:
	var r: Dictionary = disability.acquire(_disability, d_type, source, severity)
	if bool(r.get("ok", false)):
		_persist_disability()
	return r

## 装配辅具：扣除花费并提升移动能力。
func fit_disability_device(device_key: String) -> Dictionary:
	var r: Dictionary = disability.fit_device(_disability, device_key)
	if not bool(r.get("ok", false)):
		return r
	var cost := int(r.get("cost", 0))
	if cost > 0:
		if economy.cash(account_id()) < cost:
			(_disability["devices"] as Array).erase(device_key)
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "disability_device:%s" % device_key)
		sync_finances()
	_persist_disability()
	return r

## 手术/康复训练：部分恢复能力（默认 0.3），扣康复花费。
func disability_surgery(amount: float = 0.3) -> Dictionary:
	var cost := 200000
	if economy.cash(account_id()) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	economy.add_money(account_id(), -cost, "disability_surgery")
	sync_finances()
	var r: Dictionary = disability.surgery_recovery(_disability, amount)
	_persist_disability()
	return r

## 无障碍改造（居所/常去场所）：减少移动惩罚并扣除改造费。
func set_accessible_place(accessible: bool = true) -> Dictionary:
	if accessible:
		var cost := 150000
		if economy.cash(account_id()) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "disability_accessible")
		sync_finances()
	var r: Dictionary = disability.set_accessible(_disability, accessible)
	_persist_disability()
	return r

## 选择养老模式（居家/社区/机构）。
func choose_care_mode(mode: String) -> Dictionary:
	var r: Dictionary = disability.choose_care_mode(_disability, mode)
	if bool(r.get("ok", false)):
		_persist_disability()
	return r

## 结算 months 个月养老：扣除成本并返回心情/寿命修正。
func settle_care(months: float) -> Dictionary:
	var r: Dictionary = disability.care_outcome(_disability, months)
	if not bool(r.get("ok", false)):
		return r
	var cost := int(r.get("cost", 0))
	if cost > 0:
		if economy.cash(account_id()) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "disability_care")
		sync_finances()
	_persist_disability()
	return r

## 临终关怀。
func hospice_care(quality: float = 0.8) -> Dictionary:
	var r: Dictionary = disability.hospice_care(_disability, quality)
	_persist_disability()
	return r

## 抽取一次护工事件（按当前养老模式质量）。
func roll_caregiver_event() -> Dictionary:
	var mode := String(_disability.get("care_mode", ""))
	var cm: Dictionary = disability.CARE_MODES.get(mode, {})
	var quality := float(cm.get("quality", 0.5))
	_care_incident = disability.caregiver_event(quality, {}, rng)
	return _care_incident

## 追责上次护工事件（赔偿 + 吊销资格/刑责）。
func hold_caregiver_accountable() -> Dictionary:
	var r: Dictionary = disability.hold_accountable(_care_incident)
	if bool(r.get("ok", false)):
		var comp := int(r.get("compensation", 0))
		if comp > 0:
			economy.add_money(account_id(), comp, "caregiver_compensation")
			sync_finances()
		_care_incident = {}
	return r

## 建立监护（仅在丧失决策能力时成立）。
func establish_guardianship(guardian_id: String) -> Dictionary:
	var r: Dictionary = disability.establish_guardianship(_disability, guardian_id)
	if bool(r.get("ok", false)):
		_persist_disability()
	return r

## 残障与养老面板数据。
func disability_panel_data() -> Dictionary:
	var conditions: Array = []
	for c in (_disability.get("conditions", []) as Array):
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		conditions.append({
			"type": String(disability.TYPE_NAMES.get(String(cd.get("type", "")), cd.get("type", ""))),
			"source": String(disability.SOURCE_NAMES.get(String(cd.get("source", "")), cd.get("source", ""))),
			"severity": String(disability.SEVERITY_NAMES.get(String(cd.get("severity", "")), cd.get("severity", ""))),
		})
	var devices: Array = []
	for key in (_disability.get("devices", []) as Array):
		var dev: Dictionary = disability.DEVICES.get(str(key), {})
		devices.append({"name": String(dev.get("name", key))})
	var mode_key := String(_disability.get("care_mode", ""))
	var mode_def: Dictionary = disability.CARE_MODES.get(mode_key, {})
	return {
		"conditions": conditions,
		"mobility": snappedf(disability.mobility(_disability), 0.01),
		"devices": devices,
		"recovery": snappedf(float(_disability.get("recovery", 0.0)), 0.01),
		"accessible": bool(_disability.get("accessible", false)),
		"retirement_years": snappedf(float(_disability.get("retirement_years", 0.0)), 0.1),
		"care_mode": String(mode_def.get("name", mode_key)),
		"care_quality": snappedf(float(mode_def.get("quality", 0.0)), 0.01),
		"cognitive": disability.has_cognitive_impairment(_disability),
		"decision_capacity": disability.decision_capacity(_disability),
		"will_valid": disability.is_will_valid(_disability),
		"guardian": String(_disability.get("guardian", "")),
		"hospice": bool(_disability.get("hospice", false)),
	}

func _persist_disability() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["disability"] = disability.to_dict(_disability)


# --- 农业与乡土（D22） ---

func farm_state() -> Dictionary:
	return _farm

## 作物目录（供解析器链接「播种 <作物>」）。
func agri_crops_catalog() -> Array:
	var out: Array = []
	for key in agriculture.CROPS.keys():
		var d: Dictionary = agriculture.CROPS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 牲畜目录（供解析器链接「养畜 <牲畜>」）。
func agri_livestock_catalog() -> Array:
	var out: Array = []
	for key in agriculture.LIVESTOCK.keys():
		var d: Dictionary = agriculture.LIVESTOCK[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 取得土地（承包/购买/流转/租赁）。
func acquire_farm_land(area: float, use: String, mode: String, price_per_area: int, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = agriculture.acquire_land(_farm, area, use, mode, price_per_area, opts)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 在指定地块播种。
func plant_crop(land_index: int, crop_key: String, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = agriculture.plant(_farm, land_index, crop_key, opts)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 推进作物生长（按天）。
func grow_farm(days: float) -> Dictionary:
	var r: Dictionary = agriculture.grow(_farm, days)
	return r

## 收割指定地块。
func harvest_crop(plot_index: int, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = agriculture.harvest(_farm, plot_index, opts)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 增加牲畜存栏。
func add_farm_livestock(animal: String, count: int) -> Dictionary:
	var r: Dictionary = agriculture.add_livestock(_farm, animal, count)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 喂养牲畜。
func feed_farm_livestock(days: float, feed_available: float) -> Dictionary:
	var r: Dictionary = agriculture.feed_livestock(_farm, days, feed_available)
	_persist_farm()
	return r

## 售卖农产品/牲畜。
func sell_produce(item: String, amount: float, channel: String = "market", opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = agriculture.sell(_farm, item, amount, channel, opts)
	if bool(r.get("ok", false)):
		_persist_farm()
	return r

## 申领农业补贴。
func apply_farm_subsidy(amount: int) -> Dictionary:
	var r: Dictionary = agriculture.apply_subsidy(_farm, amount)
	_persist_farm()
	return r

## 农业与乡土面板数据。
func farm_panel_data() -> Dictionary:
	var lands: Array = []
	for l in (_farm.get("land", []) as Array):
		if not (l is Dictionary):
			continue
		var ld: Dictionary = l
		lands.append({
			"id": String(ld.get("id", "")),
			"area": snappedf(float(ld.get("area", 0.0)), 0.1),
			"use": String(agriculture.LAND_MODE_NAMES.get(String(ld.get("mode", "")), ld.get("mode", ""))),
			"fertility": snappedf(float(ld.get("fertility", 0.0)), 0.01),
			"value": int(ld.get("asset_value", 0)),
		})
	var plots: Array = []
	for p in (_farm.get("plots", []) as Array):
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var crop: Dictionary = agriculture.crop_def(String(pd.get("crop", "")))
		plots.append({
			"name": String(crop.get("name", pd.get("crop", ""))),
			"stage": String(pd.get("stage", "")),
			"elapsed": snappedf(float(pd.get("elapsed", 0.0)), 0.1),
			"growth_days": snappedf(float(pd.get("growth_days", 0.0)), 0.1),
		})
	var livestock: Array = []
	for a in (_farm.get("livestock", []) as Array):
		if not (a is Dictionary):
			continue
		var ad: Dictionary = a
		var def: Dictionary = agriculture.livestock_def(String(ad.get("animal", "")))
		livestock.append({"name": String(def.get("name", ad.get("animal", ""))), "count": int(ad.get("count", 0))})
	var storage: Dictionary = _farm.get("storage", {})
	var inventory: Array = []
	for item in storage.keys():
		var qty := float(storage[item])
		if qty <= 0.0:
			continue
		var cd: Dictionary = agriculture.crop_def(String(item))
		inventory.append({"name": String(cd.get("name", item)), "count": snappedf(qty, 0.1)})
	return {
		"money": int(_farm.get("money", 0)),
		"land_value": agriculture.land_asset_value(_farm),
		"lands": lands,
		"plots": plots,
		"livestock": livestock,
		"inventory": inventory,
		"subsidy": snappedf(float(_farm.get("subsidy", 0.0)), 1.0),
		"year_income": int(_farm.get("year_income", 0)),
		"coop": String(_farm.get("coop", "")),
	}

## 农场按日推进：作物生长并仓储损耗。
func _advance_farm(before_minutes: int, after_minutes: int) -> void:
	var before_day: int = before_minutes / MINUTES_PER_DAY
	var after_day: int = after_minutes / MINUTES_PER_DAY
	if after_day <= before_day:
		return
	var days: float = float(after_day - before_day)
	agriculture.grow(_farm, days)
	agriculture.storage_spoil(_farm, days)

func _persist_farm() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["farm"] = agriculture.to_dict(_farm)


# --- 数字生活与黑客（D23） ---

## 玩家技能等级（按技能 id），用于数字/黑客判定。
func _skill_level(id: String) -> int:
	return skills.level_of(player().get("skills", []), id)

func digital_state() -> Dictionary:
	return _identity

## 内容平台目录（供解析器链接「发布内容 <平台>」）。
func digital_platforms_catalog() -> Array:
	var out: Array = []
	for key in digital.CONTENT_PLATFORMS.keys():
		var d: Dictionary = digital.CONTENT_PLATFORMS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 黑客目标目录（供解析器链接「黑客攻击 <目标>」）。
func digital_hack_targets_catalog() -> Array:
	var out: Array = []
	for key in digital.HACK_TARGETS.keys():
		var d: Dictionary = digital.HACK_TARGETS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 网络安全职业目录（合法方向）。
func digital_security_jobs_catalog() -> Array:
	var out: Array = []
	for key in digital.SECURITY_JOBS.keys():
		var d: Dictionary = digital.SECURITY_JOBS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 开通平台账号。
func open_digital_account(platform: String) -> Dictionary:
	if platform.strip_edges().is_empty():
		return {"ok": false, "reason": "unknown_platform"}
	var r: Dictionary = digital.create_account(_identity, platform, {"real_name": bool(_identity.get("real_name_verified", false))})
	_persist_digital()
	return r

## 实名认证。
func verify_digital_identity() -> Dictionary:
	var r: Dictionary = digital.verify_real_name(_identity, true)
	_persist_digital()
	return r

## 增加数字资产（账号/虚拟物品/加密钱包）。
func add_digital_asset(asset_type: String, value: int) -> Dictionary:
	var r: Dictionary = digital.add_asset(_identity, asset_type, value)
	_persist_digital()
	return r

## 从事网络安全工作（合法方向，无法律风险）。
func digital_security_work(kind: String) -> Dictionary:
	var skill: float = float(_skill_level("hacking")) * 5.0
	var r: Dictionary = digital.security_job(kind, skill)
	if bool(r.get("ok", false)) and int(r.get("income", 0)) > 0:
		economy.add_money(account_id(), int(r["income"]), "security_job")
	_persist_digital()
	return r

## 实施未授权入侵（游戏内虚构抽象判定）。
func digital_hack(target: String) -> Dictionary:
	var skill: float = float(_skill_level("hacking")) * 5.0
	var r: Dictionary = digital.hack(target, skill)
	if bool(r.get("ok", false)) and int(r.get("gain", 0)) > 0:
		economy.add_money(account_id(), int(r["gain"]), "hack")
	_persist_digital()
	return r

## 发布内容（直播/短视频），首次自动开通创作者身份。
func publish_digital_content(platform: String = "short_video") -> Dictionary:
	if _creator.is_empty() or String(_creator.get("platform", "")) != platform:
		_creator = digital.new_creator("player", platform)
	var r: Dictionary = digital.publish_content(_creator)
	if bool(r.get("ok", false)) and int(r.get("income", 0)) > 0:
		economy.add_money(account_id(), int(r["income"]), "content_income")
	_persist_digital()
	return r

## 上网时长结算网络成瘾。
func digital_addiction(hours: float) -> Dictionary:
	var r: Dictionary = digital.internet_addiction(hours)
	_identity["addiction"] = float(r.get("addiction", 0.0))
	_persist_digital()
	return r

## 数字与平台面板数据。
func digital_panel_data() -> Dictionary:
	var accounts: Array = []
	var acct: Dictionary = _identity.get("accounts", {})
	for key in acct.keys():
		var a: Dictionary = acct[key]
		accounts.append({"platform": String(key), "real_name": bool(a.get("real_name", false)), "privacy": snappedf(float(a.get("privacy", 0.0)), 0.01)})
	var assets: Array = []
	for a in (_identity.get("assets", []) as Array):
		if a is Dictionary:
			var ad: Dictionary = a
			assets.append({"type": String(ad.get("type", "")), "value": int(ad.get("value", 0)), "stolen": bool(ad.get("stolen", false))})
	var leaked := 0
	var total := 0
	for d in (_identity.get("data", []) as Array):
		if d is Dictionary:
			total += 1
			if bool((d as Dictionary).get("leaked", false)):
				leaked += 1
	return {
		"real_name_verified": bool(_identity.get("real_name_verified", false)),
		"privacy": snappedf(float(_identity.get("privacy", 0.0)), 0.01),
		"exposure_heat": snappedf(float(_identity.get("exposure_heat", 0.0)), 0.1),
		"addiction": snappedf(float(_identity.get("addiction", 0.0)), 0.01),
		"accounts": accounts,
		"assets": assets,
		"data_total": total,
		"data_leaked": leaked,
		"creator": _creator.duplicate(true),
		"esports": _esports.duplicate(true),
	}

func _persist_digital() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["digital"] = {
		"identity": digital.to_dict(_identity),
		"creator": _creator.duplicate(true),
		"esports": _esports.duplicate(true),
	}


# --- 后期科技（D24） ---

func late_tech_state() -> Dictionary:
	return _late_tech

## 科技阶段目录。
func late_tech_stages_catalog() -> Array:
	var out: Array = []
	for key in late_tech.STAGES:
		out.append({"id": String(key), "name": String(late_tech.stage_def(String(key)).get("name", key))})
	return out

## 科技职业目录（按阶段门控，含技能门槛与薪资）。
func late_tech_careers_catalog() -> Array:
	var out: Array = []
	for key in late_tech.CAREERS.keys():
		var d: Dictionary = late_tech.CAREERS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 高风险科技任务目录。
func late_tech_missions_catalog() -> Array:
	var out: Array = []
	for key in late_tech.MISSIONS.keys():
		var d: Dictionary = late_tech.MISSIONS[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 解锁下一科技阶段（严格顺序）。
func unlock_late_tech_stage() -> Dictionary:
	var idx: int = int(_late_tech.get("stage_index", 0))
	if idx + 1 >= late_tech.stage_count():
		return {"ok": false, "reason": "max_stage"}
	var r: Dictionary = late_tech.unlock_stage(_late_tech, idx + 1)
	if bool(r.get("ok", false)):
		_persist_late_tech()
	return r

## 应聘科技职业。技能等级取该职业所要求技能树的当前等级。
func apply_late_tech_career(career_key: String) -> Dictionary:
	if not late_tech.CAREERS.has(career_key):
		return {"ok": false, "reason": "unknown_career"}
	var def: Dictionary = late_tech.CAREERS[career_key]
	var skill_level: int = _skill_level(String(def.get("skill", "")))
	var r: Dictionary = late_tech.apply_for_career(_late_tech, career_key, skill_level)
	_persist_late_tech()
	return r

## 执行高风险科技任务。技能等级取任务环境对应的技能树等级（用最高职业技能近似）。
func risk_late_tech_mission(mission_key: String) -> Dictionary:
	if not late_tech.MISSIONS.has(mission_key):
		return {"ok": false, "reason": "unknown_mission"}
	var skill_level: int = _late_tech_best_skill()
	var r: Dictionary = late_tech.risk_mission(_late_tech, mission_key, skill_level)
	if bool(r.get("ok", false)) and int(r.get("reward", 0)) > 0:
		economy.add_money(account_id(), int(r["reward"]), "late_tech_mission")
	_persist_late_tech()
	return r

## 生物科技延寿投资。
func invest_biotech_lifespan(investment: float) -> Dictionary:
	var r: Dictionary = late_tech.biotech_lifespan(_late_tech, investment)
	_persist_late_tech()
	return r

## 极端环境目录（失重/辐射/深海高压）。
func late_tech_environments_catalog() -> Array:
	var out: Array = []
	for key in late_tech.ENVIRONMENTS.keys():
		out.append({"id": String(key), "name": String((late_tech.ENVIRONMENTS[key] as Dictionary).get("name", key))})
	return out

## 自动化冲击评估：效率提升淘汰传统岗位，可能触发失业危机。
func late_tech_automation_impact(efficiency: float = 1.0) -> Dictionary:
	var r: Dictionary = late_tech.automation_impact(_late_tech, clampf(efficiency, 0.0, 2.0), {})
	_late_tech["last_report"] = {"kind": "automation", "result": r.duplicate(true)}
	_persist_late_tech()
	return r

## 极端环境暴露：扣减玩家健康并返回骨/肌/辐射/压力分项。
func late_tech_extreme_environment(environment: String, exposure: float = 1.0) -> Dictionary:
	var r: Dictionary = late_tech.extreme_environment_effect(environment, maxf(0.0, exposure), {"tolerance": clampf(float(_late_tech.get("lifespan_bonus", 0.0)) / 50.0, 0.0, 0.3)})
	if not bool(r.get("ok", false)):
		return r
	var penalty: float = float(r.get("health_penalty", 0.0))
	if penalty > 0.0:
		_damage_health(penalty * 100.0)
	_late_tech["last_report"] = {"kind": "environment", "result": r.duplicate(true)}
	_persist_late_tech()
	return r

## 气候难民评估：按升温与沿海人口估算难民规模并记账。
func late_tech_climate_refugees(warming: float = 2.0) -> Dictionary:
	var r: Dictionary = late_tech.climate_refugees(_late_tech, maxf(0.0, warming), {})
	_late_tech["last_report"] = {"kind": "climate", "result": r.duplicate(true)}
	_persist_late_tech()
	return r

## AI 伦理失控演练：按自主性判定失控概率与技术事故连锁。
func late_tech_ai_ethics_incident(autonomy: float = 0.9) -> Dictionary:
	var r: Dictionary = late_tech.ai_ethics_incident(_late_tech, clampf(autonomy, 0.0, 1.0), {"risk": 0.05, "critical": true}, rng)
	_late_tech["last_report"] = {"kind": "ai", "result": r.duplicate(true)}
	_persist_late_tech()
	return r

## 健康扣减：写成生理健康字段，供极端环境等外部惩罚使用。
func _damage_health(amount: float) -> void:
	if amount <= 0.0:
		return
	var attrs: Dictionary = player().get("attrs", {})
	var phys: Dictionary = attrs.get("physiological", {})
	phys["health"] = clampf(float(phys.get("health", 100.0)) - amount, 0.0, 100.0)
	attrs["physiological"] = phys
	player()["attrs"] = attrs

## 取职业路径中的最高技能等级（近似玩家科技素养）。
func _late_tech_best_skill() -> int:
	var best: int = 0
	for key in late_tech.CAREERS.keys():
		var def: Dictionary = late_tech.CAREERS[key]
		var lv: int = _skill_level(String(def.get("skill", "")))
		best = maxi(best, lv)
	return best

## 后期科技面板数据。
func late_tech_panel_data() -> Dictionary:
	var stage_key: String = late_tech.current_stage(_late_tech)
	var def: Dictionary = late_tech.stage_def(stage_key)
	var careers: Array = []
	for key in late_tech.CAREERS.keys():
		var cd: Dictionary = late_tech.CAREERS[key]
		careers.append({
			"id": String(key), "name": String(cd.get("name", key)),
			"stage": String(cd.get("stage", "")),
			"unlocked": late_tech.career_unlocked(_late_tech, String(key)),
			"min_level": int(cd.get("min_level", 0)),
			"salary": int(cd.get("salary", 0)),
		})
	var missions: Array = []
	for key in late_tech.MISSIONS.keys():
		var md: Dictionary = late_tech.MISSIONS[key]
		missions.append({
			"id": String(key), "name": String(md.get("name", key)),
			"stage": String(md.get("stage", "")),
			"min_skill": int(md.get("min_skill", 0)),
			"reward": int(md.get("reward", 0)),
		})
	return {
		"stage": stage_key,
		"stage_name": String(def.get("name", stage_key)),
		"stage_index": int(_late_tech.get("stage_index", 0)),
		"unlocked_stages": (_late_tech.get("unlocked_stages", []) as Array).duplicate(),
		"jobs": (def.get("jobs", []) as Array).duplicate(),
		"equipment": (def.get("equipment", []) as Array).duplicate(),
		"places": (def.get("places", []) as Array).duplicate(),
		"lifespan_bonus": snappedf(float(_late_tech.get("lifespan_bonus", 0.0)), 0.1),
		"unemployment_rate": snappedf(float(_late_tech.get("unemployment_rate", 0.0)), 0.001),
		"careers": careers,
		"missions": missions,
		"last_report": (_late_tech.get("last_report", {}) as Dictionary).duplicate(true),
	}

func _persist_late_tech() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["late_tech"] = late_tech.to_dict(_late_tech)


# --- 知识产权与媒体（D25） ---

func ip_media_state() -> Dictionary:
	return {"ips": _ips, "outlets": _outlets}

func ip_types_catalog() -> Array:
	var out: Array = []
	for key in ip_media.IP_TYPES.keys():
		var d: Dictionary = ip_media.IP_TYPES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func media_types_catalog() -> Array:
	var out: Array = []
	for key in ip_media.MEDIA_TYPES.keys():
		var d: Dictionary = ip_media.MEDIA_TYPES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

## 登记知识产权：扣缴登记费，登记后入档。title 缺省用类型名。
func register_ip_asset(ip_type: String, title: String = "") -> Dictionary:
	if not ip_media.IP_TYPES.has(ip_type):
		return {"ok": false, "reason": "unknown_ip_type"}
	var def: Dictionary = ip_media.IP_TYPES[ip_type]
	var fee: int = int(def.get("registration_fee", 0))
	if int(economy.cash(account_id())) < fee:
		return {"ok": false, "reason": "insufficient_funds"}
	var name: String = title
	if name.strip_edges() == "":
		name = "%s%d" % [String(def.get("name", ip_type)), _ips.size() + 1]
	var r: Dictionary = ip_media.register_ip(ip_type, "player", name, {"created_minute": now_minutes()})
	if bool(r.get("ok", false)):
		_ips.append(r["ip"])
		economy.add_money(account_id(), -fee, "ip_registration")
		_persist_ip_media()
	return {"ok": true, "ip": r.get("ip", {}), "fee": fee}

## 授权知识产权：许可费入账。
## IP 收益归属：个人 IP 进玩家现金，职务发明进公司账户。
func _ip_owner_account(ip: Dictionary) -> String:
	var owner: String = String(ip.get("owner", "player"))
	if owner.begins_with("company:"):
		return "company." + owner.trim_prefix("company:")
	return account_id()

func license_ip_asset(ip_id: String, deal_size: float, exclusive: bool = false) -> Dictionary:
	var ip: Dictionary = _find_ip(ip_id)
	if ip.is_empty():
		return {"ok": false, "reason": "unknown_ip"}
	var r: Dictionary = ip_media.license_ip(ip, "外部被许可方", deal_size, {"exclusive": exclusive, "minute": now_minutes()})
	if bool(r.get("ok", false)):
		economy.add_money(_ip_owner_account(ip), int(r.get("fee", 0)), "ip_license")
		_persist_ip_media()
	return r

## 职务发明：以公司名义登记 IP，登记费从公司账户扣除，收益归公司。
func company_file_ip(ip_type: String, title: String = "") -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	if not ip_media.IP_TYPES.has(ip_type):
		return {"ok": false, "reason": "unknown_ip_type"}
	var def: Dictionary = ip_media.IP_TYPES[ip_type]
	var fee: int = int(def.get("registration_fee", 0))
	var account: String = String(_company.get("account", ""))
	if account == "" or int(economy.cash(account)) < fee:
		return {"ok": false, "reason": "insufficient_funds"}
	var name: String = title
	if name.strip_edges() == "":
		name = "%s%d" % [String(def.get("name", ip_type)), _ips.size() + 1]
	var owner: String = "company:" + String(_company.get("id", ""))
	var r: Dictionary = ip_media.register_ip(ip_type, owner, name, {"created_minute": now_minutes()})
	if not bool(r.get("ok", false)):
		return r
	var ip: Dictionary = r["ip"]
	_ips.append(ip)
	economy.add_money(account, -fee, "company_ip_registration")
	var assets: Array = _company.get("ip_assets", [])
	assets.append({"id": String(ip.get("id", "")), "type": ip_type, "title": name})
	_company["ip_assets"] = assets
	_persist_ip_media()
	_persist_company()
	return {"ok": true, "ip": ip, "fee": fee, "owner": owner}

## 转让知识产权：成交价入账并变更所有权。
func transfer_ip_asset(ip_id: String, price: int) -> Dictionary:
	var ip: Dictionary = _find_ip(ip_id)
	if ip.is_empty():
		return {"ok": false, "reason": "unknown_ip"}
	var payee: String = _ip_owner_account(ip)
	var r: Dictionary = ip_media.transfer_ip(ip, "外部买家", price)
	economy.add_money(payee, int(r.get("price", 0)), "ip_transfer")
	_persist_ip_media()
	return r

## 质押知识产权：融资额入账。
func pledge_ip_asset(ip_id: String, amount: int) -> Dictionary:
	var ip: Dictionary = _find_ip(ip_id)
	if ip.is_empty():
		return {"ok": false, "reason": "unknown_ip"}
	var payee: String = _ip_owner_account(ip)
	var r: Dictionary = ip_media.pledge_ip(ip, amount)
	if bool(r.get("ok", false)):
		economy.add_money(payee, int(r.get("amount", 0)), "ip_pledge")
		_persist_ip_media()
	return r

## 知识产权维权诉讼：胜诉赔偿入账。
func sue_ip_infringer(ip_id: String, opts: Dictionary = {}) -> Dictionary:
	var ip: Dictionary = _find_ip(ip_id)
	if ip.is_empty():
		return {"ok": false, "reason": "unknown_ip"}
	var payee: String = _ip_owner_account(ip)
	var r: Dictionary = ip_media.file_lawsuit(ip, opts)
	if bool(r.get("win", false)) and int(r.get("compensation", 0)) > 0:
		economy.add_money(payee, int(r["compensation"]), "ip_compensation")
	_persist_ip_media()
	return r

## 平台内容审核：按风险与版权标记判定放行/驳回/下架，媒体机构声誉随违规内容下降。
func audit_media_content(content: String, risk: float = 0.3, copyright_infringement: bool = false, strictness: float = 0.5) -> Dictionary:
	var title: String = content.strip_edges()
	if title == "":
		title = "待审内容"
	var r: Dictionary = ip_media.moderate_content(title, {
		"risk": clampf(risk, 0.0, 1.0),
		"policy_strictness": clampf(strictness, 0.0, 1.0),
		"copyright_infringement": copyright_infringement,
	})
	if not bool(r.get("approved", false)) and not _outlets.is_empty():
		var outlet: Dictionary = _outlets[_outlets.size() - 1]
		outlet["reputation"] = clampf(float(outlet.get("reputation", 0.5)) - 0.02, 0.0, 1.0)
		_persist_ip_media()
	return r

## 开办媒体机构。
func register_media_outlet(media_type: String, name: String = "") -> Dictionary:
	if not ip_media.MEDIA_TYPES.has(media_type):
		return {"ok": false, "reason": "unknown_media_type"}
	var opts: Dictionary = {"reputation": 0.5, "cash": 0}
	if name.strip_edges() != "":
		opts["name"] = name
	var r: Dictionary = ip_media.new_media_outlet(media_type, opts)
	if bool(r.get("ok", false)):
		_outlets.append(r["outlet"])
		_persist_ip_media()
	return r

## 发行作品：票房/销量入账并影响机构声誉。
func release_media_work(outlet_id: String, title: String, quality: float = 0.5, scale: float = 10000000.0) -> Dictionary:
	var outlet: Dictionary = _find_outlet(outlet_id)
	if outlet.is_empty():
		return {"ok": false, "reason": "unknown_outlet"}
	var work: Dictionary = {"title": title, "quality": clampf(quality, 0.0, 1.0)}
	var r: Dictionary = ip_media.release_work(outlet, work, {"scale": scale})
	if bool(r.get("ok", false)) and int(r.get("revenue", 0)) > 0:
		economy.add_money(account_id(), int(r["revenue"]), "media_revenue")
		_persist_ip_media()
	return r

func _find_ip(ip_id: String) -> Dictionary:
	for ip in _ips:
		if ip is Dictionary and String((ip as Dictionary).get("id", "")) == ip_id:
			return ip
	return {}

func _find_outlet(outlet_id: String) -> Dictionary:
	for o in _outlets:
		if o is Dictionary and String((o as Dictionary).get("id", "")) == outlet_id:
			return o
	return {}

func ip_media_panel_data() -> Dictionary:
	var ips: Array = []
	for ip in _ips:
		if ip is Dictionary:
			var d: Dictionary = ip
			ips.append({
				"id": String(d.get("id", "")),
				"type": String(d.get("type", "")),
				"type_name": String(ip_media.IP_TYPES.get(String(d.get("type", "")), {}).get("name", d.get("type", ""))),
				"title": String(d.get("title", "")),
				"owner": String(d.get("owner", "player")),
				"company_owned": String(d.get("owner", "")).begins_with("company:"),
				"status": String(d.get("status", "")),
				"licenses": (d.get("licenses", []) as Array).size(),
				"pledged": bool(d.get("pledged", false)),
				"public_domain": bool(d.get("public_domain", false)),
			})
	var outlets: Array = []
	for o in _outlets:
		if o is Dictionary:
			var od: Dictionary = o
			outlets.append({
				"id": String(od.get("id", "")),
				"name": String(od.get("name", "")),
				"type_name": String(ip_media.MEDIA_TYPES.get(String(od.get("type", "")), {}).get("name", od.get("type", ""))),
				"reputation": snappedf(float(od.get("reputation", 0.0)), 0.001),
				"cash": int(od.get("cash", 0)),
				"works": (od.get("works", []) as Array).size(),
			})
	return {"ips": ips, "outlets": outlets}

func _persist_ip_media() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["ip_media"] = {
		"ips": _ips.duplicate(true),
		"outlets": _outlets.duplicate(true),
	}


# --- 制造业与供应链（D26） ---

func manufacturing_state() -> Dictionary:
	return _factory

func mfg_roles_catalog() -> Array:
	var out: Array = []
	for key in manufacturing.ROLES.keys():
		var d: Dictionary = manufacturing.ROLES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mfg_modes_catalog() -> Array:
	var out: Array = []
	for key in manufacturing.MODES.keys():
		var d: Dictionary = manufacturing.MODES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mfg_recipes_catalog() -> Array:
	var out: Array = []
	for key in manufacturing.RECIPES.keys():
		var d: Dictionary = manufacturing.RECIPES[key]
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mfg_materials_catalog() -> Array:
	const MATERIAL_NAMES: Dictionary = {"steel": "钢材", "resin": "树脂", "copper": "铜材", "rice": "米面", "meat": "肉类", "vegetable": "蔬菜", "spice": "调味"}
	var seen: Dictionary = {}
	var out: Array = []
	for key in manufacturing.RECIPES.keys():
		for mat in manufacturing.input_materials(String(key)):
			var m := String(mat)
			if seen.has(m):
				continue
			seen[m] = true
			out.append({"id": m, "name": String(MATERIAL_NAMES.get(m, m))})
	return out

## 开办工厂：授予所选经营模式资质并注入初始营运资金（工厂为独立资金池）。
func found_factory(mode: String = "own_factory") -> Dictionary:
	if not manufacturing.MODES.has(mode):
		return {"ok": false, "reason": "unknown_mfg_mode"}
	_factory = manufacturing.new_factory(10000000, {"mode": "own_factory"})
	manufacturing.grant_qualification(_factory, String((manufacturing.MODES[mode] as Dictionary)["qualification"]))
	var setr: Dictionary = manufacturing.set_mode(_factory, mode)
	if not bool(setr.get("ok", false)):
		# 资金/资质不足时回落到开厂模式。
		manufacturing.grant_qualification(_factory, "factory_license")
		manufacturing.set_mode(_factory, "own_factory")
	_persist_manufacturing()
	return {"ok": true, "mode": String(_factory.get("mode", "own_factory"))}

func mfg_hire(role: String, count: int) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.hire(_factory, role, count)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

func mfg_fire(role: String, count: int) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.fire(_factory, role, count)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

## 添加覆盖某原料的供应商。
func mfg_add_supplier(material: String) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.add_supplier(_factory, {
		"name": "%s 供应商" % material, "materials": [material], "reliability": 0.9, "price_factor": 1.0,
	})
	_persist_manufacturing()
	return r

func mfg_purchase(material: String, qty: float) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	# 首次采购该原料时惰性建立供应商，保证「采购原料」开箱可用。
	var covered: bool = false
	for s in (_factory.get("suppliers", []) as Array):
		if (s as Dictionary).get("materials", []).has(material):
			covered = true
			break
	if not covered:
		mfg_add_supplier(material)
	var r: Dictionary = manufacturing.purchase(_factory, material, qty, {"base_unit_cost": 1000})
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

func mfg_produce(recipe_key: String, batches: float = 1.0) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.produce(_factory, recipe_key, batches)
	if bool(r.get("ok", false)):
		# 生产碳排进入企业碳账户，随产量按单位系数累计。
		var good: float = float(r.get("good_output", 0.0))
		if good > 0.0 and not _env_enterprise.is_empty():
			var emitted: float = good * BaselineScript.MFG_EMISSION_PER_UNIT
			_env_enterprise["emissions"] = float(_env_enterprise.get("emissions", 0.0)) + emitted
			r["emissions"] = emitted
			r["carbon_balance"] = environment_sys.carbon_balance(_env_enterprise)
			_persist_environment()
		_persist_manufacturing()
	return r


## 工厂成品出口：扣成品库存，按吨位与货值建立外贸单据。
func mfg_export(recipe_key: String, quantity: float, destination: String = "") -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var def: Dictionary = manufacturing.recipe_def(recipe_key)
	if def.is_empty():
		return {"ok": false, "reason": "unknown_recipe"}
	var qty: float = maxf(0.0, quantity)
	if qty <= 0.0:
		return {"ok": false, "reason": "bad_quantity"}
	var have: float = manufacturing.product_qty(_factory, recipe_key)
	if have < qty:
		return {"ok": false, "reason": "insufficient_stock", "available": snappedf(have, 0.1)}
	var margin: float = 1.0 + float((manufacturing.MODES.get(String(_factory.get("mode", "")), {}) as Dictionary).get("brand_margin", 0.0))
	var goods_value: int = int(round(qty * float(def.get("price", 0)) * margin))
	var tons: float = qty * BaselineScript.MFG_TONS_PER_UNIT
	var s: Dictionary = trade.new_shipment({
		"id": "shipment_%d" % _shipments.size(),
		"goods_value": maxi(0, goods_value),
		"quantity_ton": maxf(0.01, tons),
		"origin": current_region_id(),
		"destination": destination,
	})
	s["goods"] = String(def.get("name", recipe_key))
	s["recipe"] = recipe_key
	s["quantity"] = qty
	(_factory["products"] as Dictionary)[recipe_key] = have - qty
	_shipments.append(s)
	_persist_manufacturing()
	_persist_trade()
	return {
		"ok": true, "index": _shipments.size() - 1, "goods": String(s["goods"]),
		"goods_value": goods_value, "quantity": qty, "quantity_ton": float(s["quantity_ton"]),
	}

## 接单：价取配方基准价。
func mfg_accept_order(recipe_key: String, quantity: float) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var def: Dictionary = manufacturing.recipe_def(recipe_key)
	if def.is_empty():
		return {"ok": false, "reason": "unknown_recipe"}
	var r: Dictionary = manufacturing.accept_order(_factory, recipe_key, quantity, int(def.get("price", 0)))
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

func mfg_deliver_order(index: int = 0) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.deliver_order(_factory, index)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	return r

## 切换/升级经营模式。
func mfg_set_mode(mode: String) -> Dictionary:
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	var r: Dictionary = manufacturing.upgrade_mode(_factory, mode)
	if not bool(r.get("ok", false)):
		r = manufacturing.set_mode(_factory, mode)
	if bool(r.get("ok", false)):
		_persist_manufacturing()
	elif String(r.get("reason", "")) == "unknown_mode":
		r["reason"] = "unknown_mfg_mode"
	return r

## 制造业面板数据：模式/产能/人员/原料/成品/订单/风险。
func factory_panel_data() -> Dictionary:
	if _factory.is_empty():
		return {}
	var staff: Array = []
	for key in manufacturing.ROLES.keys():
		var n: int = manufacturing.staff_count(_factory, String(key))
		if n > 0:
			staff.append({"id": String(key), "name": String((manufacturing.ROLES[key] as Dictionary).get("name", key)), "count": n})
	var materials: Array = []
	var max_factory := _factory
	for mat in (max_factory.get("materials", {}) as Dictionary).keys():
		var entry: Dictionary = (max_factory["materials"] as Dictionary)[mat]
		if float(entry.get("qty", 0.0)) > 0.0:
			materials.append({"id": String(mat), "qty": snappedf(float(entry.get("qty", 0.0)), 0.1)})
	var products: Array = []
	for rkey in (max_factory.get("products", {}) as Dictionary).keys():
		var qty: float = float((max_factory["products"] as Dictionary)[rkey])
		if qty > 0.0:
			products.append({"id": String(rkey), "name": String(manufacturing.recipe_def(String(rkey)).get("name", rkey)), "qty": snappedf(qty, 0.1)})
	var orders: Array = []
	var idx: int = 0
	for o in (max_factory.get("orders", []) as Array):
		if o is Dictionary:
			var od: Dictionary = o
			orders.append({
				"index": idx, "name": String(manufacturing.recipe_def(String(od.get("recipe", ""))).get("name", od.get("recipe", ""))),
				"quantity": snappedf(float(od.get("quantity", 0.0)), 0.1),
				"delivered": snappedf(float(od.get("delivered", 0.0)), 0.1),
				"fulfilled": bool(od.get("fulfilled", false)),
			})
			idx += 1
	var cap: Dictionary = {}
	var recipe_keys: Array = manufacturing.recipe_keys()
	if not recipe_keys.is_empty():
		cap = manufacturing.capacity(_factory, String(recipe_keys[0]))
	return {
		"money": int(max_factory.get("money", 0)),
		"mode": String(max_factory.get("mode", "")),
		"mode_name": String(manufacturing.MODES.get(String(max_factory.get("mode", "")), {}).get("name", max_factory.get("mode", ""))),
		"headcount": manufacturing.headcount(_factory),
		"labor_factor": snappedf(manufacturing.labor_factor(_factory), 0.01),
		"efficiency": snappedf(manufacturing.effective_efficiency(_factory), 0.01),
		"bottleneck": String(cap.get("bottleneck", "")),
		"effective_capacity": snappedf(float(cap.get("effective_capacity", 0.0)), 0.1),
		"safety": snappedf(float(max_factory.get("safety", 0.0)), 0.01),
		"automation": snappedf(float(max_factory.get("automation", 0.0)), 0.01),
		"active_disruptions": manufacturing.active_disruptions(_factory),
		"staff": staff,
		"materials": materials,
		"products": products,
		"orders": orders,
	}

func _persist_manufacturing() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["manufacturing"] = manufacturing.to_dict(_factory)


# --- 国际贸易、海关与物流（D27） ---

func trade_state() -> Dictionary:
	return {"shipments": _shipments}

func trade_transport_modes_catalog() -> Array:
	var out: Array = []
	for key in trade.TRANSPORT_MODES.keys():
		out.append({"id": String(key), "name": String((trade.TRANSPORT_MODES[key] as Dictionary).get("name", key))})
	return out

func trade_incoterms_catalog() -> Array:
	var out: Array = []
	for code in trade.INCOTERMS:
		out.append({"id": String(code), "name": String(code)})
	return out

func trade_settlements_catalog() -> Array:
	var out: Array = []
	for key in trade.SETTLEMENTS.keys():
		out.append({"id": String(key), "name": String((trade.SETTLEMENTS[key] as Dictionary).get("name", key))})
	return out

func trade_services_catalog() -> Array:
	const NAMES: Dictionary = {"freight_forwarder": "货代", "customs_broker": "报关行", "overseas_warehouse": "海外仓", "cross_border_ecommerce": "跨境电商"}
	var out: Array = []
	for key in trade.SERVICES:
		out.append({"id": String(key), "name": String(NAMES.get(String(key), key))})
	return out

func trade_barriers_catalog() -> Array:
	const NAMES: Dictionary = {"tariff": "加征关税", "quota": "配额", "anti_dumping": "反倾销", "origin": "原产地"}
	var out: Array = []
	for key in trade.BARRIERS:
		out.append({"id": String(key), "name": String(NAMES.get(String(key), key))})
	return out

func trade_risk_events_catalog() -> Array:
	const NAMES: Dictionary = {"trade_war": "贸易战", "sanction": "制裁", "war": "战争"}
	var out: Array = []
	for key in trade.RISK_EVENTS:
		out.append({"id": String(key), "name": String(NAMES.get(String(key), key))})
	return out

## 新建出口单据：以货值建单，商品名落单据，返回序号。
func export_shipment(goods: String, value: int) -> Dictionary:
	var s: Dictionary = trade.new_shipment({"id": "shipment_%d" % _shipments.size(), "goods_value": maxi(0, value)})
	s["goods"] = goods if goods != "" else "货物"
	_shipments.append(s)
	_persist_trade()
	return {"ok": true, "index": _shipments.size() - 1, "goods": String(s["goods"]), "goods_value": int(s["goods_value"])}

## 规划运输：报价并写入单据运费（海运/空运/铁路/快递/管道，超载拒绝）。
func plan_trade_transport(index: int, mode: String) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var quote: Dictionary = trade.estimate_freight(mode, float(s.get("quantity_ton", 1.0)))
	if not bool(quote.get("ok", false)):
		return {"ok": false, "reason": String(quote.get("reason", "over_capacity"))}
	s["transport"] = mode
	s["freight"] = int(quote.get("freight", 0))
	s["transit_days"] = float(quote.get("days", 0.0))
	_persist_trade()
	return {"ok": true, "mode": mode, "freight": int(s["freight"]), "days": float(s["transit_days"])}

## 签订外贸合同：写入贸易术语与结算方式，进入签约阶段。
func sign_trade_contract(index: int, incoterm: String, settlement: String = "letter_of_credit") -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	if not trade.INCOTERMS.has(incoterm):
		return {"ok": false, "reason": "unknown_incoterm"}
	if not trade.SETTLEMENTS.has(settlement):
		settlement = "letter_of_credit"
	s["incoterm"] = incoterm
	s["settlement"] = settlement
	s["stage"] = "contract"
	(s["history"] as Array).append("contract")
	_persist_trade()
	return {"ok": true, "incoterm": incoterm, "settlement": settlement, "settlement_name": String((trade.SETTLEMENTS[settlement] as Dictionary).get("name", settlement))}

## 报关并落税：关税+增值税从玩家现金扣除，进入报关阶段。
func declare_shipment(index: int) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var duties: Dictionary = trade.declare_customs(s)
	var tax: int = int(duties.get("total_tax", 0))
	if economy.cash(account_id()) < tax:
		return {"ok": false, "reason": "insufficient_funds", "total_tax": tax}
	economy.add_money(account_id(), -tax, "customs_tax")
	_persist_trade()
	return {"ok": true, "tariff": int(duties.get("tariff", 0)), "vat": int(duties.get("vat", 0)), "total_tax": tax, "landed_cost": int(duties.get("landed_cost", 0))}

## 清关：进入清关阶段。
func clear_shipment(index: int) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.clear_customs(s)
	_persist_trade()
	return r

## 发货交付：货值作为出口收入入账并进入交付阶段。
func deliver_shipment(index: int) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.deliver(s)
	var revenue: int = maxi(0, int(s.get("goods_value", 0)))
	economy.add_money(account_id(), revenue, "export_revenue")
	_persist_trade()
	return {"ok": true, "revenue": revenue, "stage": String(r.get("stage", "delivery"))}

## 结汇：按结算方式计手续费，从玩家现金扣除并标记已结汇。
func settle_shipment(index: int) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var method: String = String(s.get("settlement", "letter_of_credit"))
	if method == "":
		method = "letter_of_credit"
	var fee_r: Dictionary = trade.settlement_fee(int(s.get("goods_value", 0)), method)
	var fee: int = int(fee_r.get("fee", 0))
	if economy.cash(account_id()) < fee:
		return {"ok": false, "reason": "insufficient_funds", "fee": fee}
	economy.add_money(account_id(), -fee, "settlement_fee")
	s["settled"] = true
	_persist_trade()
	return {"ok": true, "fee": fee, "method": method, "method_name": String((trade.SETTLEMENTS[method] as Dictionary).get("name", method))}

## 施加贸易壁垒：关税/配额/反倾销/原产地规则写入单据。
func apply_trade_barrier(index: int, barrier: String) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.apply_barrier(s, barrier)
	if bool(r.get("ok", false)):
		_persist_trade()
	return r

## 触发外贸风险事件：写入滞留/改道/额外费用，并从现金扣除。
func apply_trade_risk(index: int, event: String) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.risk_event(s, event)
	if not bool(r.get("ok", false)):
		return r
	var extra: int = maxi(0, int(r.get("extra_cost", 0)))
	if extra > 0:
		if int(economy.cash(account_id())) < extra:
			return {"ok": false, "reason": "insufficient_funds", "extra_cost": extra}
		economy.add_money(account_id(), -extra, "trade_risk:%s" % event)
	s["delay_days"] = float(s.get("delay_days", 0.0)) + float(r.get("delay_days", 0.0))
	s["extra_cost"] = int(s.get("extra_cost", 0)) + extra
	_persist_trade()
	return r

## 检验检疫：默认合格，不合格时标记可退运/整改。
func inspect_shipment(index: int, passed: bool = true) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.quarantine_inspect(s, {"passed": passed})
	_persist_trade()
	return r

## 货损：按比例折减货值。
func damage_shipment(index: int, loss_rate: float) -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.damage_loss(s, clampf(loss_rate, 0.0, 1.0))
	_persist_trade()
	return r

## 退运：标记退运并按运费计退运成本。
func return_shipment(index: int, reason: String = "rejected") -> Dictionary:
	var s: Dictionary = _shipment_at(index)
	if s.is_empty():
		return {"ok": false, "reason": "no_shipment"}
	var r: Dictionary = trade.return_shipment(s, reason)
	var cost: int = maxi(0, int(r.get("return_cost", 0)))
	if cost > 0 and int(economy.cash(account_id())) >= cost:
		economy.add_money(account_id(), -cost, "trade_return")
	_persist_trade()
	return r

## 外贸面板数据：单据、阶段、运输、税费、结算。
func trade_panel_data() -> Dictionary:
	if _shipments.is_empty():
		return {}
	var rows: Array = []
	var idx: int = 0
	for s in _shipments:
		var sd: Dictionary = s
		var stage: String = String(sd.get("stage", "inquiry"))
		rows.append({
			"index": idx,
			"goods": String(sd.get("goods", "货物")),
			"goods_value": int(sd.get("goods_value", 0)),
			"stage": stage,
			"stage_name": String(trade.STAGE_NAMES.get(stage, stage)),
			"incoterm": String(sd.get("incoterm", "")),
			"transport": String(sd.get("transport", "")),
			"freight": int(sd.get("freight", 0)),
			"settled": bool(sd.get("settled", false)),
			"barriers": (sd.get("barriers", []) as Array).duplicate(),
			"risk_events": (sd.get("risk_events", []) as Array).duplicate(),
			"delay_days": float(sd.get("delay_days", 0.0)),
			"extra_cost": int(sd.get("extra_cost", 0)),
			"inspection_passed": bool(sd.get("inspection_passed", true)),
			"returned": bool(sd.get("returned", false)),
		})
		idx += 1
	return {"shipments": rows}

func _shipment_at(index: int) -> Dictionary:
	var i: int = index
	if i < 0:
		i = _shipments.size() - 1
	if i < 0 or i >= _shipments.size():
		return {}
	return _shipments[i]

func _persist_trade() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["trade"] = {"shipments": _shipments.duplicate(true)}


# --- D28 矿业、能源与资源 ---

func mining_state() -> Dictionary:
	return {"mine": _mine, "energy": _energy}

func mining_minerals_catalog() -> Array:
	var out: Array = []
	for key in mining_energy.mineral_keys():
		var d: Dictionary = mining_energy.mineral_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mining_energy_catalog() -> Array:
	var out: Array = []
	for key in mining_energy.energy_keys():
		var d: Dictionary = mining_energy.energy_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func mining_energy_types_catalog() -> Array:
	var out: Array = []
	for key in mining_energy.energy_keys():
		out.append({"id": String(key), "name": String((mining_energy.ENERGY_TYPES[key] as Dictionary).get("name", key))})
	return out

func mining_energy_kinds_catalog() -> Array:
	var out: Array = []
	for key in mining_energy.NEW_ENERGY_KINDS:
		out.append({"id": String(key), "name": String(mining_energy.NEW_ENERGY_NAMES.get(String(key), key))})
	return out

## 开办矿场：独立资金池，预置矿权资质（仍需另行取得矿权）。
func open_mine(mineral: String, capital: int = 100000000) -> Dictionary:
	var m: Dictionary = mining_energy.new_mine(mineral, maxi(0, capital), {"qualifications": [mining_energy.CONCESSION_QUALIFICATION]})
	if m.is_empty():
		return {"ok": false, "reason": "unknown_mineral"}
	_mine = m
	_persist_mining()
	return {"ok": true, "mineral": mineral, "name": String((mining_energy.MINERALS[mineral] as Dictionary).get("name", mineral))}

## 取得矿权（特许经营），需资质与最低资本。
func acquire_mine_concession() -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.acquire_concession(_mine)
	_persist_mining()
	return r

## 勘探矿场：投入预算揭示储量与品位。
func explore_mine(budget: int) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.explore(_mine, maxi(0, budget))
	_persist_mining()
	return r

## 开采矿石：产出自动转运至冶炼环节。
func extract_ore(amount: float) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.extract(_mine, maxf(0.0, amount))
	if bool(r.get("ok", false)):
		mining_energy.transport_ore(_mine, float(r.get("ore", 0.0)))
	_persist_mining()
	return r

## 冶炼金属。
func smelt_ore(amount: float) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.smelt(_mine, maxf(0.0, amount))
	_persist_mining()
	return r

## 出售精炼金属，收入进矿场资金池。
func sell_metal(amount: float) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.sell(_mine, maxf(0.0, amount))
	_persist_mining()
	return r

## 新能源项目：风电/光伏/核电/储能。
func build_energy_project(kind: String, capacity: float) -> Dictionary:
	var p: Dictionary = mining_energy.new_energy_project(kind, maxf(0.0, capacity))
	if p.is_empty():
		return {"ok": false, "reason": "unknown_energy_kind"}
	var projects: Array = _energy.get("projects", [])
	projects.append(p)
	_energy["projects"] = projects
	_persist_mining()
	return {"ok": true, "kind": kind, "name": String(p.get("name", kind)), "capacity": float(p.get("capacity", 0.0))}

## 安全投入：从矿场资金池扣款，降低事故率。
func invest_mine_safety(amount: int) -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var spend: int = maxi(0, amount)
	if int(_mine.get("money", 0)) < spend:
		return {"ok": false, "reason": "insufficient_funds", "required": spend}
	_mine["money"] = int(_mine.get("money", 0)) - spend
	var r: Dictionary = mining_energy.safety_invest(_mine, spend)
	_persist_mining()
	return r

## 矿难判定：按安全水平掷骰，事故造成罚款、健康损伤与环保负债。
func check_mine_accident() -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var r: Dictionary = mining_energy.accident_check(_mine, {}, rng)
	if bool(r.get("occurred", false)):
		var fine: int = mini(int(_mine.get("money", 0)), 2000000)
		_mine["money"] = int(_mine.get("money", 0)) - fine
		_mine["environment_liability"] = clampf(float(_mine.get("environment_liability", 0.0)) + 0.1, 0.0, 1.0)
		var injured: int = int(r.get("injured", 0))
		_damage_health(clampf(float(injured) * 0.05, 0.0, 5.0))
		r["fine"] = fine
		if injured >= 3:
			crime_sys.add_record(_crime_state, "major_accident", current_region_id(), now_minutes(), 0.9)
			crime_sys.add_wanted(_crime_state, "major_accident", current_region_id(), 2)
			_sync_legal()
			r["criminal_record"] = true
		_mine["last_accident"] = r.duplicate(true)
	_persist_mining()
	return r

## 能源期货：锁定未来价格，到期按市价与锁价差额结算。
func buy_energy_futures(energy_type: String, amount: float = 100.0, lock_price: int = 0) -> Dictionary:
	var price: int = lock_price if lock_price > 0 else mining_energy.energy_price(_energy, energy_type)
	var r: Dictionary = mining_energy.futures_contract(_energy, energy_type, maxf(0.0, amount), price)
	if bool(r.get("ok", false)):
		_persist_mining()
	return r

## 结算能源期货：index 为 -1 时取该品种首个未结算合约。
func settle_energy_futures(energy_type: String, index: int = -1) -> Dictionary:
	var contracts: Array = (_energy.get("futures", {}) as Dictionary).get(energy_type, []) if _energy.get("futures", {}) is Dictionary else []
	var idx: int = index
	if idx < 0:
		idx = -1
		for i in range(contracts.size()):
			if not bool((contracts[i] as Dictionary).get("settled", false)):
				idx = i
				break
	if idx < 0:
		return {"ok": false, "reason": "no_contract"}
	var market: int = mining_energy.energy_price(_energy, energy_type)
	var r: Dictionary = mining_energy.settle_futures(_energy, energy_type, idx, market)
	if bool(r.get("ok", false)):
		var pnl: int = int(r.get("pnl", 0))
		if not _mine.is_empty():
			_mine["money"] = int(_mine.get("money", 0)) + pnl
		_persist_mining()
	return r

## 能源长约：锁定固定价与年限，期间不受市价影响。
func sign_energy_contract(energy_type: String, amount: float = 1000.0, fixed_price: int = 0, years: float = 1.0) -> Dictionary:
	var price: int = fixed_price if fixed_price > 0 else mining_energy.energy_price(_energy, energy_type)
	var r: Dictionary = mining_energy.long_term_contract(_energy, energy_type, maxf(0.0, amount), price, maxf(0.0, years))
	if bool(r.get("ok", false)):
		_persist_mining()
	return r

## 资源城市衰退：扣减所在区域人口，并把衰退传导到宏观失业/GDP/PMI。
func mining_city_decline() -> Dictionary:
	if _mine.is_empty():
		return {"ok": false, "reason": "no_mine"}
	var rid: String = current_region_id()
	if rid == "" or regions == null or not regions.has_region(rid):
		return {"ok": false, "reason": "no_region"}
	var region = regions.get_region(rid)
	var city: Dictionary = {
		"population": int(region.population),
		"decline": float((region.snapshot as Dictionary).get("decline", 0.0)),
	}
	var r: Dictionary = mining_energy.resource_city_decline(city, _mine)
	region.population = int(city.get("population", region.population))
	(region.snapshot as Dictionary)["decline"] = float(city.get("decline", 0.0))
	region.economy = maxf(0.0, float(region.economy) - float(r.get("decline", 0.0)) * 0.2)
	var macro: Dictionary = mining_energy.apply_decline_to_macro(economy.macro, float(r.get("decline", 0.0)))
	_persist_regions()
	_persist_mining()
	return {"ok": true, "region_id": rid, "population": int(region.population),
		"decline": float(r.get("decline", 0.0)), "population_loss": int(r.get("population_loss", 0)),
		"macro": macro}

## 战略资源管制与囤积：写入能源运行态，管制越高可交易比例越低。
func mining_strategic_control(resource: String, level: float) -> Dictionary:
	if not mining_energy.ENERGY_TYPES.has(resource):
		return {"ok": false, "reason": "unknown_resource"}
	var r: Dictionary = mining_energy.set_strategic_control(_energy, resource, level)
	r["tradable_ratio"] = mining_energy.tradable_ratio(_energy, resource)
	_persist_mining()
	return r

func mining_stockpile(resource: String, amount: float) -> Dictionary:
	if not mining_energy.ENERGY_TYPES.has(resource):
		return {"ok": false, "reason": "unknown_resource"}
	var r: Dictionary = mining_energy.stockpile(_energy, resource, amount)
	r["tradable_ratio"] = mining_energy.tradable_ratio(_energy, resource)
	_persist_mining()
	return r

## 矿业/能源面板数据：矿场概况、能源价格、新能源项目。
func mining_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _mine.is_empty():
		var mineral: String = String(_mine.get("mineral", ""))
		out["mine"] = {
			"mineral": mineral,
			"mineral_name": String((mining_energy.MINERALS.get(mineral, {}) as Dictionary).get("name", mineral)),
			"concession": bool(_mine.get("concession", false)),
			"explored": bool(_mine.get("explored", false)),
			"reserve": float(_mine.get("reserve", 0.0)),
			"grade": float(_mine.get("grade", 0.0)),
			"workers": int(_mine.get("workers", 0)),
			"safety": float(_mine.get("safety", 0.5)),
			"stockpile_ore": float(_mine.get("stockpile_ore", 0.0)),
			"in_transit_ore": float(_mine.get("in_transit_ore", 0.0)),
			"refined_metal": float(_mine.get("refined_metal", 0.0)),
			"revenue": int(_mine.get("revenue", 0)),
			"money": int(_mine.get("money", 0)),
			"accident_count": int(_mine.get("accident_count", 0)),
			"occupational_disease": String((_mine.get("occupational_disease", {}) as Dictionary).get("name", "")),
		}
	var prices: Dictionary = _energy.get("prices", {})
	var price_rows: Array = []
	for key in mining_energy.energy_keys():
		price_rows.append({
			"key": String(key),
			"name": String((mining_energy.ENERGY_TYPES[key] as Dictionary).get("name", key)),
			"price": int(prices.get(key, 0)),
		})
	out["energy_prices"] = price_rows
	var projects: Array = []
	for p in _energy.get("projects", []):
		projects.append({"name": String(p.get("name", "")), "kind": String(p.get("kind", "")), "capacity": float(p.get("capacity", 0.0))})
	out["projects"] = projects
	out["strategic_control"] = (_energy.get("strategic_control", {}) as Dictionary).duplicate(true)
	out["strategic_stockpile"] = (_energy.get("stockpile", {}) as Dictionary).duplicate(true)
	var futures_rows: Array = []
	var futures: Dictionary = _energy.get("futures", {}) if _energy.get("futures", {}) is Dictionary else {}
	for key in futures.keys():
		var i: int = 0
		for c in (futures[key] as Array):
			futures_rows.append({
				"energy": String(key),
				"name": String((mining_energy.ENERGY_TYPES.get(String(key), {}) as Dictionary).get("name", key)),
				"index": i,
				"amount": float((c as Dictionary).get("amount", 0.0)),
				"lock_price": int((c as Dictionary).get("lock_price", 0)),
				"settled": bool((c as Dictionary).get("settled", false)),
			})
			i += 1
	out["futures"] = futures_rows
	var contracts_rows: Array = []
	for c in (_energy.get("long_term_contracts", []) as Array):
		contracts_rows.append({
			"energy": String((c as Dictionary).get("energy", "")),
			"name": String((mining_energy.ENERGY_TYPES.get(String((c as Dictionary).get("energy", "")), {}) as Dictionary).get("name", "")),
			"amount": float((c as Dictionary).get("amount", 0.0)),
			"fixed_price": int((c as Dictionary).get("fixed_price", 0)),
			"years": float((c as Dictionary).get("years", 0.0)),
		})
	out["contracts"] = contracts_rows
	out["last_accident"] = (_mine.get("last_accident", {}) as Dictionary).duplicate(true) if not _mine.is_empty() else {}
	return out

func _mining_tick(before_minutes: int, after_minutes: int) -> void:
	var years: float = float(maxi(0, after_minutes - before_minutes)) / 525960.0
	if years <= 0.0:
		return
	mining_energy.tick_energy(_energy, years)
	if not _mine.is_empty():
		var occ: Dictionary = mining_energy.occupational_disease_check(_mine, years, {}, rng)
		if bool(occ.get("occurred", false)):
			_damage_health(float(occ.get("health_penalty", 0.0)))
		elif not (_mine.get("occupational_disease", {}) as Dictionary).is_empty():
			_damage_health(float(mining_energy.OCCUPATIONAL_DISEASES["pneumoconiosis"].get("annual_health_loss", 2.0)) * years)
			_mine["occupational_disease"]["years"] = float((_mine["occupational_disease"] as Dictionary).get("years", 0.0)) + years
	_persist_mining()

func _persist_mining() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["mining"] = {"mine": _mine.duplicate(true), "energy": _energy.duplicate(true)}

## 工厂工资按月结算：资金不足则拖欠并触发罢工，补足后自动复工。
func _mfg_tick(before_minutes: int, after_minutes: int) -> void:
	if _factory.is_empty():
		return
	var outage_until: int = int(_factory.get("power_outage_until", 0))
	if outage_until > 0 and after_minutes >= outage_until:
		_factory["power_outage_until"] = 0
		manufacturing.set_disruption(_factory, "power_outage", false)
		_persist_manufacturing()
	var months: int = _month_ordinal(after_minutes) - _month_ordinal(before_minutes)
	if months <= 0:
		return
	var due: int = manufacturing.payroll_cost(_factory) * months
	if due <= 0:
		return
	if int(_factory.get("money", 0)) >= due:
		_factory["money"] = int(_factory.get("money", 0)) - due
		if bool(_factory.get("payroll_arrears", false)):
			_factory["payroll_arrears"] = false
			manufacturing.set_disruption(_factory, "strike", false)
	else:
		_factory["payroll_arrears"] = true
		manufacturing.set_disruption(_factory, "strike", true)
	_persist_manufacturing()

func _month_ordinal(minutes: int) -> int:
	var cal: Dictionary = GregorianScript.from_absolute_minutes(minutes)
	return int(cal.get("year", 2000)) * 12 + int(cal.get("month", 1))


# --- D29 农林牧渔深化 ---

func primary_state() -> Dictionary:
	return {"fishery": _fishery, "forest": _forest, "hunter": _hunter, "ecology": _ecology}

func fish_species_catalog() -> Array:
	var out: Array = []
	for key in primary_industry.FISH_SPECIES.keys():
		out.append({"id": String(key), "name": String((primary_industry.FISH_SPECIES[key] as Dictionary).get("name", key))})
	return out

func game_species_catalog() -> Array:
	var out: Array = []
	for key in primary_industry.GAME_SPECIES.keys():
		out.append({"id": String(key), "name": String((primary_industry.GAME_SPECIES[key] as Dictionary).get("name", key))})
	return out

func forest_types_catalog() -> Array:
	var out: Array = []
	for key in primary_industry.FOREST_TYPES.keys():
		out.append({"id": String(key), "name": String((primary_industry.FOREST_TYPES[key] as Dictionary).get("name", key))})
	return out

func new_fishery() -> Dictionary:
	if not _fishery.is_empty():
		return {"ok": false, "reason": "already_owns"}
	_fishery = primary_industry.new_fishery()
	_persist_primary()
	return {"ok": true, "boats": int(_fishery.get("boats", 0))}

func fish_catch(species: String, amount: float) -> Dictionary:
	if _fishery.is_empty():
		return {"ok": false, "reason": "no_fishery"}
	var r: Dictionary = primary_industry.catch_fish(_fishery, species, maxf(0.0, amount))
	_persist_primary()
	return r

func start_closed_season() -> Dictionary:
	if _fishery.is_empty():
		return {"ok": false, "reason": "no_fishery"}
	var r: Dictionary = primary_industry.start_closed_season(_fishery)
	_persist_primary()
	return r

func new_forest(ftype: String = "timber") -> Dictionary:
	if not _forest.is_empty():
		return {"ok": false, "reason": "already_owns"}
	if not primary_industry.FOREST_TYPES.has(ftype):
		ftype = "timber"
	_forest = primary_industry.new_forest(1000000, {"forest_type": ftype})
	primary_industry.grant_forest_rights(_forest)
	_persist_primary()
	return {"ok": true, "forest_type": ftype, "name": String((primary_industry.FOREST_TYPES[ftype] as Dictionary).get("name", ftype))}

func log_trees(amount: float) -> Dictionary:
	if _forest.is_empty():
		return {"ok": false, "reason": "no_forest"}
	var r: Dictionary = primary_industry.log_trees(_forest, maxf(0.0, amount))
	_persist_primary()
	return r

func reforest(amount: float) -> Dictionary:
	if _forest.is_empty():
		return {"ok": false, "reason": "no_forest"}
	var r: Dictionary = primary_industry.reforest(_forest, maxf(0.0, amount))
	_persist_primary()
	return r

## 林业碳汇：核证林分碳汇并售出，收益入玩家现金。
func forest_carbon_sink(years: float = 1.0, price: int = 100) -> Dictionary:
	if _forest.is_empty():
		return {"ok": false, "reason": "no_forest"}
	var before_money: int = int(_forest.get("money", 0))
	var r: Dictionary = primary_industry.carbon_sink(_forest, price, {"years": maxf(0.0, years)})
	var revenue: int = int(r.get("revenue", 0))
	_forest["money"] = before_money
	if revenue > 0:
		economy.add_money(account_id(), revenue, "forest_carbon")
	r["paid"] = revenue
	_persist_primary()
	return r

func apply_hunting_license() -> Dictionary:
	if _hunter.is_empty():
		_hunter = primary_industry.new_hunter()
	var r: Dictionary = primary_industry.hunting_license(_hunter)
	_persist_primary()
	return r

func hunt(species: String, amount: float) -> Dictionary:
	if _hunter.is_empty():
		_hunter = primary_industry.new_hunter()
	var r: Dictionary = primary_industry.hunt(_hunter, species, maxf(0.0, amount))
	_persist_primary()
	return r

## 农林牧渔面板数据：渔场/林场/狩猎/生态。
func primary_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _fishery.is_empty():
		out["fishery"] = {
			"boats": int(_fishery.get("boats", 0)),
			"resource_ratio": float(_fishery.get("resource_ratio", 1.0)),
			"closed_season": bool(_fishery.get("closed_season", false)),
			"closed_days_left": float(_fishery.get("closed_days_left", 0.0)),
			"overfish": float(_fishery.get("overfish", 0.0)),
		}
	if not _forest.is_empty():
		var ftype: String = String(_forest.get("forest_type", "timber"))
		out["forest"] = {
			"forest_type": ftype,
			"forest_type_name": String((primary_industry.FOREST_TYPES.get(ftype, {}) as Dictionary).get("name", ftype)),
			"area": float(_forest.get("area", 0.0)),
			"trees": float(_forest.get("trees", 0.0)),
			"wood": float(_forest.get("wood", 0.0)),
			"fire_risk": float(_forest.get("fire_risk", 0.0)),
		}
	if not _hunter.is_empty():
		out["hunter"] = {"license": bool(_hunter.get("license", false)), "wanted_level": int(_hunter.get("wanted_level", 0)), "money": int(_hunter.get("money", 0))}
	if not _ecology.is_empty():
		out["ecology"] = {"resource_ratio": float(_ecology.get("resource_ratio", 1.0)), "soil_quality": float(_ecology.get("soil_quality", 1.0)), "erosion": float(_ecology.get("erosion", 0.0))}
	return out

func _primary_tick(before_minutes: int, after_minutes: int) -> void:
	var days: float = float(maxi(0, after_minutes - before_minutes)) / 1440.0
	if days <= 0.0:
		return
	if not _fishery.is_empty():
		primary_industry.recover_resource(_fishery, days)
	if not _forest.is_empty():
		var growth: float = float((primary_industry.FOREST_TYPES.get(String(_forest.get("forest_type", "timber")), {}) as Dictionary).get("growth", 0.0))
		_forest["trees"] = float(_forest.get("trees", 0.0)) + float(_forest.get("area", 0.0)) * growth * days
	_persist_primary()

func _persist_primary() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["primary"] = {
		"fishery": _fishery.duplicate(true), "forest": _forest.duplicate(true),
		"hunter": _hunter.duplicate(true), "ecology": _ecology.duplicate(true),
	}


# --- D30 餐饮与食品工业 ---

func dining_state() -> Dictionary:
	return _restaurant.duplicate(true)

func dining_recipes_catalog() -> Array:
	var out: Array = []
	for key in dining.recipe_keys():
		out.append({"id": String(key), "name": String((dining.RECIPES[key] as Dictionary).get("name", key))})
	return out

func dining_channels_catalog() -> Array:
	var out: Array = []
	for key in dining.channel_keys():
		out.append({"id": String(key), "name": String((dining.CHANNELS[key] as Dictionary).get("name", key))})
	return out

func dining_staff_roles_catalog() -> Array:
	var out: Array = []
	for key in dining.staff_role_keys():
		out.append({"id": String(key), "name": String((dining.STAFF_ROLES[key] as Dictionary).get("name", key))})
	return out

func dining_modes_catalog() -> Array:
	var out: Array = []
	for key in dining.expansion_modes():
		out.append({"id": String(key), "name": String((dining.EXPANSION[key] as Dictionary).get("name", key))})
	return out

func dining_certs_catalog() -> Array:
	var out: Array = []
	for key in dining.certification_keys():
		out.append({"id": String(key), "name": String((dining.CERTIFICATIONS[key] as Dictionary).get("name", key))})
	return out

func dining_marketing_catalog() -> Array:
	var out: Array = []
	for key in dining.MARKETING.keys():
		out.append({"id": String(key), "name": String((dining.MARKETING[key] as Dictionary).get("name", key))})
	return out

func open_restaurant(money: int = 1000000) -> Dictionary:
	if not _restaurant.is_empty():
		return {"ok": false, "reason": "already_owns"}
	_restaurant = dining.new_restaurant(maxi(0, money))
	_persist_dining()
	return {"ok": true, "name": String(_restaurant.get("name", ""))}

func restaurant_add_menu(recipe: String) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.add_to_menu(_restaurant, recipe)
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_set_price(recipe: String, price: int) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.set_price(_restaurant, recipe, maxi(0, price))
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_sell_day(channel: String = "dine_in") -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.sell_day(_restaurant, {"channel": channel})
	_persist_dining()
	return r

func restaurant_hire(role: String, count: int) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.hire(_restaurant, role, maxi(0, count))
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_expand(mode: String) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.expand_to(_restaurant, mode)
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_certify(cert: String) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.certify(_restaurant, cert)
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_marketing(kind: String, cost: int) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.marketing_campaign(_restaurant, kind, maxi(0, cost))
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

func restaurant_process(recipe: String, qty: float) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.process_food(_restaurant, recipe, maxf(0.0, qty))
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

## 中央厨房产线供餐：把自有食品工厂的成品转入餐厅预包装库存。
func restaurant_industrial_supply(recipe: String, qty: float) -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	if _factory.is_empty():
		return {"ok": false, "reason": "no_factory"}
	if not (bool(_restaurant.get("central_kitchen", false)) or String(_restaurant.get("mode", "")) == "food_factory"):
		return {"ok": false, "reason": "no_food_facility"}
	if not dining.PACKAGED.has(recipe) or manufacturing.recipe_def(recipe).is_empty():
		return {"ok": false, "reason": "not_packageable"}
	var amount: float = maxf(0.0, qty)
	if amount <= 0.0:
		return {"ok": false, "reason": "bad_quantity"}
	var have: float = manufacturing.product_qty(_factory, recipe)
	var moved: float = minf(amount, have)
	if moved <= 0.0:
		return {"ok": false, "reason": "no_stock"}
	(_factory["products"] as Dictionary)[recipe] = have - moved
	var products: Dictionary = _restaurant.get("products", {})
	var entry: Dictionary = products.get(recipe, {"qty": 0.0})
	entry["qty"] = float(entry.get("qty", 0.0)) + moved
	products[recipe] = entry
	_restaurant["products"] = products
	_restaurant["industrial_supply"] = int(_restaurant.get("industrial_supply", 0)) + int(ceil(moved))
	_persist_manufacturing()
	_persist_dining()
	return {"ok": true, "recipe": recipe, "moved": moved, "factory_stock": have - moved, "restaurant_stock": float(entry["qty"])}

func restaurant_distribute(recipe: String, qty: float, channel: String = "retail") -> Dictionary:
	if _restaurant.is_empty():
		return {"ok": false, "reason": "no_restaurant"}
	var r: Dictionary = dining.distribute(_restaurant, recipe, maxf(0.0, qty), channel)
	if bool(r.get("ok", false)):
		_persist_dining()
	return r

## 餐饮面板数据：门店概况/菜单/员工/产品/认证。
func dining_panel_data() -> Dictionary:
	if _restaurant.is_empty():
		return {}
	var out: Dictionary = {
		"name": String(_restaurant.get("name", "")),
		"money": int(_restaurant.get("money", 0)),
		"mode": String(_restaurant.get("mode", "single_shop")),
		"mode_name": String((dining.EXPANSION.get(String(_restaurant.get("mode", "single_shop")), {}) as Dictionary).get("name", "")),
		"stores": int(_restaurant.get("stores", 1)),
		"reputation": float(_restaurant.get("reputation", 50.0)),
		"hygiene": float(_restaurant.get("hygiene", 70.0)),
		"brand": float(_restaurant.get("brand", 40.0)),
		"stars": dining.review_stars(_restaurant),
		"stars_name": dining.star_name(_restaurant),
		"headcount": dining.headcount(_restaurant),
		"turnover": dining.expected_turnover(_restaurant),
	}
	var menu_rows: Array = []
	for recipe in dining.menu_keys(_restaurant):
		var m: Dictionary = dining.recipe_margin(_restaurant, String(recipe))
		menu_rows.append({
			"key": String(recipe),
			"name": String((dining.RECIPES.get(String(recipe), {}) as Dictionary).get("name", recipe)),
			"price": int(m.get("price", 0)), "cost": int(m.get("cost", 0)),
			"margin": float(m.get("gross_margin", 0.0)),
		})
	out["menu"] = menu_rows
	var staff_rows: Array = []
	for role in dining.staff_role_keys():
		var n: int = dining.staff_count(_restaurant, String(role))
		if n > 0:
			staff_rows.append({"role": String(role), "name": String((dining.STAFF_ROLES[role] as Dictionary).get("name", role)), "count": n})
	out["staff"] = staff_rows
	var products: Array = []
	for k in (_restaurant.get("products", {}) as Dictionary).keys():
		var raw: Variant = (_restaurant["products"] as Dictionary)[k]
		var qty: float = float((raw as Dictionary).get("qty", 0.0)) if raw is Dictionary else float(raw)
		products.append({"key": String(k), "qty": qty})
	out["products"] = products
	out["industrial_supply"] = int(_restaurant.get("industrial_supply", 0))
	out["certifications"] = (_restaurant.get("certifications", []) as Array).duplicate()
	return out

func _persist_dining() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["dining"] = {"restaurant": dining.to_dict(_restaurant)}


# --- D31 时尚、设计与奢侈品 ---

func fashion_state() -> Dictionary:
	return {"brand": _brand, "trend": _trend}

func fashion_disciplines_catalog() -> Array:
	var out: Array = []
	for key in fashion.discipline_keys():
		out.append({"id": String(key), "name": String((fashion.DISCIPLINES[key] as Dictionary).get("name", key))})
	return out

func fashion_positionings_catalog() -> Array:
	var out: Array = []
	for key in fashion.positioning_keys():
		out.append({"id": String(key), "name": String((fashion.POSITIONING[key] as Dictionary).get("name", key))})
	return out

func fashion_luxury_catalog() -> Array:
	var out: Array = []
	for key in fashion.luxury_keys():
		out.append({"id": String(key), "name": String((fashion.LUXURY_ITEMS[key] as Dictionary).get("name", key))})
	return out

func fashion_marketing_catalog() -> Array:
	var out: Array = []
	for key in fashion.MARKETING.keys():
		out.append({"id": String(key), "name": String((fashion.MARKETING[key] as Dictionary).get("name", key))})
	return out

func fashion_seasons_catalog() -> Array:
	var out: Array = []
	for key in fashion.season_keys():
		out.append({"id": String(key), "name": String((fashion.SEASONS[key] as Dictionary).get("name", key))})
	return out

func new_brand(positioning: String, money: int = 1000000) -> Dictionary:
	if not _brand.is_empty():
		return {"ok": false, "reason": "already_owns"}
	if not fashion.POSITIONING.has(positioning):
		positioning = "mass"
	_brand = fashion.new_brand(money, {"positioning": positioning})
	_trend = fashion.new_trend()
	_persist_fashion()
	return {"ok": true, "name": String(_brand.get("name", "")), "positioning": positioning}

func fashion_design(discipline: String) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	if not fashion.DISCIPLINES.has(discipline):
		return {"ok": false, "reason": "bad_discipline"}
	var design: Dictionary = fashion.create_design(discipline, player().get("skills", []), _trend)
	if not bool(design.get("ok", false)):
		return design
	(_brand["collections"] as Array).append(design)
	_persist_fashion()
	return design

func fashion_week(season: String = "ss") -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var designs: Array = _brand.get("collections", [])
	if designs.is_empty():
		return {"ok": false, "reason": "no_design"}
	var r: Dictionary = fashion.fashion_week(_brand, designs, {"season": season})
	_persist_fashion()
	return r

func fashion_collab(partner_fame: float) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.collab(_brand, clampf(partner_fame, 0.0, 100.0))
	_persist_fashion()
	return r

func fashion_limited_edition(item: String, qty: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	if not fashion.LUXURY_ITEMS.has(item):
		return {"ok": false, "reason": "unknown_item"}
	var r: Dictionary = fashion.limited_edition(_brand, item, maxi(1, qty))
	_persist_fashion()
	return r

func fashion_open_store(cost: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.open_store(_brand, maxi(0, cost), current_region_id())
	if bool(r.get("ok", false)):
		_persist_fashion()
	return r

func fashion_marketing(kind: String, cost: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.run_marketing(_brand, kind, maxi(0, cost))
	if bool(r.get("ok", false)):
		_persist_fashion()
	return r

func fashion_renew(strategy: String, cost: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.renew_brand(_brand, strategy, maxi(0, cost))
	if bool(r.get("ok", false)):
		_persist_fashion()
	return r

## 品牌跨代传承：未指定继承人时取法定子女。
func fashion_inherit(heir: String = "") -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var name: String = heir.strip_edges()
	if name == "":
		var heirs: Array = legal_heirs().get("children", [])
		if heirs.is_empty():
			return {"ok": false, "reason": "no_heir"}
		name = String(heirs[0])
	var r: Dictionary = fashion.inherit_brand(_brand, name, {"day": now_minutes() / MINUTES_PER_DAY})
	if bool(r.get("ok", false)):
		_persist_fashion()
	return r

## 仿品侵权：品牌受损；若持有 IP 则同步发起 D25 维权诉讼。
func fashion_counterfeit(loss: int) -> Dictionary:
	if _brand.is_empty():
		return {"ok": false, "reason": "no_brand"}
	var r: Dictionary = fashion.counterfeit_hit(_brand, maxi(0, loss), {})
	if not _ips.is_empty():
		r["lawsuit"] = sue_ip_infringer(String((_ips[0] as Dictionary).get("id", "")), {"roll": -1.0})
	_persist_fashion()
	return r

func fashion_authenticate(item: String) -> Dictionary:
	if not fashion.LUXURY_ITEMS.has(item):
		return {"ok": false, "reason": "unknown_item"}
	var entry: Dictionary = (_brand.get("inventory", {}) as Dictionary).get(item, {}) if not _brand.is_empty() else {}
	var rec: Dictionary = {
		"authentic": true,
		"provenance": 0.8,
		"value": int(entry.get("price", int((fashion.LUXURY_ITEMS[item] as Dictionary).get("base_value", 0)))),
	}
	return fashion.authenticate(rec)

func fashion_panel_data() -> Dictionary:
	if _brand.is_empty():
		return {}
	var out: Dictionary = {
		"name": String(_brand.get("name", "")),
		"positioning": String(_brand.get("positioning", "mass")),
		"positioning_name": String((fashion.POSITIONING.get(String(_brand.get("positioning", "mass")), {}) as Dictionary).get("name", "")),
		"money": int(_brand.get("money", 0)),
		"reputation": float(_brand.get("reputation", 50.0)),
		"fame": float(_brand.get("fame", 0.0)),
		"relevance": float(_brand.get("relevance", 80.0)),
		"age_years": float(_brand.get("age_years", 0.0)),
		"brand_value": int(_brand.get("brand_value", 0)),
		"premium": fashion.brand_premium(_brand),
		"stores": (_brand.get("stores", []) as Array).size(),
		"trend_phase": String(_trend.get("phase", "")),
		"trend_phase_name": String(fashion.TREND_PHASE_NAMES.get(String(_trend.get("phase", "")), "")),
		"trend_hot": String((fashion.DISCIPLINES.get(String(_trend.get("hot_discipline", "")), {}) as Dictionary).get("name", "")),
	}
	var design_rows: Array = []
	for d in (_brand.get("collections", []) as Array):
		design_rows.append({
			"discipline": String(d.get("discipline", "")),
			"discipline_name": String((fashion.DISCIPLINES.get(String(d.get("discipline", "")), {}) as Dictionary).get("name", "")),
			"score": float(d.get("score", 0.0)), "grade": String(d.get("grade", "")),
		})
	out["designs"] = design_rows
	var inv_rows: Array = []
	for key in (_brand.get("inventory", {}) as Dictionary).keys():
		var inv: Dictionary = (_brand["inventory"] as Dictionary)[key]
		inv_rows.append({"key": String(key), "qty": int(inv.get("qty", 0)), "price": int(inv.get("price", 0))})
	out["inventory"] = inv_rows
	return out

func _persist_fashion() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["fashion"] = {"brand": fashion.to_dict(_brand), "trend": _trend.duplicate(true)}

## 品牌按年老化：相关度随定位自然衰减，玩家可用「品牌复兴」对冲。
func _fashion_tick(before_minutes: int, after_minutes: int) -> void:
	if _brand.is_empty():
		return
	var years: float = float(maxi(0, after_minutes - before_minutes)) / 525960.0
	if years <= 0.0:
		return
	fashion.brand_aging(_brand, years)
	_persist_fashion()


func sports_state() -> Dictionary:
	return {"player": _pro_player, "club": _sports_club, "rival": _sports_rival, "league": _sports_league}

func sports_injuries_catalog() -> Array:
	var out: Array = []
	for key in sports_industry.INJURIES.keys():
		out.append({"id": String(key), "name": String((sports_industry.INJURIES[key] as Dictionary).get("name", key))})
	return out

func sports_scandals_catalog() -> Array:
	var out: Array = []
	for key in sports_industry.SCANDALS.keys():
		out.append({"id": String(key), "name": String((sports_industry.SCANDALS[key] as Dictionary).get("name", key))})
	return out

func sports_competitions_catalog() -> Array:
	var out: Array = []
	for key in sports_industry.COMPETITIONS.keys():
		out.append({"id": String(key), "name": String((sports_industry.COMPETITIONS[key] as Dictionary).get("name", key))})
	return out

## 开启职业运动生涯：注册球会与地区联赛，签订首份职业合同。
func start_sports_career() -> Dictionary:
	if not _pro_player.is_empty():
		return {"ok": false, "reason": "already_career"}
	var pname := String(player().get("name", "我"))
	_pro_player = sports_industry.new_pro("player", "home_club", {"name": pname, "age": int(player().get("age", 22))})
	_sports_club = sports_industry.new_club("home_club", {"name": "本地球会"})
	_sports_rival = sports_industry.new_club("rival_club", {"name": "同城劲敌"})
	_sports_league = sports_industry.new_league("local_league", "top", {"name": "地区联赛"})
	sports_industry.register_club(_sports_league, _sports_club)
	sports_industry.register_club(_sports_league, _sports_rival)
	sports_industry.schedule_season(_sports_league)
	var wage: int = int(_pro_player.get("wage", 200000))
	sports_industry.sign_pro_contract(_pro_player, _sports_club, wage, 3.0)
	_sports_club["strength"] = sports_industry.club_strength(_sports_club)
	_persist_sports()
	return {"ok": true, "club": String(_sports_club.get("name", "")), "wage": wage}

## 出战一场联赛：推演比分、计入积分榜并为球会结算门票收入。
func sports_play_match() -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	if bool(_pro_player.get("disabled", false)):
		return {"ok": false, "reason": "disabled"}
	if float(_pro_player.get("injury_days", 0.0)) > 0.0:
		return {"ok": false, "reason": "injured"}
	if float(_pro_player.get("ban_days", 0.0)) > 0.0:
		return {"ok": false, "reason": "banned"}
	var r: Dictionary = sports_industry.play_match(_sports_league, _sports_club, _sports_rival)
	_pro_player["appearances"] = int(_pro_player.get("appearances", 0)) + 1
	if str(r.get("winner", "")) == String(_sports_club.get("id", "")):
		_pro_player["goals"] = int(_pro_player.get("goals", 0)) + 1
	_sports_club["budget"] = int(_sports_club.get("budget", 0)) + sports_industry.club_matchday_income(_sports_club)
	sports_industry.market_value(_pro_player)
	_persist_sports()
	return r

## 转会至对手球会：结算转会费与经纪人佣金，双方球会互换。
func sports_transfer(fee: int) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.transfer(_pro_player, _sports_rival, maxi(0, fee))
	if bool(r.get("ok", false)):
		var tmp: Dictionary = _sports_club
		_sports_club = _sports_rival
		_sports_rival = tmp
		_sports_club["strength"] = sports_industry.club_strength(_sports_club)
		_persist_sports()
	return r

## 签订代言合同：追加赞助商并抬升身价。
func sports_sponsorship(brand: String, amount: int) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var b := brand.strip_edges()
	if b == "":
		b = "赞助商"
	var r: Dictionary = sports_industry.sponsorship(_pro_player, {"brand": b, "amount": maxi(0, amount)})
	_persist_sports()
	return r

func sports_injure(severity: String) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.injure(_pro_player, severity)
	if bool(r.get("ok", false)):
		_persist_sports()
	return r

## 运动康复：按天数恢复，清除伤病天数并部分恢复状态。
func sports_rehab(days: float) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.rehab(_pro_player, maxf(0.0, days))
	_persist_sports()
	return r

## 兴奋剂检测：阳性则追加禁赛处罚。
func sports_doping_test() -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.doping_test(_pro_player, 0.1)
	if bool(r.get("positive", false)):
		sports_industry.commit_scandal(_pro_player, "doping")
	_persist_sports()
	return r

func sports_retire() -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.retire(_pro_player)
	_persist_sports()
	return r

## 国家队征召：状态达到门槛即可入选。
func sports_national_callup(nation: String = "中国") -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.national_callup(_pro_player, nation, {"form_threshold": 40.0})
	if bool(r.get("ok", false)):
		_persist_sports()
	return r

## 国家队集训：按天数提升状态。
func sports_national_camp(days: float = 10.0) -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var r: Dictionary = sports_industry.national_camp(_pro_player, maxf(0.0, days))
	if bool(r.get("ok", false)):
		_persist_sports()
	return r

## 国际赛事：以球会与国家队实力推演冠军并结算奖金。
func sports_international_tournament(competition: String = "world_cup") -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var club_name: String = String(_sports_club.get("name", "本地球会"))
	var rival_name: String = String(_sports_rival.get("name", "同城劲敌"))
	var teams: Array = [
		{"name": club_name, "strength": float(_sports_club.get("strength", 50.0)) + float(_pro_player.get("form", 50.0)) * 0.1},
		{"name": rival_name, "strength": float(_sports_rival.get("strength", 50.0))},
		{"name": "国家队", "strength": 72.0},
		{"name": "海外劲旅", "strength": 78.0},
	]
	var r: Dictionary = sports_industry.international_tournament(competition, teams, rng, {"reward": 30000000})
	if bool(r.get("ok", false)):
		var reward: int = int(r.get("reward", 0))
		if String(r.get("champion", "")) == club_name:
			economy.add_money(account_id(), reward, "sports_tournament")
		else:
			r["reward"] = 0
		_pro_player["last_tournament"] = {"competition": competition, "champion": String(r.get("champion", "")), "reward": int(r.get("reward", 0))}
		_persist_sports()
	return r

## 球迷冲突：罚款并损伤球会声誉。
func sports_fan_violence() -> Dictionary:
	if _sports_club.is_empty():
		return {"ok": false, "reason": "no_club"}
	var r: Dictionary = sports_industry.fan_violence(_sports_club, 0.0, {"force": true})
	_persist_sports()
	return r

## 裁判争议：申诉并支付申诉费。
func sports_referee_controversy() -> Dictionary:
	if _sports_club.is_empty():
		return {"ok": false, "reason": "no_club"}
	var r: Dictionary = sports_industry.referee_controversy({}, 0.0, {"force": true})
	var fee: int = int(r.get("protest_fee", 0))
	if bool(r.get("disputed", false)) and fee > 0:
		if int(economy.cash(account_id())) < fee:
			return {"ok": false, "reason": "insufficient_funds", "protest_fee": fee}
		economy.add_money(account_id(), -fee, "sports_protest")
		_sports_club["reputation"] = clampf(float(_sports_club.get("reputation", 50.0)) - 3.0, 0.0, 100.0)
	_persist_sports()
	return r

## 学业冲突：在役且在读时，训练挤压学业；成绩过低退学。
func sports_academic_conflict() -> Dictionary:
	if _pro_player.is_empty():
		return {"ok": false, "reason": "no_career"}
	var enrolled: bool = false
	var edu: Array = player().get("education", []) if player().get("education", []) is Array else []
	for e in edu:
		if e is Dictionary and String((e as Dictionary).get("status", "")) == "enrolled":
			enrolled = true
			break
	if not enrolled:
		return {"ok": true, "conflict": false, "reason": "not_enrolled"}
	var p: Dictionary = {"enrolled": true, "gpa": float(player().get("gpa", 70.0))}
	var r: Dictionary = sports_industry.academic_conflict(p, {})
	player()["gpa"] = float(p.get("gpa", 70.0))
	player()["enrolled"] = bool(p.get("enrolled", true))
	if not bool(r.get("can_continue", true)):
		for e in edu:
			if e is Dictionary and String((e as Dictionary).get("status", "")) == "enrolled":
				(e as Dictionary)["status"] = "suspended"
		player()["education"] = edu
	_persist_sports()
	return r

func sports_panel_data() -> Dictionary:
	if _pro_player.is_empty():
		return {}
	var out: Dictionary = {
		"stage": String(_pro_player.get("career_stage", "")),
		"age": int(_pro_player.get("age", 0)),
		"form": float(_pro_player.get("form", 0.0)),
		"market_value": int(_pro_player.get("market_value", 0)),
		"wage": int(_pro_player.get("wage", 0)),
		"injury_days": float(_pro_player.get("injury_days", 0.0)),
		"ban_days": float(_pro_player.get("ban_days", 0.0)),
		"appearances": int(_pro_player.get("appearances", 0)),
		"goals": int(_pro_player.get("goals", 0)),
		"club": String(_sports_club.get("name", "")),
		"club_division": String(_sports_club.get("division", "top")),
		"budget": int(_sports_club.get("budget", 0)),
		"club_reputation": float(_sports_club.get("reputation", 50.0)),
		"sponsors": (_pro_player.get("sponsors", []) as Array).size(),
		"national_team": String(_pro_player.get("national_team", "")),
		"last_tournament": (_pro_player.get("last_tournament", {}) as Dictionary).duplicate(true),
	}
	var rows: Array = []
	for row in sports_industry.standings(_sports_league):
		rows.append({
			"id": String(row.get("id", "")),
			"played": int(row.get("played", 0)),
			"points": int(row.get("points", 0)),
			"goals_for": int(row.get("goals_for", 0)),
			"goals_against": int(row.get("goals_against", 0)),
		})
	out["standings"] = rows
	return out

func _persist_sports() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["sports"] = {
		"player": _pro_player.duplicate(true),
		"club": _sports_club.duplicate(true),
		"rival": _sports_rival.duplicate(true),
		"league": _sports_league.duplicate(true),
	}


func events_state() -> Dictionary:
	return {"event": _event, "planner": _planner}

func events_types_catalog() -> Array:
	var out: Array = []
	for key in events_expo.event_type_keys():
		out.append({"id": String(key), "name": String((events_expo.EVENT_TYPES[key] as Dictionary).get("name", key))})
	return out

func events_stages_catalog() -> Array:
	var out: Array = []
	var names: Dictionary = events_expo.stage_names()
	for key in events_expo.STAGES:
		out.append({"id": String(key), "name": String(names.get(String(key), key))})
	return out

func events_sponsor_tiers_catalog() -> Array:
	var out: Array = []
	for key in events_expo.sponsor_tier_keys():
		out.append({"id": String(key), "name": String((events_expo.SPONSOR_TIERS[key] as Dictionary).get("name", key))})
	return out

func events_roles_catalog() -> Array:
	var out: Array = []
	for key in events_expo.career_role_keys():
		out.append({"id": String(key), "name": String((events_expo.CAREER_ROLES[key] as Dictionary).get("name", key))})
	return out

## 开启活动策划职业路径。
func start_event_career(role: String = "planner") -> Dictionary:
	if not _planner.is_empty():
		return {"ok": false, "reason": "already_planner"}
	_planner = events_expo.new_planner(role)
	_persist_events()
	return {"ok": true, "role": String(_planner.get("role", role)), "level": int(_planner.get("level", 1))}

## 筹办一场新活动（覆盖上一场已复盘的活动）。
func events_new(event_type: String) -> Dictionary:
	if not _event.is_empty() and str(_event.get("stage", "")) != "review":
		return {"ok": false, "reason": "in_progress"}
	if not events_expo.EVENT_TYPES.has(event_type):
		return {"ok": false, "reason": "unknown_type"}
	_event = events_expo.new_event(event_type)
	_persist_events()
	return {"ok": true, "type": event_type, "name": String(_event.get("name", ""))}

func events_rent_venue(cost: int) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var capacity: int = int((events_expo.EVENT_TYPES.get(String(_event.get("type", "")), {}) as Dictionary).get("base_capacity", 10000))
	var venue: Dictionary = {"name": "会展中心", "capacity": capacity, "cost": maxi(0, cost)}
	var r: Dictionary = events_expo.rent_venue(_event, venue)
	if bool(r.get("ok", false)):
		_persist_events()
	return r

func events_approval() -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.apply_approval(_event, true)
	_persist_events()
	return r

func events_sponsor(tier: String) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.add_sponsor(_event, tier)
	if bool(r.get("ok", false)):
		_persist_events()
	return r

func events_sell_tickets(qty: int) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.sell_tickets(_event, maxi(0, qty))
	_persist_events()
	return r

## 票务二级市场：持票人转售，平台佣金进入活动收入。
func events_secondary_market(qty: int, premium: float = 1.4) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.secondary_market(_event, maxi(0, qty), {"premium": premium})
	if bool(r.get("ok", false)):
		_persist_events()
	return r

func events_set_security(level: float) -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.set_security(_event, level)
	if bool(r.get("ok", false)):
		_persist_events()
	return r

## 举办活动：确定性推演现场（roll 固定），结算门票/周边/直播与风险。
func events_hold() -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	if str(_event.get("stage", "")) == "review":
		return {"ok": false, "reason": "already_held"}
	if not bool(_event.get("approved", false)):
		return {"ok": false, "reason": "not_approved"}
	var r: Dictionary = events_expo.hold_event(_event, 0.1)
	var attendance: int = int(r.get("attendance", 0))
	if bool(r.get("ok", false)) and attendance > 0 and not _city_municipal.is_empty():
		var complaint: Dictionary = municipal.report_nuisance(_city_municipal, {
			"source": "large_event",
			"severity": clampf(float(attendance) / 50000.0, 0.1, 0.8),
			"day": WeatherScript.day_of_minute(now_minutes()),
		})
		_persist_municipal()
		r["nuisance"] = complaint.get("severity", 0.0)
	_persist_events()
	return r

## 复盘：结算净利润，若已从业则累计经验并可能升级。
func events_review() -> Dictionary:
	if _event.is_empty():
		return {"ok": false, "reason": "no_event"}
	var r: Dictionary = events_expo.after_action_review(_event)
	var profit: int = int(r.get("profit", 0))
	if profit != 0:
		economy.add_money(account_id(), profit, "event_review")
	r["settled"] = profit
	if not _planner.is_empty():
		var cp: Dictionary = events_expo.career_progress(_planner, r)
		r["planner"] = cp
	_persist_events()
	return r

func events_panel_data() -> Dictionary:
	if _event.is_empty() and _planner.is_empty():
		return {}
	var out: Dictionary = {}
	if not _event.is_empty():
		var def: Dictionary = events_expo.EVENT_TYPES.get(String(_event.get("type", "")), {})
		out = {
			"type": String(_event.get("type", "")),
			"type_name": String(def.get("name", "")),
			"name": String(_event.get("name", "")),
			"stage": String(_event.get("stage", "")),
			"stage_name": String(events_expo.STAGE_NAMES.get(String(_event.get("stage", "")), "")),
			"capacity": int(_event.get("capacity", 0)),
			"sold": int(_event.get("sold", 0)),
			"ticket_price": int(_event.get("ticket_price", 0)),
			"budget": int(_event.get("budget", 0)),
			"revenue": int(_event.get("revenue", 0)),
			"cost": int(_event.get("cost", 0)),
			"reputation": float(_event.get("reputation", 0.0)),
			"attendance": int(_event.get("attendance", 0)),
			"sponsors": (_event.get("sponsors", []) as Array).size(),
			"incidents": (_event.get("incidents", []) as Array).size(),
			"resales": int(_event.get("resales", 0)),
			"resale_commission": int(_event.get("resale_commission", 0)),
		}
	if not _planner.is_empty():
		out["planner_level"] = int(_planner.get("level", 1))
		out["planner_exp"] = int(_planner.get("exp", 0))
		out["planner_events"] = int(_planner.get("events_done", 0))
	return out

func _persist_events() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["events"] = {
		"event": events_expo.to_dict(_event),
		"planner": _planner.duplicate(true),
	}


func honors_state() -> Dictionary:
	return {"candidate": _honor_candidate, "hall": _hall}

func honors_categories_catalog() -> Array:
	var out: Array = []
	for key in honors.categories():
		out.append({"id": String(key), "name": honors.category_name(String(key))})
	return out

func honors_awards_catalog() -> Array:
	var out: Array = []
	for key in honors.award_keys():
		var def: Dictionary = honors.AWARDS[key]
		out.append({
			"id": String(key),
			"name": String(def.get("name", key)),
			"category_name": honors.category_name(String(def.get("category", ""))),
			"threshold": float(def.get("threshold", 0.0)),
			"prestige": float(def.get("prestige", 0.0)),
		})
	return out

## 开启荣誉档案：候选人初始成就由参数给定（缺省 60）。
func start_honor_profile(achievement: float = 60.0) -> Dictionary:
	if not _honor_candidate.is_empty():
		return {"ok": false, "reason": "already_profile"}
	_honor_candidate = honors.new_candidate("player", {
		"name": String(player().get("name", "我")),
		"achievement": clampf(achievement, 0.0, 100.0),
	})
	_persist_honors()
	return {"ok": true, "achievement": float(_honor_candidate.get("achievement", 0.0))}

func honors_nominate(award_key: String) -> Dictionary:
	if _honor_candidate.is_empty():
		return {"ok": false, "reason": "no_profile"}
	return honors.nominate(_honor_candidate, award_key)

func honors_evaluate(award_key: String) -> Dictionary:
	if _honor_candidate.is_empty():
		return {"ok": false, "reason": "no_profile"}
	return honors.evaluate(_honor_candidate, award_key)

## 领奖：完成评定并（达标时）登记荣誉与入名人堂。
func honors_award(award_key: String, corrupt: bool = false) -> Dictionary:
	if _honor_candidate.is_empty():
		return {"ok": false, "reason": "no_profile"}
	var jury: Dictionary = {"corruption": 0.9} if corrupt else {}
	var r: Dictionary = honors.award(_honor_candidate, award_key, jury, {
		"hall": _hall, "enshrine": true,
		"generation": maxi(1, int(state.legacy.get("generation", 0)) + 1),
	})
	if bool(r.get("awarded", false)):
		honors.honor_effects(_honor_candidate)
	_persist_honors()
	return r

## 买奖：打上隐蔽黑幕并借助评审腐败运作。
func honors_buy(award_key: String) -> Dictionary:
	if _honor_candidate.is_empty():
		return {"ok": false, "reason": "no_profile"}
	honors.mark_scandal(_honor_candidate, "bought_award", {"severity": 0.8})
	var r: Dictionary = honors_award(award_key, true)
	_persist_honors()
	return r

## 揭露黑幕：清算声望、撤销荣誉与名人堂记录。
func honors_expose() -> Dictionary:
	if _honor_candidate.is_empty():
		return {"ok": false, "reason": "no_profile"}
	var r: Dictionary = honors.expose_scandal(_honor_candidate, {"hall": _hall})
	_persist_honors()
	return r

func honors_inherit() -> Dictionary:
	return honors.inherit_evaluation(_hall)

## 跨代名人堂与家族史联动：名人堂代际聚合 + legacy.history/lineage 叙事。
func honors_family_legacy() -> Dictionary:
	return honors.family_legacy(_hall, state.legacy)

func honors_panel_data() -> Dictionary:
	if _honor_candidate.is_empty() and _hall.is_empty():
		return {}
	var out: Dictionary = {}
	if not _honor_candidate.is_empty():
		out["achievement"] = float(_honor_candidate.get("achievement", 0.0))
		out["relations"] = float(_honor_candidate.get("relations", 0.0))
		out["reputation"] = float(_honor_candidate.get("reputation", 0.0))
		out["privileges"] = (_honor_candidate.get("privileges", []) as Array).size()
		var honor_rows: Array = []
		for h in (_honor_candidate.get("honors", []) as Array):
			var hd: Dictionary = h
			if bool(hd.get("revoked", false)):
				continue
			honor_rows.append({"name": String(hd.get("name", "")), "category": honors.category_name(String(hd.get("category", ""))), "prestige": float(hd.get("prestige", 0.0))})
		out["honors"] = honor_rows
	out["hall_size"] = honors.hall_size(_hall)
	out["hall_active"] = int(honors.inherit_evaluation(_hall).get("active_honors", 0))
	out["family_legacy"] = honors_family_legacy()
	return out

func _persist_honors() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["honors"] = {
		"candidate": honors.to_dict(_honor_candidate),
		"hall": _hall.duplicate(true),
	}



# --- D35 安保、警务与刑侦 ---

func police_state() -> Dictionary:
	return {"case": _police_case, "firm": _security_firm}

func police_crimes_catalog() -> Array:
	var out: Array = []
	var defs: Dictionary = CrimeScript.CRIMES
	for key in defs.keys():
		out.append({"id": String(key), "name": String((defs[key] as Dictionary).get("name", key))})
	return out

func police_roles_catalog() -> Array:
	var out: Array = []
	for key in police.role_keys():
		var d: Dictionary = police.role_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key)), "skill": String(d.get("skill", ""))})
	return out

func police_evidence_catalog() -> Array:
	var out: Array = []
	for key in police.evidence_kinds():
		out.append({"id": String(key), "name": String(police.EVIDENCE_NAMES.get(String(key), key))})
	return out

func police_stages_catalog() -> Array:
	var names: Dictionary = police.stage_names()
	var out: Array = []
	for st in police.STAGES:
		out.append({"id": String(st), "name": String(names.get(String(st), st))})
	return out

func police_services_catalog() -> Array:
	var out: Array = []
	for key in police.security_service_keys():
		var d: Dictionary = police.security_service_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key)), "base_fee": int(d.get("base_fee", 0))})
	return out

func police_start_case(crime: String, role: String = "detective") -> Dictionary:
	var region: String = _home_region_id
	var r: Dictionary = police.new_case(crime, region, {"role": role})
	_police_case = r
	var case_id: String = "case:%d:%d" % [now_minutes(), domain_wake.entry_count()]
	var due: int = now_minutes() + BaselineScript.WAKE_CASE_LIMIT_DAYS * BaselineScript.WAKE_MINUTES_PER_DAY
	domain_register(case_id, DomainWakeScript.KIND_CASE, {
		"region_id": region, "due_minute": due, "total": due - now_minutes(), "case_id": case_id,
	})
	_persist_police()
	return {"ok": true, "case": _police_case}

func police_survey() -> Dictionary:
	if _police_case.is_empty():
		return {"ok": false, "reason": "no_case"}
	var r: Dictionary = police.survey(_police_case)
	_persist_police()
	return r

func police_collect(kind: String, strength: float = 0.3) -> Dictionary:
	if _police_case.is_empty():
		return {"ok": false, "reason": "no_case"}
	var r: Dictionary = police.collect(_police_case, kind, strength)
	_persist_police()
	return r

func police_warrant() -> Dictionary:
	if _police_case.is_empty():
		return {"ok": false, "reason": "no_case"}
	var r: Dictionary = police.request_warrant(_police_case, {"granted": true})
	_persist_police()
	return r

func police_interrogate(pressure: float = 0.5) -> Dictionary:
	if _police_case.is_empty():
		return {"ok": false, "reason": "no_case"}
	var r: Dictionary = police.interrogate(_police_case, pressure, {"roll": -1.0}, rng)
	_persist_police()
	return r

func police_informant() -> Dictionary:
	if _police_case.is_empty():
		return {"ok": false, "reason": "no_case"}
	var r: Dictionary = police.use_informant(_police_case, {"roll": -1.0}, rng)
	_persist_police()
	return r

func police_undercover() -> Dictionary:
	if _police_case.is_empty():
		return {"ok": false, "reason": "no_case"}
	var r: Dictionary = police.deploy_undercover(_police_case, {"roll": -1.0}, rng)
	_persist_police()
	return r

func police_tech() -> Dictionary:
	if _police_case.is_empty():
		return {"ok": false, "reason": "no_case"}
	var r: Dictionary = police.tech_surveillance(_police_case)
	_persist_police()
	return r

func police_advance() -> Dictionary:
	if _police_case.is_empty():
		return {"ok": false, "reason": "no_case"}
	var r: Dictionary = police.advance(_police_case, {"roll": -1.0}, rng)
	_persist_police()
	return r

func start_security_firm(name: String) -> Dictionary:
	if not _security_firm.is_empty():
		return {"ok": false, "reason": "already_firm"}
	_security_firm = police.new_security_firm(name, {"funds": int(economy.cash(account_id()))})
	_persist_police()
	return {"ok": true, "firm": _security_firm}

func security_take_contract(kind: String) -> Dictionary:
	if _security_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var r: Dictionary = police.take_contract(_security_firm, kind)
	_persist_police()
	return r

func security_resolve_contract() -> Dictionary:
	if _security_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var contracts: Array = _security_firm.get("contracts", [])
	if contracts.is_empty():
		return {"ok": false, "reason": "no_contract"}
	var contract: Dictionary = contracts[contracts.size() - 1]
	var r: Dictionary = police.resolve_contract(_security_firm, contract, {"roll": -1.0}, rng)
	_persist_police()
	return r

func police_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _police_case.is_empty():
		var ev: Dictionary = _police_case.get("evidence", {})
		var ev_rows: Array = []
		for k in police.evidence_kinds():
			ev_rows.append({"name": String(police.EVIDENCE_NAMES.get(String(k), k)), "value": float(ev.get(String(k), 0.0))})
		out["case"] = {
			"crime": String(_police_case.get("crime", "")),
			"region": String(_police_case.get("region", "")),
			"stage": String(police.STAGE_NAMES.get(String(_police_case.get("stage", "")), _police_case.get("stage", ""))),
			"role": String((police.role_def(String(_police_case.get("role", ""))) as Dictionary).get("name", "")),
			"evidence": ev_rows,
			"evidence_score": police.evidence_score(_police_case),
			"leads": float(_police_case.get("leads", 0.0)),
			"legality": police.legality_score(_police_case),
			"solve_probability": police.solve_probability(_police_case),
			"wrongful": bool(_police_case.get("wrongful", false)),
		}
	if not _security_firm.is_empty():
		var contracts: Array = _security_firm.get("contracts", [])
		var c_rows: Array = []
		for c in contracts:
			c_rows.append({
				"name": String((c as Dictionary).get("name", "")),
				"fee": int((c as Dictionary).get("fee", 0)),
				"resolved": bool((c as Dictionary).get("resolved", false)),
				"failure": bool((c as Dictionary).get("failure", false)),
			})
		out["firm"] = {
			"name": String(_security_firm.get("name", "")),
			"staff": int(_security_firm.get("staff", 0)),
			"funds": int(_security_firm.get("funds", 0)),
			"reputation": float(_security_firm.get("reputation", 0.0)),
			"contracts": c_rows,
		}
	return out

func _persist_police() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["police"] = {
		"case": police.to_dict(_police_case),
		"firm": _security_firm.duplicate(true),
	}



# --- D36 应急、消防与灾害救援 ---

func emergency_state() -> Dictionary:
	return {"incident": _incident, "org": _volunteer_org}

func emergency_professions_catalog() -> Array:
	var out: Array = []
	for key in emergency.profession_keys():
		var d: Dictionary = emergency.profession_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func emergency_stages_catalog() -> Array:
	var names: Dictionary = emergency.stage_names()
	var out: Array = []
	for st in emergency.STAGES:
		out.append({"id": String(st), "name": String(names.get(String(st), st))})
	return out

func emergency_new_incident(type: String, severity: float = 0.5) -> Dictionary:
	var r: Dictionary = emergency.new_incident(type, {"region": _home_region_id, "severity": severity, "at_risk": 200, "trapped": 40})
	_incident = r
	var iid: String = "disaster:%d:%d" % [now_minutes(), domain_wake.entry_count()]
	var duration: float = float(BaselineScript.WAKE_DISASTER_HOURS * 60)
	domain_register(iid, DomainWakeScript.KIND_DISASTER, {
		"region_id": _home_region_id, "total": duration, "progress": 0.0,
		"params": {"duration_minutes": duration, "severity": severity},
		"incident_at": iid,
	})
	_persist_emergency()
	return {"ok": true, "incident": _incident}

## 天气灾害接警：读取当前区域当日灾害，生成应急事件并结算设施损毁与人身伤害。
func emergency_weather_disaster() -> Dictionary:
	var rid: String = current_region_id()
	if rid == "" or weather == null:
		return {"ok": false, "reason": "no_disaster"}
	var day: int = WeatherScript.day_of_minute(now_minutes())
	var events: Array = weather.disasters_on(rid, day)
	if events.is_empty():
		return {"ok": false, "reason": "no_disaster"}
	if not _incident.is_empty() and int(_incident.get("disaster_day", -1)) == day:
		return {"ok": false, "reason": "already_reported"}
	var ev: Dictionary = events[0]
	var key: String = String(ev.get("key", ""))
	var name: String = String(ev.get("name", key))
	var prof_map: Dictionary = {
		"earthquake": "earthquake_rescue", "flood": "flood_rescue", "tsunami": "flood_rescue",
		"typhoon": "fire", "wildfire": "fire", "mudslide": "mountain_rescue",
		"drought": "flood_rescue", "blizzard": "mountain_rescue",
		"hailstorm": "fire", "locust": "flood_rescue",
	}
	var sev_map: Dictionary = {
		"earthquake": 0.9, "tsunami": 0.85, "flood": 0.7, "typhoon": 0.8,
		"wildfire": 0.65, "mudslide": 0.7, "drought": 0.5, "blizzard": 0.65,
		"hailstorm": 0.45, "locust": 0.4,
	}
	var prof: String = String(prof_map.get(key, "fire"))
	var severity: float = float(sev_map.get(key, 0.5))
	var base: Dictionary = emergency_new_incident(prof, severity)
	if not bool(base.get("ok", false)):
		return base
	_incident["disaster"] = key
	_incident["disaster_name"] = name
	_incident["disaster_day"] = day
	_incident["at_risk"] = int(round(120.0 + severity * 280.0))
	_incident["trapped"] = int(round(20.0 + severity * 60.0))
	var fac_types: Dictionary = {
		"earthquake": ["road", "bridge", "sewage", "lighting"],
		"flood": ["road", "bridge", "sewage", "sanitation"],
		"tsunami": ["road", "bridge", "sewage", "sanitation"],
		"typhoon": ["road", "bridge", "lighting", "park"],
		"wildfire": ["park", "sanitation", "lighting"],
		"mudslide": ["road", "bridge"],
		"drought": ["park", "sanitation"],
		"blizzard": ["road", "bridge", "lighting", "park"],
		"hailstorm": ["road", "bridge", "park"],
		"locust": ["park", "sanitation"],
	}
	var damage: Dictionary = municipal.damage_facilities(_city_municipal, severity, {"types": fac_types.get(key, ["road", "bridge"])})
	var injury: float = clampf(round(severity * 6.0 + 1.0), 1.0, 8.0)
	_damage_health(injury)
	_persist_municipal()
	var outage: bool = false
	var outage_types: Array = ["earthquake", "flood", "tsunami", "typhoon", "blizzard", "hailstorm", "mudslide"]
	if not _factory.is_empty() and key in outage_types and severity >= 0.5:
		manufacturing.set_disruption(_factory, "power_outage", true)
		_factory["power_outage_until"] = now_minutes() + 2880
		_persist_manufacturing()
		outage = true
	_incident["applied"] = {"injury": injury, "facility_losses": damage.get("losses", {}), "power_outage": outage}
	_persist_emergency()
	return {"ok": true, "incident": _incident, "disaster": key, "disaster_name": name, "injury": injury, "facility_losses": damage.get("losses", {}), "power_outage": outage}

## 跨区增援：按距离与队伍数计费，补充现场救援队与医疗容量。
func emergency_mutual_aid(distance_km: float, teams: int = 2) -> Dictionary:
	if _incident.is_empty():
		return {"ok": false, "reason": "no_incident"}
	var added: int = clampi(teams, 1, 10)
	var distance: float = clampf(distance_km, 1.0, 2000.0)
	var cost: int = added * 20000 + int(round(distance * 5000.0))
	if int(economy.cash(account_id())) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	economy.add_money(account_id(), -cost, "mutual_aid")
	var r: Dictionary = emergency.request_mutual_aid(_incident, added, distance, {"cost": cost, "source_region": "neighbor"})
	r["cost"] = cost
	_persist_emergency()
	return r

func emergency_dispatch(distance_km: float = 5.0) -> Dictionary:
	if _incident.is_empty():
		return {"ok": false, "reason": "no_incident"}
	var r: Dictionary = emergency.dispatch(_incident, {"distance_km": distance_km})
	_persist_emergency()
	return r

func emergency_rescue() -> Dictionary:
	if _incident.is_empty():
		return {"ok": false, "reason": "no_incident"}
	var r: Dictionary = emergency.rescue(_incident)
	_persist_emergency()
	return r

func emergency_secondary() -> Dictionary:
	if _incident.is_empty():
		return {"ok": false, "reason": "no_incident"}
	var r: Dictionary = emergency.secondary_incident(_incident, {"roll": -1.0}, rng)
	_persist_emergency()
	return r

func emergency_aftermath() -> Dictionary:
	if _incident.is_empty():
		return {"ok": false, "reason": "no_incident"}
	var r: Dictionary = emergency.aftermath(_incident)
	# 跨域：灾后心理创伤写回心理压力/情绪，指挥失当罚款从现金扣除。
	var trauma: float = clampf(float(r.get("psych_trauma", 0.0)), 0.0, 1.0)
	var stress_added: float = 0.0
	if trauma > 0.0:
		var attrs: Dictionary = player().get("attrs", {})
		var psych: Dictionary = attrs.get("psychological", {})
		var before_stress: float = float(psych.get("stress", 0.0))
		psych["stress"] = clampf(before_stress + trauma * 40.0, 0.0, 100.0)
		psych["mood"] = clampf(float(psych.get("mood", 50.0)) - trauma * 25.0, 0.0, 100.0)
		attrs["psychological"] = psych
		player()["attrs"] = attrs
		stress_added = float(psych["stress"]) - before_stress
	var penalty: int = maxi(0, int(r.get("penalty", 0)))
	var paid: int = 0
	if penalty > 0:
		paid = mini(penalty, maxi(0, int(economy.cash(account_id()))))
		if paid > 0:
			economy.add_money(account_id(), -paid, "emergency_penalty")
			sync_finances()
		r["penalty_paid"] = paid
	r["stress_added"] = stress_added
	_incident["applied"] = {"stress": stress_added, "penalty_paid": paid}
	_persist_emergency()
	return r

func start_volunteer_org(name: String) -> Dictionary:
	if not _volunteer_org.is_empty():
		return {"ok": false, "reason": "already_org"}
	_volunteer_org = emergency.new_volunteer_org(name, {"funds": int(economy.cash(account_id()))})
	_persist_emergency()
	return {"ok": true, "org": _volunteer_org}

func volunteer_purchase(item: String, cost: int) -> Dictionary:
	if _volunteer_org.is_empty():
		return {"ok": false, "reason": "no_org"}
	var r: Dictionary = emergency.purchase_equipment(_volunteer_org, item, cost)
	_persist_emergency()
	return r

func volunteer_recruit(count: int) -> Dictionary:
	if _volunteer_org.is_empty():
		return {"ok": false, "reason": "no_org"}
	var r: Dictionary = emergency.recruit_volunteers(_volunteer_org, count)
	_persist_emergency()
	return r

func volunteer_dispatch_incident() -> Dictionary:
	if _incident.is_empty():
		return {"ok": false, "reason": "no_incident"}
	if _volunteer_org.is_empty():
		return {"ok": false, "reason": "no_org"}
	var r: Dictionary = emergency.volunteer_dispatch(_volunteer_org, _incident)
	_persist_emergency()
	return r

func emergency_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _incident.is_empty():
		var tri: Dictionary = _incident.get("triage", {})
		out["incident"] = {
			"type": String((emergency.profession_def(String(_incident.get("type", ""))) as Dictionary).get("name", _incident.get("type", ""))),
			"disaster_name": String(_incident.get("disaster_name", "")),
			"stage": String(emergency.STAGE_NAMES.get(String(_incident.get("stage", "")), _incident.get("stage", ""))),
			"severity": float(_incident.get("severity", 0.0)),
			"at_risk": int(_incident.get("at_risk", 0)),
			"trapped": int(_incident.get("trapped", 0)),
			"response_minutes": float(_incident.get("response_minutes", -1.0)),
			"deaths": int(_incident.get("deaths", 0)),
			"injured": int(_incident.get("injured", 0)),
			"rescued": int(_incident.get("rescued", 0)),
			"fault": String(_incident.get("fault", "")),
			"stress_added": float((_incident.get("applied", {}) as Dictionary).get("stress", 0.0)),
			"penalty_paid": int((_incident.get("applied", {}) as Dictionary).get("penalty_paid", 0)),
			"triage": {"treated": float(tri.get("treated", 0.0)), "untreated": float(tri.get("untreated", 0.0))},
			"rescue_teams": int((_incident.get("resources", {}) as Dictionary).get("rescue_teams", 1)),
			"mutual_aid": (_incident.get("mutual_aid", []) as Array).size(),
		}
	if not _volunteer_org.is_empty():
		out["org"] = {
			"name": String(_volunteer_org.get("name", "")),
			"volunteers": int(_volunteer_org.get("volunteers", 0)),
			"equipment": int(_volunteer_org.get("equipment", 0)),
			"funds": int(_volunteer_org.get("funds", 0)),
			"reputation": float(_volunteer_org.get("reputation", 0.0)),
		}
	return out

func _persist_emergency() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["emergency"] = {
		"incident": emergency.to_dict(_incident),
		"org": _volunteer_org.duplicate(true),
	}



# --- D37 环保、碳排与可持续发展 ---

func environment_state() -> Dictionary:
	return {"city": _city_env, "enterprise": _env_enterprise, "org": _env_org}

func environment_careers_catalog() -> Array:
	var out: Array = []
	for key in environment_sys.career_keys():
		var d: Dictionary = environment_sys.career_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func env_set_garbage_sorting(rate: float) -> Dictionary:
	var r: Dictionary = environment_sys.set_garbage_sorting(_city_env, rate)
	_persist_environment()
	return r

func env_recycle(generated: float) -> Dictionary:
	var r: Dictionary = environment_sys.recycle(_city_env, generated)
	_persist_environment()
	return r

func env_treat_sewage(rate: float) -> Dictionary:
	var r: Dictionary = environment_sys.treat_sewage(_city_env, rate)
	_persist_environment()
	return r

func env_air_control(investment: int) -> Dictionary:
	var r: Dictionary = environment_sys.air_control(_city_env, investment)
	_persist_environment()
	return r

func env_issue_permit(source: String, allowance: float) -> Dictionary:
	var r: Dictionary = environment_sys.issue_permit(_city_env, source, allowance)
	_persist_environment()
	return r

func env_carbon_account() -> Dictionary:
	var footprint: Dictionary = environment_sys.carbon_footprint(_env_enterprise)
	var esg: Dictionary = environment_sys.esg_rating(_env_enterprise)
	_persist_environment()
	return {"ok": true, "balance": environment_sys.carbon_balance(_env_enterprise), "footprint": footprint, "esg": esg}

func env_carbon_trade(credits: float) -> Dictionary:
	var price: int = int(_env_enterprise.get("carbon_price", 100))
	var cash: int = int(round(credits * float(price)))
	if cash > 0 and int(economy.cash(account_id())) < cash:
		return {"ok": false, "reason": "insufficient_funds", "cost": cash}
	var r: Dictionary = environment_sys.carbon_trade(_env_enterprise, credits)
	if bool(r.get("ok", false)) and cash != 0:
		economy.add_money(account_id(), -cash, "carbon_trade")
		r["paid"] = cash
	_persist_environment()
	return r

func env_carbon_auction(bid_credits: float, bid_price: int = 160) -> Dictionary:
	var cost_est: int = int(round(maxf(0.0, bid_credits) * float(bid_price)))
	if int(economy.cash(account_id())) < cost_est:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost_est}
	var r: Dictionary = environment_sys.carbon_auction(_env_enterprise, maxf(0.0, bid_credits), bid_price)
	if bool(r.get("ok", false)) and int(r.get("cost", 0)) > 0:
		economy.add_money(account_id(), -int(r["cost"]), "carbon_auction")
		_persist_environment()
	return r

## 跨企业碳市场：玩家企业与三家同业参与撮合，成交额回写/扣减玩家现金。
func env_carbon_market() -> Dictionary:
	var peers: Array = [
		environment_sys.new_enterprise("华东电力", {"emissions": 320.0, "quota": 220.0, "carbon_price": 100}),
		environment_sys.new_enterprise("绿源水泥", {"emissions": 140.0, "quota": 260.0, "carbon_price": 100}),
		environment_sys.new_enterprise("北岭钢铁", {"emissions": 260.0, "quota": 210.0, "carbon_price": 100}),
	]
	var pool: Array = [_env_enterprise]
	pool.append_array(peers)
	var r: Dictionary = environment_sys.match_carbon_market(pool)
	var mine: String = String(_env_enterprise.get("name", ""))
	var cash: int = 0
	var player_trade: Dictionary = {}
	for t in r.get("trades", []):
		var trade: Dictionary = t
		if String(trade.get("buyer", "")) == mine:
			cash -= int(trade.get("cash", 0))
			player_trade = trade
		elif String(trade.get("seller", "")) == mine:
			cash += int(trade.get("cash", 0))
			player_trade = trade
	if cash != 0:
		economy.add_money(account_id(), cash, "carbon_market")
	if not player_trade.is_empty():
		_persist_environment()
	r["player_trade"] = player_trade
	r["player_cash"] = cash
	return r

func env_carbon_compliance(mode: String) -> Dictionary:
	var balance: float = environment_sys.carbon_balance(_env_enterprise)
	var cost: int = 0
	if balance > 0.0 and mode != "fine":
		cost = int(round(balance * float(_env_enterprise.get("carbon_price", 100))))
		if int(economy.cash(account_id())) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	var r: Dictionary = environment_sys.compliance(_env_enterprise, {"mode": mode})
	cost = int(r.get("cost", 0))
	if bool(r.get("ok", false)) and cost > 0:
		economy.add_money(account_id(), -cost, "carbon_compliance")
	_persist_environment()
	return r

func env_report_carbon(reported: float) -> Dictionary:
	var r: Dictionary = environment_sys.report_carbon(_env_enterprise, reported, {"roll": -1.0}, rng)
	_persist_environment()
	return r

func start_env_org(kind: String) -> Dictionary:
	if not _env_org.is_empty():
		return {"ok": false, "reason": "already_org"}
	var r: Dictionary = environment_sys.new_career_org(kind, {"funds": int(economy.cash(account_id()))})
	if not bool(r.get("ok", false)):
		return r
	_env_org = r["org"]
	_persist_environment()
	return {"ok": true, "org": _env_org}

func env_run_project(name: String, budget: int) -> Dictionary:
	if _env_org.is_empty():
		return {"ok": false, "reason": "no_org"}
	var r: Dictionary = environment_sys.run_project(_env_org, name, budget)
	_persist_environment()
	return r

func env_pollute(severity: float) -> Dictionary:
	var r: Dictionary = environment_sys.pollute(_city_env, severity)
	_persist_environment()
	return r

func env_expose_pollution() -> Dictionary:
	var r: Dictionary = environment_sys.expose_pollution(_city_env)
	_persist_environment()
	return r

func env_lawsuit() -> Dictionary:
	var r: Dictionary = environment_sys.environmental_lawsuit(_city_env)
	if bool(r.get("ok", false)) and bool(r.get("liable", false)):
		var compensation: int = int(r.get("compensation", 0))
		if compensation > 0:
			economy.add_money(account_id(), -compensation, "environment_lawsuit")
			r["paid"] = compensation
	_persist_environment()
	return r

func env_green_subsidy(amount: int) -> Dictionary:
	if _env_org.is_empty():
		return {"ok": false, "reason": "no_org"}
	var r: Dictionary = environment_sys.green_subsidy(_env_org, amount)
	_persist_environment()
	return r

func env_low_carbon_transition(investment: int) -> Dictionary:
	if investment <= 0:
		return {"ok": false, "reason": "bad_amount"}
	if int(economy.cash(account_id())) < investment:
		return {"ok": false, "reason": "insufficient_funds", "cost": investment}
	var r: Dictionary = environment_sys.low_carbon_transition(_env_enterprise, investment)
	if bool(r.get("ok", false)):
		economy.add_money(account_id(), -investment, "low_carbon_transition")
	_persist_environment()
	return r

func env_illegal_discharge(amount: float) -> Dictionary:
	var before: int = int(_env_enterprise.get("fines", 0))
	var r: Dictionary = environment_sys.illegal_discharge(_env_enterprise, amount, {"roll": -1.0}, rng)
	var fine: int = maxi(0, int(_env_enterprise.get("fines", 0)) - before)
	if bool(r.get("ok", false)) and fine > 0:
		economy.add_money(account_id(), -fine, "illegal_discharge_fine")
		r["fine_paid"] = fine
	_persist_environment()
	return r

func env_nimby(scale: float) -> Dictionary:
	var r: Dictionary = environment_sys.nimby(_city_env, {}, {"scale": scale, "near_residents": scale})
	_persist_environment()
	return r

func environment_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _city_env.is_empty():
		out["city"] = {
			"garbage_sorting": float(_city_env.get("garbage_sorting", 0.0)),
			"recycling_rate": float(_city_env.get("recycling_rate", 0.0)),
			"sewage_treatment": float(_city_env.get("sewage_treatment", 0.0)),
			"air_quality": float(_city_env.get("air_quality", 0.0)),
			"pollution_index": environment_sys.pollution_index(_city_env),
			"health_index": float(_city_env.get("health_index", 0.0)),
			"reputation": float(_city_env.get("reputation", 0.0)),
			"lawsuit_open": bool(_city_env.get("lawsuit_open", false)),
		}
	if not _env_enterprise.is_empty():
		out["enterprise"] = {
			"name": String(_env_enterprise.get("name", "")),
			"emissions": float(_env_enterprise.get("emissions", 0.0)),
			"quota": float(_env_enterprise.get("quota", 0.0)),
			"credits": float(_env_enterprise.get("credits", 0.0)),
			"balance": environment_sys.carbon_balance(_env_enterprise),
			"esg": float(_env_enterprise.get("esg", 0.0)),
			"fines": int(_env_enterprise.get("fines", 0)),
		}
	if not _env_org.is_empty():
		out["org"] = {
			"kind": String(_env_org.get("kind", "")),
			"name": String(_env_org.get("name", "")),
			"funds": int(_env_org.get("funds", 0)),
			"reputation": float(_env_org.get("reputation", 0.0)),
			"emission_cut": float(_env_org.get("emission_cut", 0.0)),
		}
	return out

func _persist_environment() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["environment"] = {
		"city": environment_sys.to_dict(_city_env),
		"enterprise": environment_sys.to_dict(_env_enterprise),
		"org": _env_org.duplicate(true),
	}



# --- D38 市政公用与邮政 ---

func municipal_state() -> Dictionary:
	return {"city": _city_municipal, "hub": _postal_hub, "courier": _courier, "license": _municipal_license}

func municipal_facilities_catalog() -> Array:
	var out: Array = []
	for t in municipal.facility_types():
		out.append({"id": String(t), "name": municipal.facility_name(String(t))})
	return out

func municipal_franchise_catalog() -> Array:
	var out: Array = []
	for key in municipal.franchise_service_keys():
		var d: Dictionary = municipal.franchise_service_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func municipal_maintain(facility_type: String, amount: int) -> Dictionary:
	var r: Dictionary = municipal.maintain_facility(_city_municipal, facility_type, amount)
	_persist_municipal()
	return r

func municipal_inspect() -> Dictionary:
	var neglected: Array = municipal.inspect_parks(_city_municipal)
	return {"ok": true, "neglected_parks": neglected, "unresolved_complaints": municipal.unresolved_complaints(_city_municipal)}

func municipal_construct(facility_type: String, days: float) -> Dictionary:
	var r: Dictionary = municipal.start_construction(_city_municipal, facility_type, {"days": days})
	_persist_municipal()
	return r

func municipal_advance_construction(days: float) -> Dictionary:
	var r: Dictionary = municipal.advance_construction(_city_municipal, days)
	_persist_municipal()
	return r

func municipal_excavate(facility_type: String) -> Dictionary:
	var r: Dictionary = municipal.start_excavation(_city_municipal, facility_type)
	_persist_municipal()
	return r

func municipal_complain(source: String) -> Dictionary:
	var r: Dictionary = municipal.report_nuisance(_city_municipal, {"source": source})
	_persist_municipal()
	return {"ok": true, "complaint": r, "unresolved_complaints": municipal.unresolved_complaints(_city_municipal)}

func municipal_resolve_complaint(index: int) -> Dictionary:
	var r: Dictionary = municipal.resolve_complaint(_city_municipal, index)
	_persist_municipal()
	return r

func postal_accept(id: String, weight_kg: float, distance_km: float) -> Dictionary:
	var parcel: Dictionary = municipal.new_parcel(id, {"weight_kg": weight_kg, "distance_km": distance_km})
	var r: Dictionary = municipal.accept_parcel(_postal_hub, parcel)
	_persist_municipal()
	return {"ok": true, "pending": int(r.get("pending", 0))}

func postal_ship() -> Dictionary:
	var pending: Array = _postal_hub.get("pending", [])
	if pending.is_empty():
		return {"ok": false, "reason": "no_parcel"}
	var parcel: Dictionary = pending[0]
	var r: Dictionary = municipal.ship(_postal_hub, parcel, {"loss_roll": -1.0, "damage_roll": -1.0}, rng)
	# 记录最近一件已发运包裹，供理赔引用（发运即出队）。
	_postal_hub["last_parcel"] = parcel
	_persist_municipal()
	return r

func postal_claim() -> Dictionary:
	# 取最近发运的包裹（含丢件/破损）。
	var target: Dictionary = _postal_hub.get("last_parcel", {})
	if target.is_empty():
		return {"ok": false, "reason": "no_parcel"}
	var r: Dictionary = municipal.file_claim(_postal_hub, target)
	_persist_municipal()
	return r

func start_courier_career() -> Dictionary:
	if not _courier.is_empty():
		return {"ok": false, "reason": "already_career"}
	_courier = municipal.new_courier("player")
	_persist_municipal()
	return {"ok": true, "courier": _courier}

func courier_deliver() -> Dictionary:
	if _courier.is_empty():
		return {"ok": false, "reason": "no_career"}
	var parcel: Dictionary = municipal.new_parcel("last", {})
	var r: Dictionary = municipal.courier_deliver(_courier, parcel)
	_persist_municipal()
	return r

func municipal_grant_franchise(service: String) -> Dictionary:
	var operator: Dictionary = {"id": account_id(), "license": _municipal_license}
	var r: Dictionary = municipal.grant_franchise(_city_municipal, service, operator)
	if not bool(r.get("ok", false)) and String(r.get("reason", "")) == "unknown_service":
		r["reason"] = "unknown_franchise"
	_persist_municipal()
	return r

## 公用事业月度报表：结算最近一份特许合同，净利回写玩家账户。
func municipal_utility_report(days: float = 30.0) -> Dictionary:
	var franchises: Array = _city_municipal.get("franchises", [])
	if franchises.is_empty():
		return {"ok": false, "reason": "no_franchise"}
	var contract: Dictionary = franchises[franchises.size() - 1]
	var r: Dictionary = municipal.utility_statement(_city_municipal, contract, {"days": days})
	if bool(r.get("ok", false)):
		economy.add_money(account_id(), int(r.get("net", 0)), "utility_operation")
		_persist_municipal()
	return r

func municipal_assess_quality(score: float) -> Dictionary:
	var franchises: Array = _city_municipal.get("franchises", [])
	if franchises.is_empty():
		return {"ok": false, "reason": "no_franchise"}
	var contract: Dictionary = franchises[franchises.size() - 1]
	var r: Dictionary = municipal.assess_service_quality(_city_municipal, contract, score)
	_persist_municipal()
	return r

func municipal_government_purchase(service: String, budget: int) -> Dictionary:
	var r: Dictionary = municipal.government_purchase(_city_municipal, service, budget)
	if not bool(r.get("ok", false)) and String(r.get("reason", "")) == "unknown_service":
		r["reason"] = "unknown_franchise"
	_persist_municipal()
	return r

func municipal_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _city_municipal.is_empty():
		var f_rows: Array = []
		for t in municipal.facility_types():
			f_rows.append({
				"name": municipal.facility_name(String(t)),
				"condition": municipal.facility_condition(_city_municipal, String(t)),
				"grade": municipal.facility_grade(_city_municipal, String(t)),
			})
		out["city"] = {
			"facilities": f_rows,
			"commute_factor": municipal.commute_impact(_city_municipal),
			"nuisance": float(_city_municipal.get("nuisance", 0.0)),
			"unresolved_complaints": municipal.unresolved_complaints(_city_municipal),
			"franchises": (_city_municipal.get("franchises", []) as Array).size(),
		}
	if not _postal_hub.is_empty():
		out["hub"] = {
			"pending": (_postal_hub.get("pending", []) as Array).size(),
			"processed": int(_postal_hub.get("processed", 0)),
			"lost": int(_postal_hub.get("lost", 0)),
			"damaged": int(_postal_hub.get("damaged", 0)),
			"claims_paid": int(_postal_hub.get("claims_paid", 0)),
			"overload": municipal.postal_overload(_postal_hub),
		}
	if not _courier.is_empty():
		out["courier"] = {
			"name": String(_courier.get("name", "")),
			"deliveries": int(_courier.get("deliveries", 0)),
			"rank_index": int(_courier.get("rank_index", 0)),
			"income": int(_courier.get("income", 0)),
			"reputation": float(_courier.get("reputation", 0.0)),
		}
	return out

func _persist_municipal() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["municipal"] = {
		"city": municipal.to_dict(_city_municipal),
		"hub": municipal.to_dict(_postal_hub),
		"courier": _courier.duplicate(true),
		"license": _municipal_license,
	}



# --- D39 债务服务、当铺与小贷 ---

func debt_state() -> Dictionary:
	return {"lender": _debt_lender, "loan": _debt_loan, "lend": _debt_lend, "pawns": _debt_pawns}

func debt_businesses_catalog() -> Array:
	var out: Array = []
	for key in debt.business_keys():
		var d: Dictionary = debt.business_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func debt_collection_modes_catalog() -> Array:
	var out: Array = []
	for key in debt.collection_mode_keys():
		var d: Dictionary = debt.collection_mode_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func _current_year() -> int:
	return int(GregorianScript.from_absolute_minutes(now_minutes()).get("year", 2000))

func debt_pawn(item: String, amount: int, rate: float) -> Dictionary:
	if item.is_empty():
		return {"ok": false, "reason": "no_item"}
	var loan: Dictionary = debt.new_loan("pawn-%d" % Time.get_ticks_msec(), "pawn", amount, {
		"lender": "pawnshop", "borrower": "player", "rate": rate, "collateral": item, "collateral_value": amount,
	})
	_debt_loan = loan
	_debt_pawns.append({"item": item, "amount": amount, "loan": String(loan.get("id", ""))})
	_persist_debt()
	return {"ok": true, "loan": loan}

func debt_redeem() -> Dictionary:
	if _debt_loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	_debt_loan["status"] = "repaid"
	var item: String = String(_debt_loan.get("collateral", ""))
	for i in range(_debt_pawns.size()):
		if String((_debt_pawns[i] as Dictionary).get("loan", "")) == String(_debt_loan.get("id", "")):
			_debt_pawns.remove_at(i)
			break
	var ledger: Dictionary = _debt_loan
	_debt_loan = {}
	_persist_debt()
	return {"ok": true, "item": item, "loan": ledger}

## 登记借款/放贷进休眠补算，逾期利息按年利率折算。
func _wake_track_loan(loan: Dictionary, side: String) -> void:
	var lid: String = String(loan.get("id", ""))
	domain_register("loan:%s" % lid, DomainWakeScript.KIND_LOAN, {
		"region_id": current_region_id(),
		"principal": float(loan.get("principal", 0)),
		"annual_rate": float(loan.get("rate", 0.0)),
		"loan_id": lid,
		"side": side,
	})

## 债务重组/破产后停止补算利息，保留已累计的逾期结果。
func _wake_close_loan(side: String) -> void:
	var loan: Dictionary = _debt_loan if side == "borrow" else _debt_lend
	if loan.is_empty():
		return
	var entry_id: String = "loan:%s" % String(loan.get("id", ""))
	var entry: Dictionary = domain_wake.get_entry(entry_id)
	if entry.is_empty():
		return
	domain_wake.set_progress(entry_id, float(entry.get("progress", 0.0)), "resolved")
	_persist_domain_wake()

func debt_borrow(business: String, principal: int, rate: float, lender_id: String = "market") -> Dictionary:
	if not debt.business_available(business, _current_year()):
		return {"ok": false, "reason": "business_unavailable"}
	var loan: Dictionary = debt.new_loan("loan-%d" % Time.get_ticks_msec(), business, principal, {
		"lender": lender_id, "borrower": "player", "rate": rate,
	})
	var credit: Dictionary = debt.assess_credit(player(), loan)
	if not bool(credit.get("approved", false)):
		return {"ok": true, "approved": false, "credit": credit}
	var disb: Dictionary = debt.disburse(loan, {"license": true})
	_debt_loan = loan
	_debt_loans.append(loan)
	_wake_track_loan(loan, "borrow")
	_persist_debt()
	return {"ok": true, "approved": true, "credit": credit, "disbursement": disb, "loan": loan}

func debt_lend(business: String, principal: int, rate: float) -> Dictionary:
	if not debt.business_available(business, _current_year()):
		return {"ok": false, "reason": "business_unavailable"}
	var loan: Dictionary = debt.new_loan("lend-%d" % Time.get_ticks_msec(), business, principal, {
		"lender": "player", "borrower": "borrower", "rate": rate,
	})
	var reg: Dictionary = debt.regulate(loan, _debt_lender)
	_debt_lend = loan
	_debt_lends.append(loan)
	_wake_track_loan(loan, "lend")
	_persist_debt()
	return {"ok": true, "loan": loan, "regulation": reg}

## 多笔贷款台账：借款人/放贷人两侧的逐笔状态与汇总。
func debt_ledger() -> Dictionary:
	var borrow_rows: Array = []
	var lend_rows: Array = []
	var total_out: int = 0
	var total_in: int = 0
	for l in _debt_loans:
		var loan: Dictionary = l
		borrow_rows.append({"id": String(loan.get("id", "")), "business": String(loan.get("business", "")),
			"lender": String(loan.get("lender", "")), "principal": int(loan.get("principal", 0)),
			"outstanding": int(loan.get("outstanding", 0)), "status": String(loan.get("status", "")),
			"overdue_days": int(loan.get("overdue_days", 0))})
		if String(loan.get("status", "")) == debt.LOAN_ACTIVE:
			total_out += int(loan.get("outstanding", 0))
	for l in _debt_lends:
		var loan: Dictionary = l
		lend_rows.append({"id": String(loan.get("id", "")), "business": String(loan.get("business", "")),
			"borrower": String(loan.get("borrower", "")), "principal": int(loan.get("principal", 0)),
			"outstanding": int(loan.get("outstanding", 0)), "status": String(loan.get("status", ""))})
		if String(loan.get("status", "")) == debt.LOAN_ACTIVE:
			total_in += int(loan.get("outstanding", 0))
	return {"ok": true, "borrow_count": borrow_rows.size(), "lend_count": lend_rows.size(),
		"borrow_outstanding": total_out, "lend_outstanding": total_in,
		"loans": borrow_rows, "lends": lend_rows}

## 跨机构征信报告：汇总多笔借款的机构分布、逾期与违约。
func debt_credit_report() -> Dictionary:
	var loans: Array = _debt_loans.duplicate(true)
	if loans.is_empty() and not _debt_loan.is_empty():
		loans.append(_debt_loan.duplicate(true))
	return debt.credit_report(player(), loans)

## 还款：默认冲减最近一笔在贷借款，可指定台账序号。
func debt_repay(amount: int, index: int = -1) -> Dictionary:
	if _debt_loans.is_empty():
		return {"ok": false, "reason": "no_loan"}
	var idx: int = index
	if idx < 0:
		for i in range(_debt_loans.size() - 1, -1, -1):
			if String((_debt_loans[i] as Dictionary).get("status", "")) == debt.LOAN_ACTIVE:
				idx = i
				break
	if idx < 0 or idx >= _debt_loans.size():
		return {"ok": false, "reason": "no_active_loan"}
	var loan: Dictionary = _debt_loans[idx]
	var due: int = maxi(0, int(loan.get("outstanding", 0)))
	var paid: int = mini(due, maxi(0, amount))
	if paid <= 0:
		return {"ok": false, "reason": "nothing_to_repay"}
	if int(economy.cash(account_id())) < paid:
		return {"ok": false, "reason": "insufficient_funds", "cost": paid}
	economy.add_money(account_id(), -paid, "debt_repay")
	var r: Dictionary = debt.repay_loan(loan, paid)
	_debt_loan = loan
	_persist_debt()
	return r

func debt_assess_credit() -> Dictionary:
	var loan: Dictionary = _debt_loan if not _debt_loan.is_empty() else debt.new_loan("probe", "micro_loan", 500000, {"rate": 0.12})
	return debt.assess_credit(player(), loan)

func debt_collect(mode: String) -> Dictionary:
	if _debt_lend.is_empty():
		return {"ok": false, "reason": "no_lend"}
	var r: Dictionary = debt.collect(_debt_lend, mode, _debt_lender, {}, rng)
	_persist_debt()
	return r

func debt_restructure() -> Dictionary:
	if _debt_loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	var r: Dictionary = debt.restructure(_debt_loan, {})
	_persist_debt()
	if bool(r.get("ok", false)):
		_wake_close_loan("borrow")
	return r

func debt_bankruptcy() -> Dictionary:
	if _debt_loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	var loans: Array = [_debt_loan]
	var p: Dictionary = player()
	var r: Dictionary = debt.personal_bankruptcy(p, loans, _current_year())
	if bool(r.get("ok", false)):
		_debt_loan = loans[0]
		_persist_debt()
		_wake_close_loan("borrow")
	return r

func debt_predatory(amount: int) -> Dictionary:
	var loan: Dictionary = _debt_loan if not _debt_loan.is_empty() else debt.new_loan("predatory", "private_lending", amount, {"rate": 0.5, "cut_interest": int(amount * 0.1), "service_fee": int(amount * 0.1)})
	var r: Dictionary = debt.predatory_loan(loan, {"inflated_debt": amount})
	_debt_loan = loan
	_persist_debt()
	return r

func debt_illegal_fundraising(amount: int) -> Dictionary:
	var r: Dictionary = debt.illegal_fundraising(_debt_lender, amount, {})
	_persist_debt()
	return r

func debt_abscond() -> Dictionary:
	if _debt_loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	var r: Dictionary = debt.abscond(_debt_loan, {}, rng)
	_persist_debt()
	return r

func debt_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _debt_loan.is_empty():
		out["loan"] = {
			"business": String(_debt_loan.get("business", "")),
			"principal": int(_debt_loan.get("principal", 0)),
			"outstanding": int(_debt_loan.get("outstanding", 0)),
			"rate": float(_debt_loan.get("rate", 0.0)),
			"status": String(_debt_loan.get("status", "")),
			"predatory": bool(_debt_loan.get("predatory", false)),
			"compliant": bool(_debt_loan.get("compliant", true)),
		}
	if not _debt_lend.is_empty():
		var comp: Dictionary = debt.compliance_status(_debt_lend, _debt_lender)
		out["lend"] = {
			"business": String(_debt_lend.get("business", "")),
			"principal": int(_debt_lend.get("principal", 0)),
			"outstanding": int(_debt_lend.get("outstanding", 0)),
			"rate": float(_debt_lend.get("rate", 0.0)),
			"status": String(_debt_lend.get("status", "")),
			"compliant": bool(comp.get("compliant", true)),
			"illegal_collection": bool(_debt_lend.get("illegal_collection", false)),
			"modes": (_debt_lend.get("collection_modes", []) as Array).size(),
		}
	out["lender"] = {
		"license": bool(_debt_lender.get("license", false)),
		"violations": int(_debt_lender.get("violations", 0)),
		"reputation": float(_debt_lender.get("reputation", 0.0)),
	}
	out["pawns"] = _debt_pawns.duplicate(true)
	out["ledger"] = debt_ledger()
	out["credit_report"] = debt_credit_report()
	return out

func _persist_debt() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["debt"] = {
		"lender": debt.to_dict(_debt_lender),
		"loan": debt.to_dict(_debt_loan),
		"lend": debt.to_dict(_debt_lend),
		"loans": _debt_loans.duplicate(true),
		"lends": _debt_lends.duplicate(true),
		"pawns": _debt_pawns.duplicate(true),
	}



# --- D40 消费者保护与产品质量 ---

func consumer_state() -> Dictionary:
	return {"order": _consumer_order, "product": _consumer_product, "merchant": _consumer_merchant}

func consumer_channels_catalog() -> Array:
	var names: Dictionary = consumer.channel_names()
	var out: Array = []
	for key in consumer.channel_keys():
		out.append({"id": String(key), "name": String(names.get(key, key))})
	return out

func consumer_incident_kinds_catalog() -> Array:
	var out: Array = []
	for key in consumer.incident_kinds():
		out.append({"id": String(key), "name": "食品安全事故" if String(key) == "food_safety" else "质量事故"})
	return out

func consumer_new_order(amount: int, category: String, defective: bool, fake: bool) -> Dictionary:
	_consumer_order = consumer.new_order("order-%d" % Time.get_ticks_msec(), "merchant", amount, {
		"category": category, "defective": defective, "fake": fake,
	})
	_persist_consumer()
	return {"ok": true, "order": _consumer_order}

func consumer_new_product(price: int, warranty_days: int) -> Dictionary:
	_consumer_product = consumer.new_product("商品", {"merchant": "merchant", "price": price, "warranty_days": warranty_days})
	_persist_consumer()
	return {"ok": true, "product": _consumer_product}

func consumer_return(days_since: int, reason: String) -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	var r: Dictionary = consumer.request_return(_consumer_order, days_since, reason)
	_persist_consumer()
	return r

func consumer_three_guarantee(repairs: int) -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	var r: Dictionary = consumer.three_guarantee(_consumer_order, repairs)
	_persist_consumer()
	return r

func consumer_warranty(days_used: int) -> Dictionary:
	if _consumer_product.is_empty():
		return {"ok": false, "reason": "no_product"}
	return consumer.warranty_claim(_consumer_product, days_used)

func consumer_burden(days_since: int) -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	return consumer.burden_of_proof(_consumer_order, days_since)

func consumer_dispute(channel: String, evidence: float) -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	if channel == "platform":
		consumer.file_complaint(_consumer_order, "platform", {"evidence": evidence})
	var r: Dictionary = consumer.resolve_dispute(_consumer_order, _consumer_merchant, {"channel": channel, "evidence": evidence}, rng)
	_persist_consumer()
	return r

## 12315 热线投诉：生成受理案号与办理时限，恶意投诉标记商家反诉风险。
func consumer_12315(evidence: float, malicious: bool = false) -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	var cases: Array = _consumer_order.get("hotline_cases", [])
	var r: Dictionary = consumer.hotline_12315(_consumer_order, {"evidence": evidence, "sequence": cases.size() + 1, "malicious": malicious})
	if bool(r.get("ok", false)):
		cases.append((r.get("record", {}) as Dictionary).duplicate(true))
		_consumer_order["hotline_cases"] = cases
		_persist_consumer()
	return r

func consumer_class_action(evidence: float) -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	var r: Dictionary = consumer.class_action([_consumer_order], _consumer_merchant, {}, rng)
	_persist_consumer()
	return r

func consumer_incident(kind: String, severity: float, victims: int) -> Dictionary:
	var r: Dictionary = consumer.regulate_incident(_consumer_merchant, kind, {"severity": severity, "victims": victims})
	if kind == "food_safety" and not _restaurant.is_empty():
		var dr: Dictionary = dining.food_safety_incident(_restaurant, "contamination", severity, {"recall_qty": float(maxi(1, victims))})
		if bool(dr.get("ok", false)):
			r["restaurant_incident"] = (dr.get("incident", {}) as Dictionary).duplicate(true)
			_persist_dining()
	_persist_consumer()
	return r

func consumer_recall(affected: int) -> Dictionary:
	if _consumer_product.is_empty():
		_consumer_product = consumer.new_product("商品", {"merchant": "merchant"})
	var r: Dictionary = consumer.recall(_consumer_product, affected)
	_persist_consumer()
	return r

func consumer_professional_fraud() -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	return consumer.professional_fraud(_consumer_order)

func consumer_malicious_claim() -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	return consumer.malicious_claim(_consumer_order, _consumer_merchant, {}, rng)

func consumer_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _consumer_order.is_empty():
		out["order"] = {
			"amount": int(_consumer_order.get("amount", 0)),
			"category": String(_consumer_order.get("category", "general")),
			"defective": bool(_consumer_order.get("defective", false)),
			"fake": bool(_consumer_order.get("fake", false)),
			"status": String(_consumer_order.get("status", "")),
			"refunded": int(_consumer_order.get("refunded", 0)),
			"complaints": (_consumer_order.get("complaints", []) as Array).size(),
		}
	if not _consumer_product.is_empty():
		out["product"] = {
			"name": String(_consumer_product.get("name", "")),
			"price": int(_consumer_product.get("price", 0)),
			"warranty_days": int(_consumer_product.get("warranty_days", 0)),
			"recalled": bool(_consumer_product.get("recalled", false)),
		}
	out["merchant"] = {
		"name": String(_consumer_merchant.get("name", "")),
		"reputation": float(_consumer_merchant.get("reputation", 0.0)),
		"sales": float(_consumer_merchant.get("sales", 0.0)),
		"fines": int(_consumer_merchant.get("fines", 0)),
		"compensation_paid": int(_consumer_merchant.get("compensation_paid", 0)),
		"delisted": bool(_consumer_merchant.get("delisted", false)),
	}
	return out

func _persist_consumer() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["consumer"] = {
		"order": consumer.to_dict(_consumer_order),
		"product": consumer.to_dict(_consumer_product),
		"merchant": _consumer_merchant.duplicate(true),
	}


# --- 民事纠纷与诉讼（D12 / R52） ---

func civil_state() -> Dictionary:
	return _civil.duplicate(true)

## 消费维权起诉：以订单金额（缺陷/假货三倍）立案，并登记审限补算。
func consumer_sue(evidence: float = 0.5) -> Dictionary:
	if _consumer_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	if not (_civil.get("claim", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "existing_claim"}
	var amount: int = int(_consumer_order.get("amount", 0))
	if bool(_consumer_order.get("defective", false)) or bool(_consumer_order.get("fake", false)):
		amount *= 3
	var claim: Dictionary = civil_sys.new_claim("consumer", amount, "player", "merchant")
	claim["evidence"] = clampf(evidence, 0.0, 1.0)
	_civil = {"claim": claim, "judgment": {}, "enforced": false, "appealed": false}
	var cid: String = "civil:%d:%d" % [now_minutes(), domain_wake.entry_count()]
	var due: int = now_minutes() + BaselineScript.WAKE_CASE_LIMIT_DAYS * BaselineScript.WAKE_MINUTES_PER_DAY
	domain_register(cid, DomainWakeScript.KIND_CASE, {
		"region_id": current_region_id(), "due_minute": due, "total": due - now_minutes(), "civil_id": cid,
	})
	_persist_civil()
	return {"ok": true, "claim": claim, "case_id": cid}

## 开庭审理：证据强度、双方律师能力决定胜率与判赔。
func civil_litigate(evidence: float = -1.0, lawyer_level: int = 0, opponent_lawyer: int = 1, forced_roll: float = -1.0) -> Dictionary:
	var claim: Dictionary = _civil.get("claim", {})
	if claim.is_empty():
		return {"ok": false, "reason": "no_claim"}
	var ev: float = float(claim.get("evidence", 0.5)) if evidence < 0.0 else clampf(evidence, 0.0, 1.0)
	var judgment: Dictionary = civil_sys.litigate(claim, ev, lawyer_level, opponent_lawyer, rng, {"roll": forced_roll})
	var compensation: int = 0
	if bool(judgment.get("won", false)):
		compensation = int(judgment.get("award", 0))
		if String(claim.get("type", "")) == "consumer":
			_consumer_merchant["compensation_paid"] = int(_consumer_merchant.get("compensation_paid", 0)) + compensation
			_consumer_merchant["reputation"] = clampf(float(_consumer_merchant.get("reputation", 0.5)) - 0.2, 0.0, 1.0)
			_persist_consumer()
	_civil["judgment"] = judgment
	_persist_civil()
	return {"ok": true, "judgment": judgment, "compensation": compensation}

## 上诉：败诉后有一定概率改判，改判差额补入现金。
func civil_appeal(lawyer_level: int = 0) -> Dictionary:
	var claim: Dictionary = _civil.get("claim", {})
	var judgment: Dictionary = _civil.get("judgment", {})
	if claim.is_empty() or judgment.is_empty():
		return {"ok": false, "reason": "no_judgment"}
	if bool(_civil.get("appealed", false)):
		return {"ok": false, "reason": "already_appealed"}
	var before: int = int(judgment.get("award", 0))
	var r: Dictionary = civil_sys.appeal(claim, judgment, lawyer_level, rng)
	var after: int = int(r.get("award", before))
	judgment["award"] = after
	_civil["judgment"] = judgment
	_civil["appealed"] = true
	_persist_civil()
	return {"ok": true, "overturned": bool(r.get("overturned", false)), "award": after, "delta": maxi(0, after - before)}

## 执行判决：胜诉判赔入账，仅可执行一次。
func civil_enforce() -> Dictionary:
	var judgment: Dictionary = _civil.get("judgment", {})
	if judgment.is_empty():
		return {"ok": false, "reason": "no_judgment"}
	if bool(_civil.get("enforced", false)):
		return {"ok": false, "reason": "already_enforced"}
	var award: int = int(judgment.get("award", 0))
	var r: Dictionary = civil_sys.enforce(judgment, award)
	var recovered: int = int(r.get("recovered", 0))
	if recovered > 0:
		economy.add_money(account_id(), recovered, "civil_enforcement")
	_civil["enforced"] = true
	_persist_civil()
	return {"ok": true, "recovered": recovered, "execution_failure": bool(r.get("execution_failure", false)), "outstanding": int(r.get("outstanding", 0))}

func civil_panel_data() -> Dictionary:
	if _civil.is_empty():
		return {}
	var claim: Dictionary = _civil.get("claim", {})
	if claim.is_empty():
		return {}
	var out: Dictionary = {
		"claim": {
			"type": String(claim.get("type", "")),
			"type_name": String(claim.get("type_name", civil_sys.TYPE_NAMES.get(String(claim.get("type", "")), claim.get("type", "")))),
			"amount": int(claim.get("amount", 0)),
			"stage": String(claim.get("stage", "")),
			"won": bool(claim.get("won", false)),
			"settled": bool(claim.get("settled", false)),
			"evidence": float(claim.get("evidence", 0.0)),
		},
		"enforced": bool(_civil.get("enforced", false)),
		"appealed": bool(_civil.get("appealed", false)),
	}
	var judgment: Dictionary = _civil.get("judgment", {})
	if not judgment.is_empty():
		out["judgment"] = {
			"won": bool(judgment.get("won", false)),
			"award": int(judgment.get("award", 0)),
			"cost": int(judgment.get("cost", 0)),
			"probability": float(judgment.get("probability", 0.0)),
		}
	return out

func _persist_civil() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["civil"] = _civil.duplicate(true)


# --- D12 犯罪、通缉与监狱 ---

func _crime_new_state() -> Dictionary:
	return {"records": [], "wanted": {}, "surrendered": false, "surrender_case": {}, "fled": false, "aliases": 0, "last": {}}


func _ensure_crime_state() -> void:
	if _crime_state.is_empty():
		_crime_state = _crime_new_state()


func crime_state() -> Dictionary:
	_ensure_crime_state()
	return _crime_state.duplicate(true)


## 实施犯罪：按犯罪技能树判定成败与是否暴露，暴露即立案底并通缉。
func crime_attempt(crime: String) -> Dictionary:
	if is_dead():
		return {"ok": false, "reason": "dead"}
	if _prison_active():
		return {"ok": false, "reason": "in_prison"}
	if not CrimeScript.CRIMES.has(crime):
		return {"ok": false, "reason": "unknown_crime"}
	_ensure_crime_state()
	var c: Dictionary = CrimeScript.CRIMES[crime]
	var skill_id: String = String(CRIME_SKILLS.get(crime, "crime_disguise"))
	var skill: float = float(_skill_level(skill_id))
	var r: Dictionary = crime_sys.attempt(crime, skill, rng, {})
	var region: String = current_region_id()
	if bool(r.get("detected", false)):
		var level: int = clampi(1 + int(float(c.get("difficulty", 0.0)) / 4.0), 1, 5)
		var rec: Dictionary = crime_sys.add_record(_crime_state, crime, region, now_minutes(), clampf(0.4 + skill / 40.0, 0.3, 0.95))
		crime_sys.add_wanted(_crime_state, crime, region, level)
		_crime_state["surrendered"] = false
		_crime_state["surrender_case"] = {}
		_crime_state["last"] = {"crime": crime, "detected": true, "record": rec}
	else:
		_crime_state["last"] = {"crime": crime, "detected": false}
	_persist_crime()
	_sync_legal()
	return {
		"ok": true, "crime": crime, "name": String(c.get("name", crime)),
		"success": bool(r.get("success", false)), "detected": bool(r.get("detected", false)),
		"probability": float(r.get("probability", 0.0)), "wanted_level": crime_sys.wanted_level(_crime_state, region),
	}


## 刑事受审：按案底证据与通缉等级定罪量刑，刑期入监、罚金从现金扣除。
func crime_trial() -> Dictionary:
	if _prison_active():
		return {"ok": false, "reason": "in_prison"}
	_ensure_crime_state()
	var wanted: Dictionary = _crime_state.get("wanted", {})
	var surrender_case: Dictionary = _crime_state.get("surrender_case", {})
	if wanted.is_empty() and surrender_case.is_empty():
		return {"ok": false, "reason": "not_wanted"}
	var region: String = current_region_id()
	var entry: Dictionary = {}
	if not wanted.is_empty():
		if not wanted.has(region):
			region = String((wanted.keys() as Array)[0])
		entry = wanted.get(region, {})
	else:
		region = String(surrender_case.get("region", region))
		entry = surrender_case
	var crime: String = String(entry.get("crime", ""))
	var c: Dictionary = CrimeScript.CRIMES.get(crime, {})
	if c.is_empty():
		wanted.erase(region)
		_crime_state["wanted"] = wanted
		_persist_crime()
		_sync_legal()
		return {"ok": false, "reason": "unknown_crime"}
	var records: Array = _crime_state.get("records", [])
	var evidence: float = clampf(0.5 + float(records.size()) * 0.05 + float(entry.get("level", 1)) * 0.05, 0.3, 0.95)
	var discount: float = 0.3 if bool(_crime_state.get("surrendered", false)) else 1.0
	if rng.next_float() >= evidence:
		wanted.erase(region)
		_crime_state["wanted"] = wanted
		_crime_state["surrendered"] = false
		_persist_crime()
		_sync_legal()
		return {"ok": true, "convicted": false, "acquitted": true, "crime": crime, "evidence": evidence}
	var penalty: Dictionary = c.get("penalty", {})
	var days_range: Array = penalty.get("days", [0, 0])
	var fine_range: Array = penalty.get("fine", [0, 0])
	var low_days: int = int(days_range[0]) if days_range.size() > 0 else 0
	var high_days: int = int(days_range[1]) if days_range.size() > 1 else low_days
	var low_fine: int = int(fine_range[0]) if fine_range.size() > 0 else 0
	var high_fine: int = int(fine_range[1]) if fine_range.size() > 1 else low_fine
	var days: int = 0
	if high_days > 0:
		days = maxi(1, int(round(lerpf(float(low_days), float(high_days), rng.next_float()) * discount)))
	var fine: int = 0
	if high_fine > 0:
		fine = maxi(0, int(round(lerpf(float(low_fine), float(high_fine), rng.next_float()) * discount)))
	fine = mini(fine, economy.cash(account_id()))
	if fine > 0:
		economy.add_money(account_id(), -fine, "crime_fine")
		sync_finances()
	wanted.erase(region)
	_crime_state["wanted"] = wanted
	_crime_state["surrendered"] = false
	_crime_state["surrender_case"] = {}
	_crime_state["last"] = {"crime": crime, "convicted": true, "days": days, "fine": fine}
	_crime_state["last_judgment"] = {
		"crime": crime, "region": region, "days": days, "fine": fine,
		"evidence": evidence, "minute": now_minutes(), "appealed": false,
	}
	if days > 0:
		_prison = prison_sys.new_inmate(String(player().get("name", "我")), crime, days)
		_prison["convicted_minute"] = now_minutes()
		_prison_last_day = now_minutes() / MINUTES_PER_DAY
		_persist_prison()
	_persist_crime()
	_sync_legal()
	return {"ok": true, "convicted": true, "crime": crime, "name": String(c.get("name", crime)), "days": days, "fine": fine, "evidence": evidence, "lawyer_discount": discount}


## 刑事上诉：对已生效判决在 10 日内申请二审；改判无罪则退罚金并释放。
func crime_appeal() -> Dictionary:
	_ensure_crime_state()
	var judgment: Dictionary = _crime_state.get("last_judgment", {})
	if judgment.is_empty():
		return {"ok": false, "reason": "no_judgment"}
	if bool(judgment.get("appealed", false)):
		return {"ok": false, "reason": "already_appealed"}
	if now_minutes() - int(judgment.get("minute", 0)) > 10 * MINUTES_PER_DAY:
		return {"ok": false, "reason": "appeal_expired"}
	var evidence: float = clampf(float(judgment.get("evidence", 0.6)), 0.0, 1.0)
	var chance: float = clampf(0.5 - evidence * 0.4, 0.1, 0.4)
	if rng.next_float() >= chance:
		judgment["appealed"] = true
		judgment["outcome"] = "upheld"
		_crime_state["last_judgment"] = judgment
		_persist_crime()
		_sync_legal()
		return {"ok": true, "acquitted": false, "upheld": true, "chance": chance}
	var fine: int = maxi(0, int(judgment.get("fine", 0)))
	if fine > 0:
		economy.add_money(account_id(), fine, "crime_appeal_refund")
		sync_finances()
	var crime: String = String(judgment.get("crime", ""))
	var kept: Array = []
	var removed: bool = false
	for rec in (_crime_state.get("records", []) as Array):
		if not removed and rec is Dictionary and String((rec as Dictionary).get("crime", "")) == crime:
			removed = true
			continue
		kept.append(rec)
	_crime_state["records"] = kept
	if not _prison.is_empty() and not bool(_prison.get("released", false)):
		_prison["released"] = true
		_prison["released_minute"] = now_minutes()
		_prison["days_remaining"] = 0
		_persist_prison()
	judgment["appealed"] = true
	judgment["outcome"] = "acquitted"
	_crime_state["last_judgment"] = judgment
	_crime_state["last"] = {"crime": crime, "convicted": false, "days": 0, "fine": 0, "appealed": true}
	_persist_crime()
	_sync_legal()
	return {"ok": true, "acquitted": true, "upheld": false, "refund": fine, "chance": chance}

## 自首：撤销当前区域通缉并获得量刑折扣。
func crime_self_surrender() -> Dictionary:
	_ensure_crime_state()
	var wanted: Dictionary = _crime_state.get("wanted", {})
	if wanted.is_empty():
		return {"ok": false, "reason": "not_wanted"}
	var region: String = current_region_id()
	if not wanted.has(region):
		region = String((wanted.keys() as Array)[0])
	var r: Dictionary = crime_sys.self_surrender(_crime_state, region)
	if bool(r.get("ok", false)):
		_crime_state["surrender_case"] = {"crime": String(r.get("crime", "")), "region": region, "level": 1}
	_persist_crime()
	_sync_legal()
	return r


## 潜逃：转移通缉并实际迁往目标区域。
func crime_flee(region: String) -> Dictionary:
	if _prison_active():
		return {"ok": false, "reason": "in_prison"}
	if region.is_empty() or (geo != null and geo.count() > 0 and not geo.has_node(region)):
		return {"ok": false, "reason": "unknown_region"}
	_ensure_crime_state()
	var from_region: String = current_region_id()
	var r: Dictionary = crime_sys.flee(_crime_state, from_region, region)
	if not set_home_region(region):
		return {"ok": false, "reason": "unknown_region"}
	_crime_state["fled"] = true
	_persist_crime()
	_sync_legal()
	return r


## 化名：降低追缉强度，不改动真实身份档案。
func crime_change_identity() -> Dictionary:
	_ensure_crime_state()
	var r: Dictionary = crime_sys.change_name(_crime_state)
	_persist_crime()
	_sync_legal()
	return r


## 司法行贿：付款撤销通缉，但可能被查处并加罪。
func crime_bribe(amount_minor: int) -> Dictionary:
	if _prison_active():
		return {"ok": false, "reason": "in_prison"}
	_ensure_crime_state()
	if (_crime_state.get("wanted", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "not_wanted"}
	var paid: int = mini(maxi(0, amount_minor), economy.cash(account_id()))
	if paid <= 0:
		return {"ok": false, "reason": "insufficient_cash"}
	economy.add_money(account_id(), -paid, "crime_bribe")
	sync_finances()
	var r: Dictionary = crime_sys.bribe(0.4, float(paid), rng)
	if bool(r.get("success", false)):
		_crime_state["wanted"] = {}
		_crime_state["surrendered"] = false
	if bool(r.get("exposed", false)):
		crime_sys.add_record(_crime_state, "bribery", current_region_id(), now_minutes(), 0.8)
		crime_sys.add_wanted(_crime_state, "bribery", current_region_id(), 3)
	_persist_crime()
	_sync_legal()
	return {"ok": true, "success": bool(r.get("success", false)), "exposed": bool(r.get("exposed", false)), "paid": paid}


func _prison_active() -> bool:
	if _prison.is_empty():
		return false
	return not bool(_prison.get("released", false)) and not bool(_prison.get("escaped", false))


func prison_state() -> Dictionary:
	return _prison.duplicate(true)


## 监狱劳动：提升表现并发放少量报酬。
func prison_labor(hours: float) -> Dictionary:
	if not _prison_active():
		return {"ok": false, "reason": "not_inside"}
	var r: Dictionary = prison_sys.labor(_prison, maxf(0.0, hours), 500)
	if bool(r.get("ok", false)):
		economy.add_money(account_id(), int(r.get("income", 0)), "prison_labor")
		sync_finances()
	_persist_prison()
	return r


func prison_visit(visitor: String) -> Dictionary:
	if not _prison_active():
		return {"ok": false, "reason": "not_inside"}
	var r: Dictionary = prison_sys.visit(_prison, visitor if visitor != "" else "家人")
	_persist_prison()
	return r


func prison_interact() -> Dictionary:
	if not _prison_active():
		return {"ok": false, "reason": "not_inside"}
	var r: Dictionary = prison_sys.interact(_prison, {"name": "狱友"}, rng)
	_persist_prison()
	return r


func prison_join_gang(gang: String) -> Dictionary:
	if not _prison_active():
		return {"ok": false, "reason": "not_inside"}
	var r: Dictionary = prison_sys.join_gang(_prison, gang)
	_persist_prison()
	return r


func prison_violation() -> Dictionary:
	if not _prison_active():
		return {"ok": false, "reason": "not_inside"}
	var r: Dictionary = prison_sys.violation(_prison)
	_persist_prison()
	return r


func prison_reduce_sentence(days: int) -> Dictionary:
	if not _prison_active():
		return {"ok": false, "reason": "not_inside"}
	var r: Dictionary = prison_sys.reduce_sentence(_prison, maxi(0, days))
	if bool(r.get("ok", false)):
		_sync_legal()
		_persist_prison()
	return r


func prison_parole() -> Dictionary:
	if not _prison_active():
		return {"ok": false, "reason": "not_inside"}
	var total: float = float(maxi(1, int(_prison.get("sentence_days", 1))))
	var served: float = clampf(1.0 - float(_prison.get("days_remaining", 0)) / total, 0.0, 1.0)
	var r: Dictionary = prison_sys.parole(_prison, served, rng)
	if bool(r.get("granted", false)):
		_prison["released_minute"] = now_minutes()
		_sync_legal()
		_persist_prison()
	return r


func prison_escape() -> Dictionary:
	if not _prison_active():
		return {"ok": false, "reason": "not_inside"}
	var skill: float = float(_skill_level("crime_disguise"))
	var r: Dictionary = prison_sys.attempt_escape(_prison, skill, rng)
	if bool(r.get("escaped", false)):
		_ensure_crime_state()
		crime_sys.add_wanted(_crime_state, String(_prison.get("crime", "theft")), current_region_id(), 4)
		_prison["escaped_minute"] = now_minutes()
		_persist_crime()
	_sync_legal()
	_persist_prison()
	return r


## 出狱融入：支持度越高，就业歧视与再犯风险越低。
func prison_reintegrate(support: float = 30.0) -> Dictionary:
	if _prison.is_empty() or _prison_active():
		return {"ok": false, "reason": "still_inside"}
	var r: Dictionary = prison_sys.reintegrate(_prison, clampf(support, 0.0, 100.0), rng)
	r["ok"] = true
	_prison["reintegration"] = r.duplicate(true)
	_sync_legal()
	_persist_prison()
	return r


func _prison_tick(before_minutes: int, after_minutes: int) -> void:
	if not _prison_active():
		return
	var day: int = after_minutes / MINUTES_PER_DAY
	if _prison_last_day < 0:
		_prison_last_day = before_minutes / MINUTES_PER_DAY
	var days: int = day - _prison_last_day
	if days <= 0:
		return
	_prison_last_day = day
	var r: Dictionary = prison_sys.advance(_prison, days)
	if bool(r.get("released", false)):
		_prison["released_minute"] = after_minutes
	_sync_legal()
	_persist_prison()


## 犯罪与监狱面板数据（供法律面板展示通缉、案底、在押与融入）。
func law_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _crime_state.is_empty():
		var records: Array = []
		for rec in (_crime_state.get("records", []) as Array):
			if rec is Dictionary:
				var rd: Dictionary = rec
				var cid: String = String(rd.get("crime", ""))
				records.append({
					"crime": cid,
					"name": String((CrimeScript.CRIMES.get(cid, {}) as Dictionary).get("name", cid)),
					"region": String(rd.get("region", "")),
					"minute": int(rd.get("minute", 0)),
					"evidence": float(rd.get("evidence", 0.0)),
				})
		var wanted: Array = []
		for region in (_crime_state.get("wanted", {}) as Dictionary).keys():
			var entry: Dictionary = (_crime_state.get("wanted", {}) as Dictionary)[region]
			var wid: String = String(entry.get("crime", ""))
			wanted.append({
				"region": String(region),
				"crime": wid,
				"name": String((CrimeScript.CRIMES.get(wid, {}) as Dictionary).get("name", wid)),
				"level": int(entry.get("level", 1)),
			})
		if not records.is_empty() or not wanted.is_empty():
			out["crime"] = {
				"records": records, "wanted": wanted,
				"aliases": int(_crime_state.get("aliases", 0)),
				"surrendered": bool(_crime_state.get("surrendered", false)),
				"fled": bool(_crime_state.get("fled", false)),
			}
	if not _prison.is_empty():
		out["prison"] = {
			"crime": String(_prison.get("crime", "")),
			"name": String((CrimeScript.CRIMES.get(String(_prison.get("crime", "")), {}) as Dictionary).get("name", _prison.get("crime", ""))),
			"sentence_days": int(_prison.get("sentence_days", 0)),
			"days_remaining": int(_prison.get("days_remaining", 0)),
			"behavior": float(_prison.get("behavior", 50.0)),
			"reduction": int(_prison.get("reduction", 0)),
			"violations": int(_prison.get("violations", 0)),
			"gang": String(_prison.get("gang", "none")),
			"gang_name": String(PrisonScript.GANG_NAMES.get(String(_prison.get("gang", "none")), "中立")),
			"active": _prison_active(),
			"escaped": bool(_prison.get("escaped", false)),
			"released": bool(_prison.get("released", false)),
			"parole": bool(_prison.get("parole", false)),
			"reintegration": (_prison.get("reintegration", {}) as Dictionary).duplicate(true),
		}
	return out


## 把犯罪/监狱运行态同步到 player.legal（展示与外部系统消费）。
func _sync_legal() -> void:
	if state == null:
		return
	var legal: Dictionary = player().get("legal", {})
	if not (legal is Dictionary):
		legal = {}
	var records: Array = _crime_state.get("records", [])
	var wanted_level: int = 0
	for region in (_crime_state.get("wanted", {}) as Dictionary).keys():
		wanted_level = maxi(wanted_level, int((_crime_state["wanted"] as Dictionary)[region].get("level", 1)))
	legal["wanted_level"] = wanted_level
	legal["criminal_record"] = not records.is_empty()
	legal["record_entries"] = records.duplicate(true)
	var active: bool = _prison_active()
	legal["in_prison"] = active
	if active:
		legal["release_minutes"] = now_minutes() + int(_prison.get("days_remaining", 0)) * MINUTES_PER_DAY
	else:
		legal.erase("release_minutes")
	var effects: Dictionary = crime_sys.record_effects(_crime_state)
	var extra_emp: float = 0.0
	var extra_soc: float = 0.0
	var reintegration: Dictionary = _prison.get("reintegration", {})
	if not reintegration.is_empty():
		extra_emp = float(reintegration.get("employment_discrimination", 0.0)) * 100.0
		extra_soc = extra_emp * 0.5
	legal["employment_penalty"] = clampf(float(effects.get("employment_penalty", 0.0)) + extra_emp, 0.0, 100.0)
	legal["social_penalty"] = clampf(float(effects.get("social_penalty", 0.0)) + extra_soc, 0.0, 100.0)
	player()["legal"] = legal


func _persist_crime() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["crime"] = _crime_state.duplicate(true)


func _persist_prison() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["prison"] = _prison.duplicate(true)


# --- D7 军旅、职场与融资 ---

## 入伍：校验年龄/健康/学历/政审/兵种技能，成功后军籍写入 player.military。
func military_enlist(branch: String) -> Dictionary:
	var r: Dictionary = military_sys.enlist(player(), branch, now_minutes())
	if bool(r.get("ok", false)):
		sync_finances()
	return r


func military_train(days: float) -> Dictionary:
	return military_sys.train(player(), days)


func military_mission(difficulty: float = 1.0) -> Dictionary:
	return military_sys.mission(player(), rng, {"difficulty": difficulty})


func military_promote() -> Dictionary:
	return military_sys.promote(player(), now_minutes())


func military_discharge() -> Dictionary:
	var r: Dictionary = military_sys.discharge(player(), now_minutes())
	if bool(r.get("ok", false)):
		var severance: int = int(r.get("severance", 0))
		if severance > 0:
			economy.issue_money(account_id(), severance, "military_severance")
			sync_finances()
	return r


func military_desert() -> Dictionary:
	return military_sys.desert(player(), now_minutes())


func military_restricts(verb: String) -> bool:
	return military_sys.restricts_civil(player(), verb)


func military_panel_data() -> Dictionary:
	var state: Dictionary = military_sys.military_state(player())
	if state.is_empty():
		return {"enlisted": false, "branches": military_sys.BRANCHES.duplicate(true)}
	var idx: int = int(state.get("rank_index", 0))
	var current: Dictionary = military_sys.rank(idx)
	var next: Dictionary = military_sys.rank(idx + 1)
	var out: Dictionary = {
		"enlisted": true,
		"status": String(state.get("status", "")),
		"branch": String(state.get("branch", "")),
		"branch_name": String(state.get("branch_name", "")),
		"rank_name": String(current.get("name", "")),
		"rank_grade": String(current.get("grade", "")),
		"merits": float(state.get("merits", 0.0)),
		"casualties": int(state.get("casualties", 0)),
		"pay": military_sys.monthly_pay(player()),
		"restricted_verbs": military_sys.restricted_verbs(player()),
	}
	if not next.is_empty():
		out["next_rank_name"] = String(next.get("name", ""))
		out["next_merit_required"] = float(next.get("merit_required", 0.0))
	out["eligible"] = military_sys.evaluate_promotion(player(), now_minutes())
	return out


## 军旅薪酬按月发放（外部财政注入）。
func _military_tick(before_minutes: int, after_minutes: int) -> void:
	if not military_sys.is_serving(player()):
		return
	var months: int = _month_ordinal(after_minutes) - _month_ordinal(before_minutes)
	if months <= 0:
		return
	var pay: int = military_sys.monthly_pay(player()) * months
	if pay > 0:
		economy.issue_money(account_id(), pay, "military_pay")
		sync_finances()


## 惰性建立职场状态；从当前岗位同步绩效与声望。
func _ensure_workplace() -> void:
	var job: Dictionary = jobs.current_job(player())
	if job.is_empty():
		return
	var company_id: String = String(job.get("content_key", job.get("industry", "company")))
	if _workplace.is_empty() or String(_workplace.get("company_id", "")) != company_id:
		var colleagues: Array = []
		for npc in _acquaintances.slice(0, 3):
			colleagues.append(String((npc as Dictionary).get("id", "")))
		var supervisor: String = String((_acquaintances[0] as Dictionary).get("id", "boss")) if not _acquaintances.is_empty() else "boss"
		_workplace = workplace_sys.init_workplace(company_id, supervisor, colleagues)
		workplace_sys.add_faction(_workplace, "reform", "改革派", 35.0, "reform")
		workplace_sys.add_faction(_workplace, "status_quo", "保守派", 40.0, "conservative")
	_workplace["performance"] = float(job.get("performance", _workplace.get("performance", 50.0)))
	_workplace["internal_reputation"] = float(job.get("internal_reputation", _workplace.get("internal_reputation", 50.0)))


func workplace_politics(event: String = "") -> Dictionary:
	_ensure_workplace()
	if _workplace.is_empty():
		return {"ok": false, "reason": "unemployed"}
	var opts: Dictionary = {"check_repercussion": true}
	if not event.is_empty():
		opts["event"] = event
	var r: Dictionary = workplace_sys.office_politics(_workplace, player(), relations, rng, opts)
	var action: String = String(workplace_sys.apply_repercussion(_workplace, player(), rng).get("action", "none"))
	var job: Dictionary = jobs.current_job(player())
	if not job.is_empty():
		job["performance"] = clampf(float(_workplace.get("performance", 50.0)), 0.0, 100.0)
		job["internal_reputation"] = clampf(float(_workplace.get("internal_reputation", 50.0)), 0.0, 100.0)
		player()["job"] = job
	if action == "fire":
		jobs.resign(player(), now_minutes())
		_workplace = {}
	_persist_workplace()
	return r


func workplace_join(faction_id: String) -> Dictionary:
	_ensure_workplace()
	if _workplace.is_empty():
		return {"ok": false, "reason": "unemployed"}
	var r: Dictionary = workplace_sys.join_faction(_workplace, faction_id)
	_persist_workplace()
	return r


func workplace_stay_neutral() -> Dictionary:
	_ensure_workplace()
	if _workplace.is_empty():
		return {"ok": false, "reason": "unemployed"}
	var r: Dictionary = workplace_sys.stay_neutral(_workplace)
	_persist_workplace()
	return r


func workplace_found_faction(name: String) -> Dictionary:
	_ensure_workplace()
	if _workplace.is_empty():
		return {"ok": false, "reason": "unemployed"}
	var fid: String = "player.%d" % _workplace.get("factions", {}).size()
	var r: Dictionary = workplace_sys.found_faction(_workplace, fid, name)
	_persist_workplace()
	return r


func workplace_promote() -> Dictionary:
	_ensure_workplace()
	if _workplace.is_empty():
		return {"ok": false, "reason": "unemployed"}
	if not jobs.eligible_promotion(player()):
		return {"ok": false, "reason": "not_eligible"}
	if workplace_sys.should_promote(_workplace, player(), relations, rng):
		var r: Dictionary = jobs.promote(player(), now_minutes())
		if bool(r.get("ok", false)):
			_workplace["performance"] = clampf(float(_workplace.get("performance", 50.0)) + 5.0, 0.0, 100.0)
			_persist_workplace()
		return r
	return {"ok": false, "reason": "not_eligible"}


func workplace_panel_data() -> Dictionary:
	var job: Dictionary = jobs.current_job(player())
	if job.is_empty() and _workplace.is_empty():
		return {}
	_ensure_workplace()
	var out: Dictionary = _workplace.duplicate(true)
	out["job_title"] = String(job.get("title", job.get("content_key", "")))
	out["deterioration_risk"] = workplace_sys.deterioration_risk(_workplace)
	return out


## 职场按月推进：派系力量回归并漂移。
func _workplace_tick(before_minutes: int, after_minutes: int) -> void:
	if _workplace.is_empty():
		return
	if _month_ordinal(after_minutes) - _month_ordinal(before_minutes) <= 0:
		return
	workplace_sys.settle_factions(_workplace, rng)
	_persist_workplace()


func _persist_workplace() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["workplace"] = _workplace.duplicate(true)


# --- 公司与融资 ---

## 注册个体户/公司，本金从业主账户划入公司账户。
func company_register(kind: String, name: String, capital: int) -> Dictionary:
	if not _company.is_empty():
		return {"ok": false, "reason": "already_registered"}
	var r: Dictionary = company_sys.register_company(economy, account_id(), {
		"kind": kind, "name": name, "capital": capital, "day": day_index(),
	})
	if bool(r.get("ok", false)):
		_company = r["company"]
		_cap_table = financing_sys.new_cap_table(String(_company.get("id", "")))
		_persist_company()
		sync_finances()
	return r


func company_choose_site(area_sqm: float, monthly_rent: int) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = company_sys.choose_site(_company, current_region_id(), area_sqm, monthly_rent)
	_persist_company()
	return r


func company_set_status(open_shop: bool) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = company_sys.open_shop(_company) if open_shop else company_sys.close_shop(_company)
	_persist_company()
	return r


func company_stock(good_key: String, qty: int, unit_cost: int) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = company_sys.stock(_company, economy, good_key, qty, unit_cost)
	_persist_company()
	return r


func company_set_price(good_key: String, price: int) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = company_sys.set_price(_company, good_key, price)
	_persist_company()
	return r


func company_hire(monthly_wage: int) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var eid: String = "emp.%d" % (int(_company.get("employees", []).size()) + 1)
	var r: Dictionary = company_sys.hire(_company, eid, monthly_wage)
	_persist_company()
	return r


func company_fire(employee_id: String) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = company_sys.fire(_company, employee_id)
	_persist_company()
	return r


func company_expand(cost: int) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = company_sys.expand(_company, economy, cost)
	_persist_company()
	return r


func company_tax() -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var history: Array = _company.get("revenue_history", [])
	var profit: int = 0
	for rec in history.slice(-company_sys.MONTH_DAYS if history.size() > company_sys.MONTH_DAYS else 0):
		profit += int((rec as Dictionary).get("profit", 0))
	var r: Dictionary = company_sys.settle_tax(_company, economy, "government", profit)
	_persist_company()
	return r


func company_finance_raise(stage: String = "", equity_pct: float = -1.0) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var opts: Dictionary = {}
	if not stage.is_empty():
		opts["stage"] = stage
	if equity_pct > 0.0:
		opts["equity_pct"] = equity_pct
	var r: Dictionary = financing_sys.raise_round(_cap_table, _company, economy, opts)
	_persist_company()
	return r


func company_settle_vam(target_revenue: int) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var history: Array = _company.get("revenue_history", [])
	var actual: int = 0
	for rec in history.slice(-30 if history.size() > 30 else 0):
		actual += int((rec as Dictionary).get("revenue", 0))
	var r: Dictionary = financing_sys.settle_vam(_cap_table, _company, economy, target_revenue, actual)
	_persist_company()
	return r


func company_exit(kind: String) -> Dictionary:
	if _company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = financing_sys.exit(_cap_table, _company, economy, kind)
	_persist_company()
	return r


func company_panel_data() -> Dictionary:
	if _company.is_empty():
		return {}
	var cap: Dictionary = _cap_table.duplicate(true)
	var products: Array = []
	for key in (_company.get("inventory", {}) as Dictionary).keys():
		var entry: Dictionary = _company["inventory"][key]
		products.append({"good": String(key), "qty": int(entry.get("qty", 0)), "unit_cost": int(entry.get("unit_cost", 0)), "price": int((_company.get("prices", {}) as Dictionary).get(key, 0))})
	return {
		"company": _company.duplicate(true),
		"cap_table": cap,
		"products": products,
		"employees": (_company.get("employees", []) as Array).duplicate(true),
		"cash": int(economy.liquid(String(_company.get("account", "")))) if economy.has_account(String(_company.get("account", ""))) else 0,
		"net_worth": company_sys.net_worth(_company, economy),
		"insolvent": company_sys.is_insolvent(_company, economy),
	}


## 公司按日结算（仅营业中），资不抵债触发破产。
func _company_tick(before_minutes: int, after_minutes: int) -> void:
	if _company.is_empty() or String(_company.get("status", "")) != company_sys.STATUS_OPEN:
		return
	var days: int = after_minutes / MINUTES_PER_DAY - before_minutes / MINUTES_PER_DAY
	if days <= 0:
		return
	for i in mini(days, 366):
		var day: int = after_minutes / MINUTES_PER_DAY - days + i
		var r: Dictionary = company_sys.tick_day(_company, economy, day, rng)
		if bool(r.get("bankrupt", false)):
			company_sys.bankrupt(_company, economy)
			break
	_persist_company()


func _persist_company() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["company"] = {
		"company": _company.duplicate(true),
		"cap_table": _cap_table.duplicate(true),
	}


# --- D6 形象与医美 ---

const CARE_COSTS: Dictionary = {"haircut": 5000, "makeup": 3000, "outfit": 20000, "fitness": 2000}

## 惰性建立玩家形象档案，并以当前档案同步魅力。
func _ensure_appearance() -> void:
	if _appearance.is_empty():
		_appearance = appearance_sys.new_profile(player())
	if _aesthetic.is_empty():
		_aesthetic = aesthetic_sys.new_state()
	if (_aesthetic.get("id_photo", {}) as Dictionary).is_empty():
		_aesthetic["id_photo"] = _appearance.duplicate(true)
	_sync_appearance()


## 把魅力公式结果回写玩家能力。
func _sync_appearance() -> void:
	appearance_sys.sync_charm(_appearance, player())


## 形象护理：理发/化妆/穿搭/健身，扣费后更新档案与魅力。
func appearance_care(kind: String, opts: Dictionary = {}) -> Dictionary:
	_ensure_appearance()
	if not CARE_COSTS.has(kind):
		return {"ok": false, "reason": "unknown_care"}
	var cost: int = int(CARE_COSTS[kind])
	if int(economy.cash(account_id())) < cost:
		return {"ok": false, "reason": "insufficient_funds"}
	var use_opts: Dictionary = opts.duplicate(true)
	use_opts["cost"] = cost
	var r: Dictionary = appearance_sys.care(_appearance, kind, use_opts)
	if not bool(r.get("ok", false)):
		return r
	economy.add_money(account_id(), -cost, "appearance_care:%s" % kind)
	_sync_appearance()
	_persist_appearance()
	r["cost"] = cost
	r["charm"] = appearance_sys.charm(_appearance)
	return r


## 医美：合法性影响费用/成功率/并发症；恢复期内不可再次手术。
func aesthetic_perform(project: String, legal: bool = true) -> Dictionary:
	_ensure_appearance()
	if not aesthetic_sys.PROJECTS.has(project):
		return {"ok": false, "reason": "unknown_project"}
	if now_minutes() < int(_aesthetic.get("recovery_until", 0)):
		return {"ok": false, "reason": "recovering", "remaining_minutes": int(_aesthetic.get("recovery_until", 0)) - now_minutes()}
	var def: Dictionary = aesthetic_sys.PROJECTS[project]
	var cost_mult: float = 1.0 if legal else aesthetic_sys.ILLEGAL_COST_MULT
	var estimate: int = int(round(float(def.get("cost", 0)) * cost_mult))
	if int(economy.cash(account_id())) < estimate:
		return {"ok": false, "reason": "insufficient_funds", "cost": estimate}
	var r: Dictionary = aesthetic_sys.perform(_aesthetic, _appearance, project, legal, rng, now_minutes(), cost_mult)
	if not bool(r.get("ok", false)):
		return r
	var cost: int = int(r.get("cost", estimate))
	economy.add_money(account_id(), -cost, "aesthetic:%s" % project)
	var health_loss: float = float(r.get("health_loss", 0.0))
	if health_loss > 0.0:
		var attrs: Dictionary = player().get("attrs", {})
		var phys: Dictionary = attrs.get("physiological", {})
		phys["health"] = clampf(float(phys.get("health", 100.0)) - health_loss, 0.0, 100.0)
		attrs["physiological"] = phys
		player()["attrs"] = attrs
	_appearance["bmi"] = appearance_sys.bmi(float(_appearance.get("weight_kg", 62.0)), float(_appearance.get("height_cm", 170.0)))
	_sync_appearance()
	_persist_appearance()
	r["charm"] = appearance_sys.charm(_appearance)
	r["remaining_minutes"] = maxi(0, int(_aesthetic.get("recovery_until", 0)) - now_minutes())
	return r


## 医美失败维权：立案进入民事侵权诉讼，赔偿经开庭/执行回流。
func aesthetic_claim() -> Dictionary:
	_ensure_appearance()
	if not (_civil.get("claim", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "existing_claim"}
	var r: Dictionary = aesthetic_sys.malpractice_claim(_aesthetic)
	if not bool(r.get("ok", false)):
		return r
	var amount: int = int(r.get("compensation", BaselineScript.AESTHETICS_MALPRACTICE_COMPENSATION))
	var claim: Dictionary = civil_sys.new_claim("tort", amount, "player", "clinic")
	claim["type_name"] = "医疗纠纷"
	claim["title"] = "医美失败赔偿"
	claim["evidence"] = 0.8
	_civil = {"claim": claim, "judgment": {}, "enforced": false, "appealed": false}
	var cid: String = "civil:%d:%d" % [now_minutes(), domain_wake.entry_count()]
	var due: int = now_minutes() + BaselineScript.WAKE_CASE_LIMIT_DAYS * BaselineScript.WAKE_MINUTES_PER_DAY
	domain_register(cid, DomainWakeScript.KIND_CASE, {
		"region_id": current_region_id(), "due_minute": due, "total": due - now_minutes(), "civil_id": cid,
	})
	_persist_civil()
	_persist_appearance()
	return {"ok": true, "claim": claim, "case_id": cid, "amount": amount}


## 证件人像比对：整容后可能不匹配，需重办证件。
func appearance_verify_id() -> Dictionary:
	_ensure_appearance()
	var photo: Dictionary = _aesthetic.get("id_photo", {})
	var r: Dictionary = aesthetic_sys.verify_identity(_appearance, photo, BaselineScript.AESTHETICS_ID_TOLERANCE)
	r["diff"] = appearance_sys.photo_diff(_appearance, photo)
	r["tolerance"] = BaselineScript.AESTHETICS_ID_TOLERANCE
	return r


## 重办证件：以当前形象重拍证件照。
func appearance_reissue_id() -> Dictionary:
	_ensure_appearance()
	var cost: int = BaselineScript.AESTHETICS_REISSUE_COST
	if int(economy.cash(account_id())) < cost:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost}
	_aesthetic["id_photo"] = _appearance.duplicate(true)
	economy.add_money(account_id(), -cost, "appearance_reissue_id")
	_persist_appearance()
	return {"ok": true, "cost": cost}


## 形象随时间自然衰减（年龄/健康）与医美效果到期回收。
func _appearance_tick(minutes: int) -> void:
	if minutes <= 0:
		return
	_ensure_appearance()
	var years: float = float(minutes) / MINUTES_PER_YEAR
	var age: int = int(player().get("age", 30))
	var health: float = float((player().get("attrs", {}) as Dictionary).get("physiological", {}).get("health", 80.0))
	appearance_sys.decay(_appearance, years, float(age), health)
	aesthetic_sys.decay_effects(_aesthetic, _appearance, float(minutes) / float(MINUTES_PER_DAY))
	_sync_appearance()
	_persist_appearance()


func appearance_panel_data() -> Dictionary:
	_ensure_appearance()
	var projects: Array = []
	for key in aesthetic_sys.PROJECTS.keys():
		var def: Dictionary = aesthetic_sys.PROJECTS[key]
		projects.append({
			"key": String(key), "name": String(def.get("name", key)), "cost": int(def.get("cost", 0)),
			"recovery_minutes": int(def.get("recovery_minutes", 0)), "success": float(def.get("success", 0.0)),
			"complication": float(def.get("complication", 0.0)), "repeatable": bool(def.get("repeatable", false)),
		})
	var idr: Dictionary = appearance_verify_id()
	var procedures: Array = []
	for rec in (_aesthetic.get("procedures", []) as Array):
		var rd: Dictionary = rec
		procedures.append({
			"project": String(rd.get("project", "")), "outcome": String(rd.get("outcome", "")),
			"minute": int(rd.get("minute", 0)), "cost": int(rd.get("cost", 0)),
		})
	return {
		"profile": _appearance.duplicate(true),
		"charm": appearance_sys.charm(_appearance),
		"body_modifier": appearance_sys.body_type_modifier(_appearance),
		"voice_modifier": appearance_sys.voice_modifier(_appearance),
		"weights": appearance_sys.CHARM_WEIGHTS.duplicate(true),
		"count": int(_aesthetic.get("count", 0)),
		"stiffness": float(_aesthetic.get("stiffness", 0.0)),
		"addicted": bool(_aesthetic.get("addicted", false)),
		"recovery_remaining": maxi(0, int(_aesthetic.get("recovery_until", 0)) - now_minutes()),
		"id_match": bool(idr.get("matched", true)),
		"id_diff": float(idr.get("diff", 0.0)),
		"id_tolerance": float(idr.get("tolerance", 25.0)),
		"projects": projects,
		"procedures": procedures,
	}


func _persist_appearance() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["appearance"] = {
		"profile": _appearance.duplicate(true),
		"aesthetics": _aesthetic.duplicate(true),
	}


# --- D41 社会救助、收养寄养与慈善 ---

func welfare_state() -> Dictionary:
	return {
		"application": _welfare_application, "fund": _welfare_fund,
		"worker": _welfare_worker, "case": _welfare_case, "child": _welfare_child,
	}

func welfare_application_kinds_catalog() -> Array:
	var out: Array = []
	for key in social_welfare.application_kinds():
		out.append({"id": String(key), "name": social_welfare.application_name(String(key))})
	return out

func welfare_crisis_kinds_catalog() -> Array:
	var names: Dictionary = {"orphan": "孤儿", "abandoned": "被遗弃", "guardian_disabled": "监护人失能"}
	var out: Array = []
	for key in social_welfare.crisis_kinds():
		out.append({"id": String(key), "name": String(names.get(key, key))})
	return out

func welfare_applicant() -> Dictionary:
	var p := player()
	return {
		"id": str(p.get("id", "player")),
		"age": int(p.get("age", 30)),
		"income": float(p.get("income", 0.0)),
		"assets": float(p.get("assets", 0.0)),
		"household_size": int(p.get("household_size", 1)),
		"registered_local": bool(p.get("registered_local", true)),
		"criminal_record": bool(p.get("criminal_record", false)),
		"major_illness": bool(p.get("major_illness", false)),
		"medical_need": bool(p.get("medical_need", false)),
		"in_crisis": bool(p.get("in_crisis", false)),
		"homeless": bool(p.get("homeless", false)),
		"capacity": int(p.get("capacity", 1)),
		"housing_score": float(p.get("housing_score", 0.5)),
		"abuse_history": bool(p.get("abuse_history", false)),
		"aid_months": int(p.get("aid_months", 0)),
		"employable": float(p.get("employable", 0.0)),
	}

func welfare_apply(kind: String, amount: int = 0) -> Dictionary:
	var applicant: Dictionary = welfare_applicant()
	_welfare_application = social_welfare.new_application(kind, applicant, {"amount": amount})
	var r: Dictionary = social_welfare.review_qualification(_welfare_application, applicant)
	if bool(r.get("approved", false)) and (kind == "adoption" or kind == "foster"):
		var wait_days: int = 30 if kind == "adoption" else 15
		_welfare_application["status"] = "pending"
		_welfare_application["eligible"] = true
		_welfare_application["waiting_days"] = wait_days
		_welfare_application["placement_day"] = now_minutes() / MINUTES_PER_DAY + wait_days
		r["waiting_days"] = wait_days
	_persist_welfare()
	if not bool(r.get("ok", false)):
		return r
	return {
		"ok": true, "approved": bool(r.get("approved", false)),
		"reasons": r.get("reasons", []), "application": _welfare_application,
		"waiting_days": int(r.get("waiting_days", 0)),
	}

## 跨区资格互认：把当前已通过的申请凭证互认到所在区域。
func welfare_recognize(origin_region: String) -> Dictionary:
	if _welfare_application.is_empty():
		return {"ok": false, "reason": "no_application"}
	var r: Dictionary = social_welfare.recognize_qualification(_welfare_application, origin_region, current_region_id(), {"issued_day": now_minutes() / MINUTES_PER_DAY})
	if bool(r.get("ok", false)):
		_welfare_recognition = (r.get("certificate", {}) as Dictionary).duplicate(true)
		_persist_welfare()
	return r

## 收养/寄养等待期满后生效，记录生效日供撤销判断。
func welfare_finalize_placement() -> Dictionary:
	if _welfare_application.is_empty():
		return {"ok": false, "reason": "no_application"}
	var kind: String = String(_welfare_application.get("kind", ""))
	if kind != "adoption" and kind != "foster":
		return {"ok": false, "reason": "not_placement"}
	if str(_welfare_application.get("status", "")) != "pending":
		return {"ok": false, "reason": "not_pending"}
	var placement_day: int = int(_welfare_application.get("placement_day", 0))
	var today: int = now_minutes() / MINUTES_PER_DAY
	if today < placement_day:
		return {"ok": false, "reason": "waiting", "days_left": placement_day - today}
	_welfare_application["status"] = "approved"
	_welfare_application["finalized"] = true
	_welfare_application["finalized_day"] = today
	_persist_welfare()
	return {"ok": true, "kind": kind, "finalized_day": today, "application": _welfare_application}

## 收养生效后 30 日内可撤销；撤销后转为可重新申请状态。
func welfare_revoke_placement() -> Dictionary:
	if _welfare_application.is_empty():
		return {"ok": false, "reason": "no_application"}
	if str(_welfare_application.get("kind", "")) != "adoption":
		return {"ok": false, "reason": "not_adoption"}
	if not bool(_welfare_application.get("finalized", false)):
		return {"ok": false, "reason": "not_finalized"}
	var finalized_day: int = int(_welfare_application.get("finalized_day", 0))
	var today: int = now_minutes() / MINUTES_PER_DAY
	if today - finalized_day > 30:
		return {"ok": false, "reason": "revoke_expired"}
	_welfare_application["revoked"] = true
	_welfare_application["status"] = "revoked"
	_persist_welfare()
	return {"ok": true, "revoked": true, "day": today}

func welfare_disburse(days: int = 30) -> Dictionary:
	if _welfare_application.is_empty():
		return {"ok": false, "reason": "no_application"}
	var r: Dictionary = social_welfare.disburse_assistance(_welfare_application, welfare_applicant(), {"days": days})
	_persist_welfare()
	return r

func welfare_assess_home() -> Dictionary:
	return social_welfare.assess_home(welfare_applicant())

func welfare_crisis(situation: String, has_relative: bool = false) -> Dictionary:
	if _welfare_child.is_empty():
		_welfare_child = {"id": "child", "name": "儿童"}
	var r: Dictionary = social_welfare.child_in_crisis(_welfare_child, situation, {"has_relative": has_relative})
	_persist_welfare()
	return r

func welfare_report_abuse() -> Dictionary:
	if _welfare_child.is_empty():
		_welfare_child = {"id": "child", "name": "儿童"}
	var guardian: Dictionary = welfare_applicant()
	var r: Dictionary = social_welfare.report_abuse(_welfare_child, guardian, {"evidence": 0.6}, rng)
	_persist_welfare()
	return r

func welfare_dependency() -> Dictionary:
	return social_welfare.welfare_dependency(welfare_applicant())

func welfare_fund_new(name: String = "公益基金") -> Dictionary:
	_welfare_fund = social_welfare.new_charity_fund(name)
	_persist_welfare()
	return {"ok": true, "fund": _welfare_fund}

func welfare_fund_donate(amount: int) -> Dictionary:
	if _welfare_fund.is_empty():
		_welfare_fund = social_welfare.new_charity_fund("公益基金")
	var r: Dictionary = social_welfare.donate(_welfare_fund, amount)
	_persist_welfare()
	return r

func welfare_fund_settle() -> Dictionary:
	if _welfare_fund.is_empty():
		return {"ok": false, "reason": "no_fund"}
	return social_welfare.settle_fund(_welfare_fund)

func welfare_fund_spend(purpose: String, amount: int) -> Dictionary:
	if _welfare_fund.is_empty():
		return {"ok": false, "reason": "no_fund"}
	var r: Dictionary = social_welfare.spend_fund(_welfare_fund, purpose, amount)
	_persist_welfare()
	return r

func welfare_fund_audit() -> Dictionary:
	if _welfare_fund.is_empty():
		return {"ok": false, "reason": "no_fund"}
	var r: Dictionary = social_welfare.audit_transparency(_welfare_fund)
	_persist_welfare()
	return r

func welfare_fund_misappropriate(amount: int) -> Dictionary:
	if _welfare_fund.is_empty():
		return {"ok": false, "reason": "no_fund"}
	var r: Dictionary = social_welfare.misappropriate(_welfare_fund, amount, {"roll": -1.0}, rng)
	_persist_welfare()
	return r

func welfare_worker_start() -> Dictionary:
	_welfare_worker = social_welfare.new_social_worker("player", {"name": "本人"})
	_persist_welfare()
	return {"ok": true, "worker": _welfare_worker}

func welfare_case_open(family_id: String = "family") -> Dictionary:
	if _welfare_worker.is_empty():
		return {"ok": false, "reason": "no_worker"}
	_welfare_case = social_welfare.new_case(_welfare_worker, family_id)
	_persist_welfare()
	return {"ok": true, "case": _welfare_case}

func welfare_follow_up(note: String = "家访") -> Dictionary:
	if _welfare_case.is_empty():
		return {"ok": false, "reason": "no_welfare_case"}
	var r: Dictionary = social_welfare.follow_up(_welfare_case, note)
	_persist_welfare()
	return r

func welfare_close_case() -> Dictionary:
	if _welfare_worker.is_empty():
		return {"ok": false, "reason": "no_worker"}
	if _welfare_case.is_empty():
		return {"ok": false, "reason": "no_welfare_case"}
	var r: Dictionary = social_welfare.close_case(_welfare_worker, _welfare_case)
	_persist_welfare()
	return r

func welfare_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _welfare_application.is_empty():
		out["application"] = {
			"kind": String(_welfare_application.get("kind", "")),
			"kind_name": social_welfare.application_name(String(_welfare_application.get("kind", ""))),
			"status": String(_welfare_application.get("status", "")),
			"approved": String(_welfare_application.get("status", "")) == "approved",
			"amount": int(_welfare_application.get("amount", 0)),
			"disbursed": int(_welfare_application.get("disbursed", 0)),
			"reasons": (_welfare_application.get("reasons", []) as Array).duplicate(),
		}
	if not _welfare_fund.is_empty() and (int(_welfare_fund.get("raised", 0)) > 0 or int(_welfare_fund.get("spent", 0)) > 0 or int(_welfare_fund.get("balance", 0)) > 0):
		out["fund"] = {
			"name": String(_welfare_fund.get("name", "")),
			"balance": int(_welfare_fund.get("balance", 0)),
			"raised": int(_welfare_fund.get("raised", 0)),
			"spent": int(_welfare_fund.get("spent", 0)),
			"transparency": float(_welfare_fund.get("transparency", 0.0)),
			"reputation": float(_welfare_fund.get("reputation", 0.0)),
		}
	if not _welfare_worker.is_empty():
		out["worker"] = {
			"name": String(_welfare_worker.get("name", "")),
			"cases_closed": int(_welfare_worker.get("cases_closed", 0)),
			"rank_index": int(_welfare_worker.get("rank_index", 0)),
			"active_cases": (_welfare_worker.get("active_cases", []) as Array).size(),
		}
	if not _welfare_case.is_empty():
		out["case"] = {
			"id": String(_welfare_case.get("id", "")),
			"family_id": String(_welfare_case.get("family_id", "")),
			"status": String(_welfare_case.get("status", "")),
			"visits": int(_welfare_case.get("visits", 0)),
			"progress": float(_welfare_case.get("progress", 0.0)),
		}
	if not _welfare_child.is_empty():
		out["child"] = {
			"id": String(_welfare_child.get("id", "")),
			"route": String(_welfare_child.get("welfare_route", "")),
		}
	return out

func _persist_welfare() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["welfare"] = {
		"application": social_welfare.to_dict(_welfare_application),
		"fund": social_welfare.to_dict(_welfare_fund),
		"worker": social_welfare.to_dict(_welfare_worker),
		"case": social_welfare.to_dict(_welfare_case),
		"child": social_welfare.to_dict(_welfare_child),
		"recognition": _welfare_recognition.duplicate(true),
	}


# --- D42 殡葬、器官捐献与纪念 ---

func funeral_state() -> Dictionary:
	return {"state": _funeral_state, "home": _funeral_home}

func funeral_methods_catalog() -> Array:
	var out: Array = []
	for key in funeral.methods():
		out.append({"id": String(key), "name": String((funeral.method_def(String(key)) as Dictionary).get("name", key))})
	return out

func funeral_grave_types_catalog() -> Array:
	var out: Array = []
	for key in funeral.grave_types():
		out.append({"id": String(key), "name": String((funeral.grave_def(String(key)) as Dictionary).get("name", key))})
	return out

func funeral_memorial_kinds_catalog() -> Array:
	var names: Dictionary = {"monument": "纪念碑", "family_grave": "家族墓", "digital_cemetery": "数字纪念", "virtual_grave": "虚拟墓园"}
	var out: Array = []
	for key in funeral.memorial_kinds():
		out.append({"id": String(key), "name": String(names.get(key, key))})
	return out

func funeral_arrange(method: String, grave: String, estate: int = -1) -> Dictionary:
	var death_info: Dictionary = {"id": "player", "estate": estate if estate >= 0 else int(player_estate_minor())}
	var r: Dictionary = funeral.arrange_funeral(death_info, _funeral_state, {"method": method, "grave": grave})
	_persist_funeral()
	return r

func funeral_execute(public_assistance: bool = false) -> Dictionary:
	var r: Dictionary = funeral.execute_funeral(_funeral_state, {"public_assistance": public_assistance})
	_persist_funeral()
	return r

## 死亡自动衔接：生前已安排则立即执行，遗产不足时走公益救助。
func _auto_execute_funeral() -> void:
	if _funeral_state.is_empty():
		return
	var f: Dictionary = _funeral_state.get("funeral", {})
	if not bool(f.get("arranged", false)) or bool(f.get("executed", false)):
		return
	var r: Dictionary = funeral.execute_funeral(_funeral_state, {"public_assistance": not bool(f.get("affordable", false))})
	if bool(r.get("ok", false)):
		_funeral_state["auto_executed"] = true
		_persist_funeral()

func funeral_register_donation() -> Dictionary:
	var r: Dictionary = funeral.register_donation(_funeral_state)
	_persist_funeral()
	return r

func funeral_review_ethics() -> Dictionary:
	var r: Dictionary = funeral.review_ethics(_funeral_state, {"roll": -1.0})
	_persist_funeral()
	return r

func funeral_revoke_donation(deceased: bool = true) -> Dictionary:
	var r: Dictionary = funeral.revoke_donation(_funeral_state, {"deceased": deceased})
	_persist_funeral()
	return r

func funeral_allocate_organs() -> Dictionary:
	var region: String = current_region_id()
	var now_day: int = now_minutes() / MINUTES_PER_DAY
	var recipients: Array = [
		{"id": "recipient-1", "organ": "heart", "urgency": 0.9, "region": region, "available_day": now_day - 120},
		{"id": "recipient-2", "organ": "kidney", "urgency": 0.7, "region": "cn.shanghai", "available_day": now_day - 300},
		{"id": "recipient-3", "organ": "cornea", "urgency": 0.5, "region": region, "available_day": now_day - 30},
	]
	var r: Dictionary = funeral.allocate_organs(_funeral_state, recipients, {"local_region": region, "now_day": now_day})
	_persist_funeral()
	return r

func funeral_transplant(organ: String) -> Dictionary:
	return funeral.transplant(player(), organ, {"roll": -1.0}, rng)

func funeral_build_memorial(kind: String) -> Dictionary:
	var r: Dictionary = funeral.build_memorial(_funeral_state, kind)
	_persist_funeral()
	return r

func funeral_tomb_sweeping(kind: String = "family_grave") -> Dictionary:
	var r: Dictionary = funeral.tomb_sweeping(_funeral_state, {"kind": kind})
	_persist_funeral()
	return r

func funeral_digital_memorial() -> Dictionary:
	var r: Dictionary = funeral.create_digital_memorial(_funeral_state)
	_persist_funeral()
	return r

## 数字纪念平台：首期扣开通费与捐赠，会员订阅净收入回写玩家账户。
func funeral_digital_platform(members: int = 50, donation: int = 0) -> Dictionary:
	if _funeral_state.is_empty():
		return {"ok": false, "reason": "no_state"}
	var platform: Dictionary = (_funeral_state.get("digital", {}) as Dictionary).get("platform", {})
	var setup_cost: int = 0 if not platform.is_empty() else 50000
	var upfront: int = setup_cost + maxi(0, donation)
	if int(economy.cash(account_id())) < upfront:
		return {"ok": false, "reason": "insufficient_funds", "cost": upfront}
	economy.add_money(account_id(), -upfront, "digital_platform")
	var r: Dictionary = funeral.operate_digital_platform(_funeral_state, {
		"members": maxi(0, members), "donation": maxi(0, donation),
		"setup_cost": setup_cost, "monthly_fee": 1200, "hosting_cost": 300, "subsidy_per_member": 200,
	})
	if bool(r.get("ok", false)):
		var net: int = int(r.get("net", 0))
		if net != 0:
			economy.add_money(account_id(), net, "digital_platform_net")
		_persist_funeral()
	return r

func funeral_execute_will() -> Dictionary:
	var will: Dictionary = player().get("will", {})
	var r: Dictionary = funeral.execute_will(will, {"id": "player"}, _funeral_state)
	_persist_funeral()
	return r

func funeral_new_home(name: String = "殡仪馆") -> Dictionary:
	_funeral_home = funeral.new_funeral_home(name, {"balance": 0})
	_funeral_state["industry"] = _funeral_home
	_persist_funeral()
	return {"ok": true, "home": _funeral_home}

func funeral_quote(method: String) -> Dictionary:
	if _funeral_home.is_empty():
		return {"ok": false, "reason": "no_industry"}
	return funeral.quote_service(_funeral_home, method)

func funeral_sale(method: String) -> Dictionary:
	if _funeral_home.is_empty():
		return {"ok": false, "reason": "no_industry"}
	var r: Dictionary = funeral.settle_sale(_funeral_home, method)
	_persist_funeral()
	return r

func funeral_regulate() -> Dictionary:
	if _funeral_home.is_empty():
		return {"ok": false, "reason": "no_industry"}
	var r: Dictionary = funeral.regulate_market(_funeral_home, {"roll": -1.0}, rng)
	_persist_funeral()
	return r

func funeral_reform() -> Dictionary:
	if _funeral_home.is_empty():
		return {"ok": false, "reason": "no_industry"}
	var r: Dictionary = funeral.reform_customs(_funeral_state)
	_persist_funeral()
	return r

func funeral_unclaimed() -> Dictionary:
	var r: Dictionary = funeral.unclaimed_body(_funeral_state, {"unclaimed": true, "action": "public_cremation"})
	_persist_funeral()
	return r

func funeral_dispute() -> Dictionary:
	var r: Dictionary = funeral.donation_dispute(_funeral_state, {"roll": -1.0, "revoke": true}, rng)
	_persist_funeral()
	return r

func funeral_panel_data() -> Dictionary:
	var out: Dictionary = {}
	var st: Dictionary = _funeral_state
	var f: Dictionary = st.get("funeral", {})
	if bool(f.get("arranged", false)):
		out["funeral"] = {
			"method": String(f.get("method", "")),
			"method_name": String((funeral.method_def(String(f.get("method", ""))) as Dictionary).get("name", "")),
			"grave": String(f.get("grave", "")),
			"grave_name": String((funeral.grave_def(String(f.get("grave", ""))) as Dictionary).get("name", "")),
			"cost": int(f.get("cost", 0)),
			"affordable": bool(f.get("affordable", true)),
			"executed": bool(f.get("executed", false)),
			"paid": int(f.get("paid", 0)),
		}
	var d: Dictionary = st.get("donation", {})
	if bool(d.get("registered", false)) or bool(d.get("revoked", false)) or bool(d.get("ethics_reviewed", false)):
		out["donation"] = {
			"registered": bool(d.get("registered", false)),
			"ethics_approved": bool(d.get("ethics_approved", false)),
			"legal": bool(d.get("legal", false)),
			"revoked": bool(d.get("revoked", false)),
			"organs": (d.get("organs", []) as Array).duplicate(),
			"allocated": (d.get("allocated", []) as Array).size(),
		}
	var memorials: Array = st.get("memorials", [])
	if not memorials.is_empty():
		out["memorials"] = []
		for m in memorials:
			out["memorials"].append({
				"kind": String((m as Dictionary).get("kind", "")),
				"name": String((m as Dictionary).get("name", "")),
				"visits": int((m as Dictionary).get("visits", 0)),
			})
	var digital: Dictionary = st.get("digital", {})
	if bool(digital.get("created", false)):
		out["digital"] = {"created": true, "visits": int(digital.get("visits", 0))}
	if not _funeral_home.is_empty():
		out["industry"] = {
			"name": String(_funeral_home.get("name", "")),
			"balance": int(_funeral_home.get("balance", 0)),
			"profit": int(_funeral_home.get("profit", 0)),
			"price_mult": float(_funeral_home.get("price_mult", 1.0)),
			"reputation": float(_funeral_home.get("reputation", 0.0)),
		}
	out["meaning"] = float(st.get("meaning", 0.0))
	return out

func _persist_funeral() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["funeral"] = {
		"state": funeral.to_dict(_funeral_state),
		"home": funeral.to_dict(_funeral_home),
	}


# --- D43 玄学、命理与民俗信仰 ---

func metaphysics_state() -> Dictionary:
	return {"client": _meta_client, "practitioner": _meta_practitioner, "business": _meta_business}

## 玄学话术目录：按服务与结果分档的显式文案。
func metaphysics_phrases_catalog() -> Array:
	return metaphysics.phrase_catalog()

func metaphysics_services_catalog() -> Array:
	var out: Array = []
	for key in metaphysics.services():
		var d: Dictionary = metaphysics.service_def(String(key))
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func metaphysics_modes_catalog() -> Array:
	var names: Dictionary = {"online": "线上", "offline": "线下"}
	var out: Array = []
	for key in metaphysics.modes():
		out.append({"id": String(key), "name": String(names.get(key, key))})
	return out

func metaphysics_folk_practices_catalog() -> Array:
	var names: Dictionary = {"taboo": "禁忌", "festival_ritual": "节日仪式", "amulet": "护身符", "wish": "许愿"}
	var out: Array = []
	for key in metaphysics.folk_practices():
		out.append({"id": String(key), "name": String(names.get(key, key))})
	return out

func metaphysics_consult(service: String, mode: String = "offline") -> Dictionary:
	var r: Dictionary = metaphysics.consult(_meta_practitioner, service, _meta_client, {"mode": mode, "roll": -1.0}, rng)
	_persist_metaphysics()
	return r

func metaphysics_folk(practice: String) -> Dictionary:
	var r: Dictionary = metaphysics.use_folk_practice(_meta_client, practice)
	_persist_metaphysics()
	return r

func metaphysics_new_business(name: String = "玄学馆") -> Dictionary:
	_meta_business = metaphysics.new_business(name, {"reputation": 0.5})
	_persist_metaphysics()
	return {"ok": true, "business": _meta_business}

func metaphysics_operate() -> Dictionary:
	if _meta_business.is_empty():
		return {"ok": false, "reason": "no_business"}
	var r: Dictionary = metaphysics.operate_business(_meta_business, {"roll": -1.0}, rng)
	_persist_metaphysics()
	return r

func metaphysics_complaint(report: bool = true) -> Dictionary:
	if _meta_business.is_empty():
		return {"ok": false, "reason": "no_business"}
	var r: Dictionary = metaphysics.file_complaint(_meta_business, {"report": report})
	_persist_metaphysics()
	return r

func metaphysics_investigate() -> Dictionary:
	if _meta_business.is_empty():
		return {"ok": false, "reason": "no_business"}
	var r: Dictionary = metaphysics.investigate_fraud(_meta_business, {"roll": -1.0}, rng)
	_persist_metaphysics()
	return r

func metaphysics_master_fall() -> Dictionary:
	if _meta_business.is_empty():
		return {"ok": false, "reason": "no_business"}
	var r: Dictionary = metaphysics.master_fall(_meta_business)
	_persist_metaphysics()
	return r

func metaphysics_superstition(members: int) -> Dictionary:
	return metaphysics.organized_superstition(members)

func metaphysics_collude() -> Dictionary:
	if _meta_business.is_empty():
		return {"ok": false, "reason": "no_business"}
	var r: Dictionary = metaphysics.collude_gray_market(_meta_business, {"roll": -1.0}, rng)
	_persist_metaphysics()
	return r

func metaphysics_blur() -> Dictionary:
	return metaphysics.blur_real_and_fake(_meta_practitioner)

func metaphysics_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _meta_client.is_empty():
		out["client"] = {
			"mood": float(_meta_client.get("mood", 0.0)),
			"belief": float(_meta_client.get("belief", 0.0)),
			"social": float(_meta_client.get("social", 0.0)),
			"last_consult": String(_meta_client.get("last_consult", "")),
		}
	if not _meta_practitioner.is_empty():
		out["practitioner"] = {
			"name": String(_meta_practitioner.get("name", "")),
			"real_ability": bool(_meta_practitioner.get("real_ability", false)),
			"scamming": bool(_meta_practitioner.get("scamming", false)),
			"reputation": float(_meta_practitioner.get("reputation", 0.0)),
		}
	if not _meta_business.is_empty():
		out["business"] = {
			"name": String(_meta_business.get("name", "")),
			"income": int(_meta_business.get("income", 0)),
			"customers": int(_meta_business.get("customers", 0)),
			"complaints": int(_meta_business.get("complaints", 0)),
			"reports": int(_meta_business.get("reports", 0)),
			"reputation": float(_meta_business.get("reputation", 0.0)),
			"under_investigation": bool(_meta_business.get("under_investigation", false)),
		}
	return out

func _persist_metaphysics() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["metaphysics"] = {
		"client": metaphysics.to_dict(_meta_client),
		"practitioner": metaphysics.to_dict(_meta_practitioner),
		"business": metaphysics.to_dict(_meta_business),
	}


# --- D44 隐秘异常收容体系 ---

func anomaly_state() -> Dictionary:
	return _anomaly_state

## 异常图鉴仅在存在门闩/激活后可见（默认隐藏，普通玩法不受影响）。
func anomaly_revealed() -> bool:
	return anomaly.can_enter(_anomaly_state)

func anomaly_gate_catalog() -> Array:
	var names: Dictionary = {
		"rare_talent": "稀有天赋", "hidden_event_chain": "隐藏事件链",
		"bloodline": "血脉传承", "special_place": "特殊地点", "special_item": "特殊物品",
	}
	var out: Array = []
	for key in anomaly.gate_keys():
		out.append({"id": String(key), "name": String(names.get(key, key))})
	return out

func anomaly_entry_catalog() -> Array:
	var out: Array = []
	for e in anomaly.core_entries().values():
		out.append({"id": String(e.get("id", "")), "name": String(e.get("name", ""))})
	return out

## 生成条目目录：可按数量截取，默认全量 2000。
func anomaly_generated_catalog(count: int = -1) -> Array:
	return anomaly.generated_catalog(count)

## 全量目录 schema 校验（字段/枚举/唯一 id）。
func anomaly_catalog_validate(count: int = -1) -> Dictionary:
	return anomaly.validate_catalog(count)

func anomaly_mission_catalog(faction: String = "") -> Array:
	return anomaly.faction_mission_catalog(faction)

func anomaly_ability_catalog() -> Array:
	var out: Array = []
	for key in anomaly.ability_keys():
		out.append({"id": String(key), "name": anomaly.ability_name(String(key))})
	return out

func anomaly_faction_catalog() -> Array:
	var out: Array = []
	for key in anomaly.factions():
		out.append({"id": String(key), "name": anomaly.faction_name(String(key))})
	return out

func anomaly_identity_catalog() -> Array:
	var out: Array = []
	for key in anomaly.identities():
		out.append({"id": String(key), "name": anomaly.identity_name(String(key))})
	return out

func anomaly_open_gate(path: String) -> Dictionary:
	var r: Dictionary = anomaly.open_gate(_anomaly_state, path)
	_persist_anomaly()
	return r

func anomaly_rare_talent(roll: float = -1.0) -> Dictionary:
	var effective: float = roll if roll >= 0.0 else rng.next_float()
	var r: Dictionary = anomaly.rare_talent_check(_anomaly_state, effective)
	_persist_anomaly()
	return r

func anomaly_set_clearance(level: int) -> Dictionary:
	var r: Dictionary = anomaly.set_clearance(_anomaly_state, level)
	_persist_anomaly()
	return r

func anomaly_set_identity(identity: String) -> Dictionary:
	var r: Dictionary = anomaly.set_identity(_anomaly_state, identity)
	_persist_anomaly()
	return r

func anomaly_join_faction(faction: String) -> Dictionary:
	var r: Dictionary = anomaly.join_faction(_anomaly_state, faction)
	_persist_anomaly()
	return r

func anomaly_accept_mission(mission_id: String, faction: String) -> Dictionary:
	var r: Dictionary = anomaly.accept_mission(_anomaly_state, mission_id, faction)
	_persist_anomaly()
	return r

func anomaly_complete_mission(mission_id: String, success: bool = true) -> Dictionary:
	var r: Dictionary = anomaly.complete_mission(_anomaly_state, mission_id, {"success": success})
	_persist_anomaly()
	return r

func anomaly_use_ability(line: String) -> Dictionary:
	var r: Dictionary = anomaly.use_ability(_anomaly_state, line, {}, rng)
	_persist_anomaly()
	return r

func anomaly_gain_exp(line: String, amount: float) -> Dictionary:
	var r: Dictionary = anomaly.gain_exp(_anomaly_state, line, amount)
	_persist_anomaly()
	return r

func anomaly_encounter(entry_id: String) -> Dictionary:
	var r: Dictionary = anomaly.encounter(_anomaly_state, entry_id)
	_persist_anomaly()
	return r

func anomaly_amnestics(dose: float = 0.5) -> Dictionary:
	var r: Dictionary = anomaly.amnestics(_anomaly_state, dose, {}, rng)
	_persist_anomaly()
	return r

## 认知对抗：与同种子确定性生成的对手依能力/法器/气运/抗性判定。
func anomaly_combat() -> Dictionary:
	var rival: Dictionary = anomaly.new_state()["anomaly"]
	for line in anomaly.ability_keys():
		(rival["abilities"] as Dictionary)[line]["level"] = 3
	var r: Dictionary = anomaly.resolve_combat(_anomaly_state, rival, {"contest_type": "rival", "roll": -1.0}, rng)
	_persist_anomaly()
	return r

func anomaly_breach() -> Dictionary:
	var r: Dictionary = anomaly.trigger_containment_breach(_anomaly_state)
	_persist_anomaly()
	return r

func anomaly_panel_data() -> Dictionary:
	var a: Dictionary = _anomaly_state
	var abilities: Array = []
	for key in anomaly.ability_keys():
		var line: String = String(key)
		abilities.append({
			"line": line, "name": anomaly.ability_name(line),
			"level": anomaly.ability_level(a, line), "exp": anomaly.ability_exp(a, line),
		})
	return {
		"hidden": anomaly.is_hidden(a),
		"active": anomaly.is_active(a),
		"can_enter": anomaly.can_enter(a),
		"exposure": anomaly.exposure(a),
		"tier": anomaly.exposure_tier(a),
		"ending": anomaly.ending(a),
		"clearance": anomaly.clearance_level(a),
		"is_d_class": anomaly.is_d_class(a),
		"identity": String(a.get("identity", "")),
		"identity_name": anomaly.identity_name(String(a.get("identity", ""))),
		"faction": String(a.get("faction", "")),
		"faction_name": anomaly.faction_name(String(a.get("faction", ""))),
		"abilities": abilities,
		"resources": (a.get("resources", {}) as Dictionary).duplicate(true),
		"contamination": anomaly.contamination(a),
		"contamination_total": anomaly.contamination_total(a),
		"amnestics": anomaly.amnestic_status(a),
		"known_count": anomaly.known_entries(a).size(),
		"known": anomaly.known_entries(a),
		"catalog_size": anomaly.catalog_size(),
		"missions": anomaly.faction_mission_catalog(String(a.get("faction", ""))),
	}

func _persist_anomaly() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["anomaly"] = anomaly.to_dict(_anomaly_state)


# --- D45 医疗、生命科技与医药产业 ---

func medical_diseases_catalog() -> Array:
	var out: Array = []
	for key in medical.DISEASES.keys():
		out.append({"id": String(key), "name": String((medical.DISEASES[key] as Dictionary).get("name", key))})
	return out

func medical_facilities_catalog() -> Array:
	var out: Array = []
	for key in medical.FACILITIES.keys():
		out.append({"id": String(key), "name": String((medical.FACILITIES[key] as Dictionary).get("name", key))})
	return out

func medical_services_catalog() -> Array:
	var names: Dictionary = {
		"register": "挂号", "consult": "门诊", "medicine": "买药", "dental": "牙科",
		"therapy": "心理治疗", "admit": "住院", "surgery": "手术", "checkup": "体检",
	}
	var out: Array = []
	for key in names.keys():
		out.append({"id": String(key), "name": String(names[key])})
	return out

func medtech_care_levels_catalog() -> Array:
	var out: Array = []
	for key in medtech.care_level_keys():
		out.append({"id": String(key), "name": String(medtech.care_level_def(String(key)).get("name", key))})
	return out

func medtech_departments_catalog() -> Array:
	var out: Array = []
	for key in medtech.department_keys():
		out.append({"id": String(key), "name": medtech.department_name(String(key))})
	return out

func medtech_exams_catalog() -> Array:
	var out: Array = []
	for key in medtech.exam_keys():
		out.append({"id": String(key), "name": String(medtech.exam_def(String(key)).get("name", key))})
	return out

func medtech_high_end_catalog() -> Array:
	var out: Array = []
	for key in medtech.high_end_keys():
		out.append({"id": String(key), "name": String(medtech.high_end_def(String(key)).get("name", key))})
	return out

func medtech_organ_source_catalog() -> Array:
	var names: Dictionary = {
		"voluntary_donation": "自愿捐献", "living_related": "亲属活体",
		"compensated": "有偿交易", "black_market": "黑市",
	}
	var out: Array = []
	for key in names.keys():
		out.append({"id": String(key), "name": String(names[key])})
	return out

func medical_visit(facility: String, service: String, disease: String = "") -> Dictionary:
	var fund: int = int(_medical_region.get("insurance_fund", 0))
	var cost_estimate: int = 0
	if medical.FACILITIES.has(facility):
		var f: Dictionary = medical.FACILITIES[facility]
		cost_estimate = int(round(float(medical.SERVICE_COST.get(service, 0)) * float(f.get("cost_mult", 1.0))))
	if int(economy.cash(account_id())) < cost_estimate:
		return {"ok": false, "reason": "insufficient_funds", "cost": cost_estimate}
	var r: Dictionary = medical.visit(facility, service, disease, now_minutes(), rng)
	if not bool(r.get("ok", false)):
		return r
	# 医保基金不足时按可用余额封顶，剩余转自付。
	var reimburse: int = mini(int(r.get("reimbursed", 0)), fund)
	r["reimbursed"] = reimburse
	r["self_pay"] = int(r.get("cost", 0)) - reimburse
	_medical_region["insurance_fund"] = maxi(0, fund - reimburse)
	(economy.macro as Dictionary)["medical_spending"] = int(economy.macro.get("medical_spending", 0)) + reimburse
	if int(r.get("self_pay", 0)) != 0:
		economy.add_money(account_id(), -int(r["self_pay"]), "medical_visit")
	_persist_medical()
	return r

## 用药疗程：按天数累计耐药，并按副作用风险扣减健康。
func medical_drug_course(days: int, adherence: float = 0.7) -> Dictionary:
	var side: Dictionary = medtech.drug_side_effect(1.0, {"susceptibility": 0.3})
	var resist: Dictionary = medtech.drug_resistance(float(days), {"adherence": adherence})
	var health: Dictionary = player().get("health", {})
	var prior: float = clampf(float(health.get("drug_resistance", 0.0)), 0.0, 1.0)
	var total_resistance: float = clampf(prior + float(resist.get("resistance", 0.0)), 0.0, 1.0)
	health["drug_resistance"] = total_resistance
	var loss: float = 0.0
	if rng.next_float() < float(side.get("risk", 0.0)):
		loss = 6.0 if String(side.get("severity", "")) == "severe" else (3.0 if String(side.get("severity", "")) == "moderate" else 1.0)
		_damage_health(loss)
	player()["health"] = health
	_persist_medical()
	return {"ok": true, "days": maxi(0, days), "resistance": total_resistance,
		"effective": bool(resist.get("effective", true)) and total_resistance < 0.7,
		"side_effect_risk": float(side.get("risk", 0.0)), "side_effect_loss": loss}

func medical_treat(disease: String, method: String) -> Dictionary:
	var r: Dictionary = medical.treat(disease, method)
	_persist_medical()
	return r

func medtech_register(care_level: String, department: String) -> Dictionary:
	var r: Dictionary = medtech.register(_medical_region, care_level, department)
	_persist_medical()
	return r

func medtech_examine(care_level: String, exam: String) -> Dictionary:
	var r: Dictionary = medtech.examine(_medical_region, care_level, exam)
	_persist_medical()
	return r

func medtech_high_end(kind: String, source: String = "") -> Dictionary:
	var ctx: Dictionary = {"ethics_cleared": true, "legal_cleared": true, "roll": -1.0}
	if not source.is_empty():
		ctx["organ_source"] = source
	var r: Dictionary = medtech.high_end_procedure(kind, ctx, rng)
	_persist_medical()
	return r

func medtech_review_ethics(kind: String, score: float = 0.7) -> Dictionary:
	return medtech.review_ethics(kind, score)

func medtech_pharma_new(name: String = "医药公司") -> Dictionary:
	_pharma_company = medtech.new_pharma_company({"name": name, "money": 10000000})
	_persist_medical()
	return {"ok": true, "company": _pharma_company}

func medtech_pharma_start(drug_id: String) -> Dictionary:
	if _pharma_company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = medtech.start_drug(_pharma_company, drug_id)
	_persist_medical()
	return r

func medtech_pharma_advance(drug_id: String) -> Dictionary:
	if _pharma_company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = medtech.pharma_advance(_pharma_company, drug_id, {"roll": -1.0}, rng)
	_persist_medical()
	return r

func medtech_pharma_produce(drug_id: String, batches: float = 1.0) -> Dictionary:
	if _pharma_company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = medtech.pharma_produce(_pharma_company, drug_id, batches)
	_persist_medical()
	return r

func medtech_pharma_sell(drug_id: String, units: float = 100.0, unit_price: int = 1000) -> Dictionary:
	if _pharma_company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = medtech.pharma_sell(_pharma_company, drug_id, units, unit_price)
	_persist_medical()
	return r

func medtech_medical_rep(drug_id: String, effort: float = 0.5) -> Dictionary:
	if _pharma_company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = medtech.medical_rep(_pharma_company, drug_id, effort, {"roll": -1.0}, rng)
	_persist_medical()
	return r

func medtech_counterfeit(scale: float = 0.5) -> Dictionary:
	var r: Dictionary = medtech.counterfeit_drug({"scale": scale, "roll": -1.0}, rng)
	_persist_medical()
	return r

func medtech_dispute(severity: float = 0.5) -> Dictionary:
	var r: Dictionary = medtech.doctor_patient_dispute(severity)
	if not bool(r.get("litigation", false)):
		return r
	if not (_civil.get("claim", {}) as Dictionary).is_empty():
		r["civil_filed"] = false
		r["reason"] = "existing_claim"
		return r
	var amount: int = maxi(0, int(r.get("compensation", 0)))
	var claim: Dictionary = civil_sys.new_claim("tort", amount, "player", "hospital")
	claim["type_name"] = "医疗纠纷"
	claim["title"] = "医患损害赔偿"
	claim["evidence"] = 0.6
	_civil = {"claim": claim, "judgment": {}, "enforced": false, "appealed": false}
	var cid: String = "civil:%d:%d" % [now_minutes(), domain_wake.entry_count()]
	var due: int = now_minutes() + BaselineScript.WAKE_CASE_LIMIT_DAYS * BaselineScript.WAKE_MINUTES_PER_DAY
	domain_register(cid, DomainWakeScript.KIND_CASE, {
		"region_id": current_region_id(), "due_minute": due, "total": due - now_minutes(), "civil_id": cid,
	})
	_persist_civil()
	r["civil_filed"] = true
	r["case_id"] = cid
	r["amount"] = amount
	return r

func medtech_over_treatment(cost: int = 100000) -> Dictionary:
	return medtech.over_treatment(cost)

func medtech_insurance_fraud(claim: int = 100000) -> Dictionary:
	var r: Dictionary = medtech.insurance_fraud(claim, {"roll": -1.0}, rng)
	_persist_medical()
	return r

func medtech_trial_scandal(drug_id: String) -> Dictionary:
	if _pharma_company.is_empty():
		return {"ok": false, "reason": "no_company"}
	var r: Dictionary = medtech.trial_scandal(_pharma_company, drug_id, {"roll": -1.0}, rng)
	_persist_medical()
	return r

func medical_panel_data() -> Dictionary:
	var active: Array = []
	for c in medical.active_cases():
		var key: String = String((c as Dictionary).get("key", ""))
		var d: Dictionary = medical.DISEASES.get(key, {})
		active.append(String(d.get("name", key)))
	var out: Dictionary = {
		"disease_count": medical.diseases_count(),
		"active": active,
		"care_levels": medtech_care_levels_catalog(),
		"high_end": medtech_high_end_catalog(),
		"region": {
			"medical_level": float(_medical_region.get("medical_level", 1.0)),
			"cure_rate": float(_medical_region.get("cure_rate", 0.0)),
			"life_expectancy": float(_medical_region.get("life_expectancy", 0.0)),
		},
	}
	if not _pharma_company.is_empty():
		out["pharma"] = {
			"name": String(_pharma_company.get("name", "")),
			"money": int(_pharma_company.get("money", 0)),
			"drugs": (_pharma_company.get("pipeline", {}) as Dictionary).size(),
			"scandal": bool(_pharma_company.get("scandal", false)),
		}
	out["drug_resistance"] = float((player().get("health", {}) as Dictionary).get("drug_resistance", 0.0))
	out["insurance_fund"] = int(_medical_region.get("insurance_fund", 0))
	return out

func _persist_medical() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["medical"] = {
		"cases": medical._cases.duplicate(true),
		"surgeries": medical._surgeries.duplicate(true),
		"region": medtech.to_dict(_medical_region),
		"pharma": medtech.to_dict(_pharma_company),
	}


# --- D46 文娱内容产业 ---

const CONTENT_FUNDING_NAMES: Dictionary = {"seed": "种子轮", "angel": "天使轮", "a": "A 轮", "b": "B 轮", "c": "C 轮"}

func content_types_catalog() -> Array:
	var labels: Dictionary = {"game": "游戏", "anime": "动漫", "webnovel": "网文", "film": "影视", "variety": "综艺", "music": "音乐"}
	var aliases: Dictionary = {"game": ["游戏研发"], "anime": ["动漫制作"], "webnovel": ["网络文学"], "film": [], "variety": [], "music": ["音乐制作"]}
	var out: Array = []
	for key in content_industry.CONTENT_TYPES.keys():
		var k: String = String(key)
		out.append({"id": k, "name": String(labels.get(k, k)), "aliases": (aliases.get(k, []) as Array).duplicate()})
	return out

func content_roles_catalog() -> Array:
	var out: Array = []
	for key in content_industry.CREATION_ROLES.keys():
		out.append({"id": String(key), "name": String((content_industry.CREATION_ROLES[key] as Dictionary).get("name", key))})
	return out

func content_channels_catalog() -> Array:
	var out: Array = []
	for key in content_industry.CHANNELS.keys():
		out.append({"id": String(key), "name": String((content_industry.CHANNELS[key] as Dictionary).get("name", key))})
	return out

func content_platforms_catalog() -> Array:
	var out: Array = []
	for key in content_industry.PLATFORMS.keys():
		out.append({"id": String(key), "name": String((content_industry.PLATFORMS[key] as Dictionary).get("name", key))})
	return out

func content_ip_operations_catalog() -> Array:
	var out: Array = []
	for key in content_industry.IP_OPERATIONS.keys():
		out.append({"id": String(key), "name": String((content_industry.IP_OPERATIONS[key] as Dictionary).get("name", key))})
	return out

func content_funding_stages_catalog() -> Array:
	var out: Array = []
	for s in content_industry.FUNDING_STAGES:
		out.append({"id": String(s), "name": String(CONTENT_FUNDING_NAMES.get(String(s), String(s)))})
	return out

func content_studio() -> Dictionary:
	return _content_studio

func content_new_studio(name: String = "") -> Dictionary:
	var nm: String = name if not name.is_empty() else "文娱工作室"
	_content_studio = content_industry.new_studio({"id": "studio.player", "name": nm, "money": 10000000})
	_content_work = {}
	_content_ip_id = ""
	_persist_content()
	return {"ok": true, "name": String(_content_studio.get("name", nm))}

func content_hire(role: String, count: int) -> Dictionary:
	if _content_studio.is_empty():
		return {"ok": false, "reason": "no_studio"}
	var r: Dictionary = content_industry.hire(_content_studio, role, count)
	_persist_content()
	return r

func content_fire(role: String, count: int) -> Dictionary:
	if _content_studio.is_empty():
		return {"ok": false, "reason": "no_studio"}
	var r: Dictionary = content_industry.fire(_content_studio, role, count)
	_persist_content()
	return r

func content_new_work(content_type: String, title: String = "") -> Dictionary:
	if _content_studio.is_empty():
		return {"ok": false, "reason": "no_studio"}
	_content_seq += 1
	var wid: String = "work.%d" % _content_seq
	var ttl: String = title if not title.is_empty() else content_industry.content_type_name(content_type)
	var r: Dictionary = content_industry.new_work(wid, content_type, {"title": ttl})
	if not bool(r.get("ok", false)):
		return r
	_content_work = r["work"]
	_persist_content()
	return {"ok": true, "work_id": wid, "name": String(_content_work.get("title", wid))}

func content_manage(management: float = 0.5) -> Dictionary:
	if _content_work.is_empty():
		return {"ok": false, "reason": "no_work"}
	var r: Dictionary = content_industry.project_management(_content_work, {"management": management})
	_persist_content()
	return r

func content_advance(days: float = 30.0) -> Dictionary:
	if _content_work.is_empty() or _content_studio.is_empty():
		return {"ok": false, "reason": "no_work"}
	var r: Dictionary = content_industry.advance_project(_content_work, _content_studio, days, {"roll": -1.0}, rng)
	_persist_content()
	return r

func content_release() -> Dictionary:
	if _content_work.is_empty():
		return {"ok": false, "reason": "no_work"}
	var r: Dictionary = content_industry.release_work(_content_studio, _content_work, {"roll": -1.0}, rng)
	_persist_content()
	return r

func content_monetize(channel: String, platform: String = "") -> Dictionary:
	if _content_work.is_empty():
		return {"ok": false, "reason": "no_work"}
	var r: Dictionary = content_industry.monetize(_content_work, channel, {"platform": platform})
	_persist_content()
	return r

func content_register_ip() -> Dictionary:
	if _content_studio.is_empty() or _content_work.is_empty():
		return {"ok": false, "reason": "no_work"}
	var r: Dictionary = content_industry.register_ip(_content_studio, _content_work, {"id": "ip.%s" % String(_content_work.get("id", "w"))})
	if bool(r.get("ok", false)):
		_content_ip_id = String((r["ip"] as Dictionary).get("id", ""))
		# 与 D25 知识产权系统互通：作品版权同步登记为可授权、可维权资产。
		var legal_id: String = "ip.media.%s" % _content_ip_id
		var existing: bool = false
		for item in _ips:
			if String((item as Dictionary).get("id", "")) == legal_id:
				existing = true
				break
		if not existing:
			var legal: Dictionary = ip_media.register_ip("copyright", "player", String(_content_work.get("title", "")), {
				"id": legal_id, "created_minute": now_minutes(), "evidence": 0.8})
			if bool(legal.get("ok", false)):
				_ips.append(legal["ip"])
				(r["ip"] as Dictionary)["legal_ip_id"] = legal_id
				_persist_ip_media()
	_persist_content()
	return r

func _content_ip() -> Dictionary:
	if _content_ip_id.is_empty() or _content_studio.is_empty():
		return {}
	return (_content_studio.get("ip_library", {}) as Dictionary).get(_content_ip_id, {})

func content_adapt(target_type: String) -> Dictionary:
	var ip: Dictionary = _content_ip()
	if ip.is_empty():
		return {"ok": false, "reason": "no_ip"}
	var r: Dictionary = content_industry.adapt(ip, target_type)
	_persist_content()
	return r

func content_operate_ip(operation: String, scale: float = 1000000.0) -> Dictionary:
	var ip: Dictionary = _content_ip()
	if ip.is_empty():
		return {"ok": false, "reason": "no_ip"}
	var r: Dictionary = content_industry.operate_ip(ip, operation, scale, {"roll": -1.0}, rng)
	_persist_content()
	return r

func content_ip_universe() -> Dictionary:
	if _content_studio.is_empty():
		return {"ok": false, "reason": "no_studio"}
	var ips: Array = (_content_studio.get("ip_library", {}) as Dictionary).values()
	var r: Dictionary = content_industry.build_ip_universe(ips)
	_persist_content()
	return r

func content_plagiarism(similarity: float = 0.5, detect: float = 0.5) -> Dictionary:
	if _content_work.is_empty():
		return {"ok": false, "reason": "no_work"}
	var r: Dictionary = content_industry.plagiarism_check(_content_work, {"similarity": similarity, "detect_prob": detect, "roll": -1.0}, rng)
	_persist_content()
	return r

func content_compliance(risk: float = 0.3, strictness: float = 0.5) -> Dictionary:
	if _content_work.is_empty():
		return {"ok": false, "reason": "no_work"}
	var r: Dictionary = content_industry.content_compliance(_content_work, {"risk": risk, "strictness": strictness})
	_persist_content()
	return r

func content_takedown(reason: String = "content_violation", severity: float = 0.6) -> Dictionary:
	if _content_work.is_empty():
		return {"ok": false, "reason": "no_work"}
	var r: Dictionary = content_industry.take_down(_content_studio, _content_work, reason, {"severity": severity})
	_persist_content()
	return r

func content_scandal(severity: float = 0.6, exposure: float = 0.6) -> Dictionary:
	if _content_studio.is_empty():
		return {"ok": false, "reason": "no_studio"}
	var r: Dictionary = content_industry.scandal_event(_content_studio, {"severity": severity, "exposure": exposure, "roll": -1.0}, rng)
	_persist_content()
	return r

func content_funding(stage: String = "seed") -> Dictionary:
	if _content_studio.is_empty():
		return {"ok": false, "reason": "no_studio"}
	if not content_industry.FUNDING_STAGES.has(stage):
		return {"ok": false, "reason": "unknown_stage"}
	var r: Dictionary = content_industry.raise_funding(_content_studio, stage, {}, rng)
	_persist_content()
	return r

func content_poach(role: String, offer: float = 1.5) -> Dictionary:
	if _content_studio.is_empty():
		return {"ok": false, "reason": "no_studio"}
	var r: Dictionary = content_industry.poach_team(_content_studio, _content_rival, role, {"offer_mult": offer, "roll": -1.0}, rng)
	_persist_content()
	return r

func content_approval(content_type: String, strictness: float = 0.5) -> Dictionary:
	var r: Dictionary = content_industry.approval_delay(content_type, {"base_days": 30.0, "strictness": strictness, "roll": -1.0}, rng)
	return r

func content_fandom(growth: float = 0.1) -> Dictionary:
	if _content_studio.is_empty():
		return {"ok": false, "reason": "no_studio"}
	var r: Dictionary = content_industry.fandom_dynamics(_content_studio, {"growth": growth, "roll": -1.0}, rng)
	_persist_content()
	return r

func content_panel_data() -> Dictionary:
	if _content_studio.is_empty():
		return {}
	var out: Dictionary = {
		"studio": {
			"name": String(_content_studio.get("name", "")),
			"money": int(_content_studio.get("money", 0)),
			"reputation": float(_content_studio.get("reputation", 0.0)),
			"team_size": 0,
			"financing_stage": String((_content_studio.get("financing", {}) as Dictionary).get("stage", "")),
		},
		"team": [],
		"works": [],
		"ips": [],
		"fandom": {
			"size": int((_content_studio.get("fandom", {}) as Dictionary).get("size", 0)),
			"toxicity": float((_content_studio.get("fandom", {}) as Dictionary).get("toxicity", 0.0)),
		},
	}
	var team_size: int = 0
	for role in (_content_studio.get("team", {}) as Dictionary).keys():
		var e: Dictionary = _content_studio["team"][role]
		var cnt: int = int(e.get("count", 0))
		if cnt <= 0:
			continue
		team_size += cnt
		out["team"].append({
			"role": String(role),
			"name": String((content_industry.CREATION_ROLES.get(role, {}) as Dictionary).get("name", role)),
			"count": cnt,
			"skill": float(e.get("skill", 0.0)),
		})
	out["studio"]["team_size"] = team_size
	if not _content_work.is_empty():
		out["work"] = {
			"title": String(_content_work.get("title", "")),
			"type": String(_content_work.get("type", "")),
			"type_name": content_industry.content_type_name(String(_content_work.get("type", ""))),
			"progress": float(_content_work.get("progress", 0.0)),
			"required": float(_content_work.get("required_progress", 1.0)),
			"quality": float(_content_work.get("quality", 0.0)),
			"status": String(_content_work.get("status", "")),
			"revenue": int(_content_work.get("revenue", 0)),
			"controversy": float(_content_work.get("controversy", 0.0)),
		}
	for w in _content_studio.get("catalog", []):
		out["works"].append({
			"title": String((w as Dictionary).get("title", "")),
			"type": String((w as Dictionary).get("type", "")),
			"quality": float((w as Dictionary).get("quality", 0.0)),
			"performance": float((w as Dictionary).get("performance", 0.0)),
		})
	for key in (_content_studio.get("ip_library", {}) as Dictionary).keys():
		var ip: Dictionary = _content_studio["ip_library"][key]
		out["ips"].append({
			"title": String(ip.get("title", "")),
			"power": float(ip.get("power", 0.0)),
			"universe": String(ip.get("universe", "")),
			"adaptations": (ip.get("adaptations", []) as Array).size(),
		})
	return out

func _persist_content() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["content"] = {
		"studio": content_industry.to_dict(_content_studio),
		"work": content_industry.to_dict(_content_work),
		"rival": content_industry.to_dict(_content_rival),
		"ip_id": _content_ip_id,
		"seq": _content_seq,
	}


# --- D47 建筑、工程与城市规划 ---

func engineering_qualifications_catalog() -> Array:
	var out: Array = []
	for key in engineering.QUALIFICATIONS.keys():
		out.append({"id": String(key), "name": String((engineering.QUALIFICATIONS[key] as Dictionary).get("name", key))})
	return out

func engineering_stages_catalog() -> Array:
	var out: Array = []
	for key in engineering.CHAIN:
		var d: Dictionary = engineering.STAGES.get(key, {})
		out.append({"id": String(key), "name": String(d.get("name", key))})
	return out

func engineering_procurement_catalog() -> Array:
	var out: Array = []
	for key in engineering.PROCUREMENT_MODES.keys():
		out.append({"id": String(key), "name": String((engineering.PROCUREMENT_MODES[key] as Dictionary).get("name", key))})
	return out

func engineering_zone_types_catalog() -> Array:
	var out: Array = []
	for key in engineering.ZONE_TYPES.keys():
		out.append({"id": String(key), "name": String((engineering.ZONE_TYPES[key] as Dictionary).get("name", key))})
	return out

func engineering_contractor() -> Dictionary:
	return _eng_contractor

func eng_new_contractor(name: String = "", qualification: String = "second") -> Dictionary:
	var nm: String = name if not name.is_empty() else "我的建设公司"
	if not engineering.QUALIFICATIONS.has(qualification):
		return {"ok": false, "reason": "unknown_qualification"}
	_eng_contractor = engineering.new_contractor({
		"id": "contractor.player", "name": nm, "qualification": qualification,
		"capital": int((engineering.QUALIFICATIONS[qualification] as Dictionary)["min_capital"]),
		"workmanship": 0.7, "relationship": 0.5, "reputation": 0.6,
	})
	_persist_engineering()
	return {"ok": true, "name": String(_eng_contractor.get("name", nm)), "qualification": qualification}

func eng_take_project(name: String = "", scale: int = 50000000) -> Dictionary:
	if _eng_contractor.is_empty():
		return {"ok": false, "reason": "no_contractor"}
	_eng_project = engineering.new_project({"name": name if not name.is_empty() else "承接工程", "scale": maxi(1, scale), "budget": maxi(1, scale)})
	_persist_engineering()
	_wake_track_project()
	return {
		"ok": true, "name": String(_eng_project.get("name", "")),
		"required_qualification": String(_eng_project.get("required_qualification", "")),
	}

## 把当前在建工程登记进休眠补算（进度按阶段折算，手动推进后同步）。
func _wake_track_project() -> void:
	if _eng_project.is_empty():
		return
	var pid: String = String(_eng_project.get("id", ""))
	var total: float = float(engineering.CHAIN.size())
	domain_register("eng:%s" % pid, DomainWakeScript.KIND_PROJECT, {
		"region_id": current_region_id(),
		"total": total,
		"progress": float(_eng_project.get("stage_index", 0)),
		"rate": 1.0 / float(BaselineScript.WAKE_PROJECT_STAGE_DAYS * BaselineScript.WAKE_MINUTES_PER_DAY),
		"project_id": pid,
	})

func eng_advance() -> Dictionary:
	if _eng_project.is_empty() or _eng_contractor.is_empty():
		return {"ok": false, "reason": "no_project"}
	var before: int = int(_eng_project.get("stage_index", 0))
	var r: Dictionary = engineering.advance_stage(_eng_project, _eng_contractor, {}, rng)
	if bool(r.get("ok", false)):
		r["stage"] = String(engineering.CHAIN[before]) if before < engineering.CHAIN.size() else ""
		r["next"] = String(_eng_project.get("stage", ""))
		var pid: String = String(_eng_project.get("id", ""))
		var done: bool = int(_eng_project.get("stage_index", 0)) >= engineering.CHAIN.size()
		domain_wake.set_progress("eng:%s" % pid, float(_eng_project.get("stage_index", 0)), "completed" if done else "in_progress")
		_persist_domain_wake()
	_persist_engineering()
	return r

func eng_supervise(strength: float = 0.5) -> Dictionary:
	if _eng_project.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = engineering.supervise(_eng_project, {"supervision_strength": clampf(strength, 0.0, 1.0), "roll": -1.0}, rng)
	_persist_engineering()
	return r

func eng_tender() -> Dictionary:
	if _eng_project.is_empty() or _eng_contractor.is_empty():
		return {"ok": false, "reason": "no_project"}
	var bidders: Array = _eng_bidders()
	var r: Dictionary = engineering.tender(_eng_project, bidders, {"roll": -1.0}, rng)
	if bool(r.get("ok", false)) and String(r.get("winner", "")) == "contractor.player":
		r["won"] = true
	_persist_engineering()
	return r

func _eng_bidders() -> Array:
	var out: Array = []
	var budget: int = maxi(1, int(_eng_project.get("budget", 1)))
	if not _eng_contractor.is_empty():
		out.append({
			"id": "contractor.player", "qualification": String(_eng_contractor.get("qualification", "second")),
			"price": int(round(float(budget) * 0.95)), "relationship": float(_eng_contractor.get("relationship", 0.5)),
			"reputation": float(_eng_contractor.get("reputation", 0.6)),
		})
	for rv in _eng_rivals:
		var c: Dictionary = rv
		out.append({
			"id": String(c.get("id", "")), "qualification": String(c.get("qualification", "second")),
			"price": int(round(float(budget) * (0.9 + float(c.get("reputation", 0.5)) * 0.15))),
			"relationship": float(c.get("relationship", 0.4)), "reputation": float(c.get("reputation", 0.5)),
		})
	return out

func eng_rig() -> Dictionary:
	if _eng_project.is_empty() or _eng_contractor.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = engineering.rig_bids(_eng_bidders(), "contractor.player", {"collusion_bonus": 0.5, "accomplice_price_mult": 1.25})
	_persist_engineering()
	return r

func eng_bribe(amount: int = 5000000) -> Dictionary:
	if _eng_project.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = engineering.tender_corruption(_eng_project, {"bribe": maxi(0, amount), "roll": -1.0}, rng)
	_persist_engineering()
	return r

func eng_cut_corners(degree: float = 0.3) -> Dictionary:
	if _eng_project.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = engineering.cut_corners(_eng_project, clampf(degree, 0.0, 1.0), {})
	_persist_engineering()
	return r

func eng_accident() -> Dictionary:
	if _eng_project.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = engineering.engineering_accident(_eng_project, {"roll": -1.0}, rng)
	_persist_engineering()
	return r

func eng_arrears(amount: int = 10000000) -> Dictionary:
	if _eng_contractor.is_empty():
		return {"ok": false, "reason": "no_contractor"}
	var r: Dictionary = engineering.arrears(_eng_contractor, maxi(0, amount), {})
	_persist_engineering()
	return r

func eng_debt_chain(amount: int = 10000000) -> Dictionary:
	var r: Dictionary = engineering.debt_chain(["业主", "总包", "分包"], maxi(0, amount), {"start_default": 0, "contagion": 0.6})
	return r

func eng_new_city(name: String = "", population: int = 1000000) -> Dictionary:
	_eng_city = engineering.new_city({"name": name if not name.is_empty() else "我的城市", "population": maxi(0, population)})
	_persist_engineering()
	return {"ok": true, "name": String(_eng_city.get("name", ""))}

func eng_rezone(zone_id: String, zone_type: String) -> Dictionary:
	if _eng_city.is_empty():
		return {"ok": false, "reason": "no_city"}
	var r: Dictionary = engineering.rezone(_eng_city, zone_id, zone_type, {"migration_rate": 0.05})
	if bool(r.get("ok", false)):
		_persist_engineering()
	return r

func eng_transport(zone_id: String) -> Dictionary:
	if _eng_city.is_empty():
		return {"ok": false, "reason": "no_city"}
	var r: Dictionary = engineering.transport_project(_eng_city, zone_id, {"improvement": 0.2})
	_persist_engineering()
	return r

func eng_planning_corruption(bribe: int = 10000000) -> Dictionary:
	if _eng_city.is_empty():
		return {"ok": false, "reason": "no_city"}
	var r: Dictionary = engineering.planning_corruption(_eng_city, {"bribe": maxi(0, bribe), "roll": -1.0}, rng)
	_persist_engineering()
	return r

func eng_demolition(zone_id: String, residents: int = 1000, compensation: int = 300000) -> Dictionary:
	if _eng_city.is_empty():
		return {"ok": false, "reason": "no_city"}
	var r: Dictionary = engineering.demolition(_eng_city, zone_id, {"residents": maxi(0, residents), "compensation_per": maxi(0, compensation)})
	if bool(r.get("ok", false)):
		_persist_engineering()
	return r

func eng_new_developer(name: String = "", cash: int = 50000000) -> Dictionary:
	_eng_developer = engineering.new_developer({"name": name if not name.is_empty() else "我的地产公司", "cash": maxi(0, cash)})
	_persist_engineering()
	return {"ok": true, "name": String(_eng_developer.get("name", ""))}

func eng_pre_sale(units: int = 10, unit_price: int = 1000000) -> Dictionary:
	if _eng_developer.is_empty():
		return {"ok": false, "reason": "no_developer"}
	if _eng_project.is_empty():
		_eng_project = engineering.new_project({"name": "楼盘", "scale": maxi(1, units * maxi(1, unit_price)), "budget": maxi(1, units * maxi(1, unit_price))})
	_eng_project["unit_price"] = maxi(0, unit_price)
	_eng_project["remaining_cost"] = int(round(float(units) * float(maxi(1, unit_price)) * 0.7))
	var r: Dictionary = engineering.pre_sale(_eng_developer, _eng_project, maxi(0, units), maxi(0, unit_price), {})
	_persist_engineering()
	return r

func eng_develop(cost: int = 5000000) -> Dictionary:
	if _eng_developer.is_empty() or _eng_project.is_empty():
		return {"ok": false, "reason": "no_developer"}
	var r: Dictionary = engineering.develop_project(_eng_developer, _eng_project, maxi(0, cost), {"pace": 0.2})
	_persist_engineering()
	return r

func eng_unfinished() -> Dictionary:
	if _eng_developer.is_empty() or _eng_project.is_empty():
		return {"ok": false, "reason": "no_developer"}
	var r: Dictionary = engineering.unfinished(_eng_developer, _eng_project, {})
	_persist_engineering()
	return r

func engineering_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _eng_contractor.is_empty():
		out["contractor"] = {
			"name": String(_eng_contractor.get("name", "")),
			"qualification": String(_eng_contractor.get("qualification", "")),
			"capital": int(_eng_contractor.get("capital", 0)),
			"workmanship": float(_eng_contractor.get("workmanship", 0.0)),
			"reputation": float(_eng_contractor.get("reputation", 0.0)),
		}
	if not _eng_project.is_empty():
		out["project"] = {
			"name": String(_eng_project.get("name", "")),
			"stage": String(_eng_project.get("stage", "")),
			"stage_name": String((engineering.STAGES.get(String(_eng_project.get("stage", "")), {}) as Dictionary).get("name", _eng_project.get("stage", ""))),
			"progress": float(_eng_project.get("progress", 0.0)),
			"quality": float(_eng_project.get("quality", 0.0)),
			"budget": int(_eng_project.get("budget", 0)),
			"accepted": bool(_eng_project.get("accepted", false)),
			"accident": bool(_eng_project.get("accident", false)),
		}
	if not _eng_city.is_empty():
		var zones: Array = []
		for zid in (_eng_city.get("zones", {}) as Dictionary).keys():
			var z: Dictionary = _eng_city["zones"][zid]
			zones.append({
				"zone": String(zid),
				"type": String(z.get("type", "")),
				"type_name": String((engineering.ZONE_TYPES.get(String(z.get("type", "")), {}) as Dictionary).get("name", z.get("type", ""))),
				"land_price": float(z.get("land_price", 0.0)),
			})
		out["city"] = {
			"name": String(_eng_city.get("name", "")),
			"population": int(_eng_city.get("population", 0)),
			"land_price": float(_eng_city.get("land_price", 0.0)),
			"traffic": float(_eng_city.get("traffic", 0.0)),
			"zones": zones,
		}
	if not _eng_developer.is_empty():
		out["developer"] = {
			"name": String(_eng_developer.get("name", "")),
			"cash": int(_eng_developer.get("cash", 0)),
			"debt": int(_eng_developer.get("debt", 0)),
		}
	return out

func _persist_engineering() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["engineering"] = {
		"contractor": engineering.to_dict(_eng_contractor),
		"project": engineering.to_dict(_eng_project),
		"city": engineering.to_dict(_eng_city),
		"developer": engineering.to_dict(_eng_developer),
	}


# --- 科研流程与成果转化（D5 / R45.4-5） ---

func research_state() -> Dictionary:
	return _research.duplicate(true)

## 科研运行时惰性初始化：默认具备实验室与基础团队，经费由玩家注入。
func _ensure_research() -> void:
	if not _research.is_empty():
		return
	_research = {
		"project": {},
		"resources": {"lab": true, "equipment": 1, "team": 2, "funding": 0},
		"prestige": 0.0,
		"citations": 0,
		"income": 0,
	}

## 科研经费注入：从玩家现金转入实验室经费池。
func research_fund(amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "reason": "bad_amount"}
	if int(economy.cash(account_id())) < amount:
		return {"ok": false, "reason": "insufficient_funds"}
	_ensure_research()
	economy.add_money(account_id(), -amount, "research_fund")
	var res: Dictionary = _research["resources"]
	res["funding"] = int(res.get("funding", 0)) + amount
	_persist_research()
	return {"ok": true, "funding": int(res["funding"])}

## 立项：校验实验室/仪器/团队/经费并扣除启动经费。
func research_start(topic: String) -> Dictionary:
	_ensure_research()
	var r: Dictionary = research_sys.start_project(topic, _research["resources"])
	if bool(r.get("ok", false)):
		_research["project"] = r["project"]
		_persist_research()
	return r

## 推进一段：文献→实验→数据→论文→同行评审→发表/退稿。
func research_advance() -> Dictionary:
	_ensure_research()
	var project: Dictionary = _research.get("project", {})
	if project.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = research_sys.advance(project, _research["resources"], {
		"skills": player().get("skills", []),
		"investment": 60.0,
		"innovation": 60.0,
		"competition": 20.0,
		"rng": rng,
	})
	if bool(r.get("ok", false)):
		_persist_research()
	return r

## 成果结算：发表后声望/引用/收入入账，仅可结算一次。
func research_collect() -> Dictionary:
	_ensure_research()
	var project: Dictionary = _research.get("project", {})
	if project.is_empty():
		return {"ok": false, "reason": "no_project"}
	if bool(project.get("collected", false)):
		return {"ok": false, "reason": "already_collected"}
	var r: Dictionary = research_sys.collect(project, economy, account_id())
	if bool(r.get("ok", false)):
		project["collected"] = true
		_research["prestige"] = float(_research.get("prestige", 0.0)) + float(r.get("prestige", 0.0))
		_research["citations"] = int(_research.get("citations", 0)) + int(r.get("citations", 0))
		_research["income"] = int(_research.get("income", 0)) + int(r.get("income", 0))
		_persist_research()
	return r

## 申请专利并登记知识产权；登记失败则回滚专利标记。
func research_file_patent() -> Dictionary:
	_ensure_research()
	var project: Dictionary = _research.get("project", {})
	if project.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = research_sys.file_patent(project)
	if not bool(r.get("ok", false)):
		return r
	var ipr: Dictionary = register_ip_asset("patent", String(project.get("topic", "")))
	if not bool(ipr.get("ok", false)):
		project["patented"] = false
		_persist_research()
		return ipr
	project["patent_ip"] = String((ipr.get("ip", {}) as Dictionary).get("id", ""))
	_persist_research()
	return {"ok": true, "patent": r.get("patent", {}), "ip": ipr.get("ip", {}), "fee": int(ipr.get("fee", 0))}

func research_panel_data() -> Dictionary:
	if _research.is_empty():
		return {}
	var project: Dictionary = _research.get("project", {})
	var res: Dictionary = _research.get("resources", {})
	var out: Dictionary = {
		"resources": {
			"lab": bool(res.get("lab", false)),
			"equipment": int(res.get("equipment", 0)),
			"team": int(res.get("team", 0)),
			"funding": int(res.get("funding", 0)),
		},
		"prestige": float(_research.get("prestige", 0.0)),
		"citations": int(_research.get("citations", 0)),
		"income": int(_research.get("income", 0)),
	}
	if not project.is_empty():
		out["project"] = {
			"topic": String(project.get("topic", "")),
			"stage": String(project.get("stage", "")),
			"quality": float(project.get("quality", 0.0)),
			"published": bool(project.get("published", false)),
			"patented": bool(project.get("patented", false)),
			"citations": int(project.get("citations", 0)),
		}
	return out

func _persist_research() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["research"] = _research.duplicate(true)


# --- D48 专业服务业 ---

func prof_practice_types_catalog() -> Array:
	var out: Array = []
	for key in professional.PRACTICE_TYPES.keys():
		out.append({"id": String(key), "name": String((professional.PRACTICE_TYPES[key] as Dictionary).get("name", key))})
	return out

func prof_qualifications_catalog() -> Array:
	var out: Array = []
	for key in professional.QUALIFICATIONS.keys():
		out.append({"id": String(key), "name": String((professional.QUALIFICATIONS[key] as Dictionary).get("name", key))})
	return out

func professional_firm() -> Dictionary:
	return _prof_firm

func prof_new_firm(name: String = "") -> Dictionary:
	var nm: String = name if not name.is_empty() else "我的事务所"
	_prof_firm = professional.new_firm({"id": "firm.player", "name": nm, "money": 5000000})
	_prof_project = {}
	_persist_professional()
	return {"ok": true, "name": String(_prof_firm.get("name", nm))}

func prof_acquire(cert: String) -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var r: Dictionary = professional.acquire_qualification(_prof_firm, cert, {"skill": 0.8, "roll": -1.0}, rng)
	_persist_professional()
	return r

func prof_client() -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var r: Dictionary = professional.client_acquisition(_prof_firm, {"roll": -1.0}, rng)
	_persist_professional()
	return r

func prof_new_project(practice: String, client_id: String = "") -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var cid: String = client_id if not client_id.is_empty() else "客户"
	var r: Dictionary = professional.new_project(_prof_firm, cid, practice, {})
	if bool(r.get("ok", false)):
		_prof_project = r["project"]
	_persist_professional()
	return r

func prof_due_diligence(depth: float = 0.5) -> Dictionary:
	if _prof_project.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = professional.due_diligence(_prof_project, {"depth": clampf(depth, 0.0, 1.0), "roll": -1.0}, rng)
	_persist_professional()
	return r

func prof_ma_advisory(deal_size: int = 10000000) -> Dictionary:
	if _prof_project.is_empty():
		return {"ok": false, "reason": "no_project"}
	var r: Dictionary = professional.ma_advisory(_prof_project, {"deal_size": maxi(0, deal_size), "roll": -1.0}, rng)
	_persist_professional()
	return r

func prof_independence(roles: Array) -> Dictionary:
	return professional.independence_conflict({"roles": roles}, {})

func prof_false_report(severity: float = 0.6) -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var r: Dictionary = professional.false_report(_prof_firm, _prof_project, {"severity": clampf(severity, 0.0, 1.0), "roll": -1.0}, rng)
	_persist_professional()
	return r

func prof_insider(profit: int = 1000000) -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var r: Dictionary = professional.insider_trading(_prof_firm, {"profit": maxi(0, profit), "roll": -1.0}, rng)
	_persist_professional()
	return r

func prof_bribery(amount: int = 500000) -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var r: Dictionary = professional.commercial_bribery(_prof_firm, {"amount": maxi(0, amount), "roll": -1.0}, rng)
	_persist_professional()
	return r

func prof_add_partner(partner_id: String, share: float = 0.2, clients: int = 0) -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	if partner_id.strip_edges().is_empty():
		return {"ok": false, "reason": "bad_partner"}
	var r: Dictionary = professional.add_partner(_prof_firm, partner_id, {"share": clampf(share, 0.0, 0.9), "clients": maxi(0, clients)})
	_persist_professional()
	return r

func prof_partner_split(partner_id: String) -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var r: Dictionary = professional.partner_split(_prof_firm, partner_id, {"roll": -1.0}, rng)
	_persist_professional()
	return r

func prof_non_compete() -> Dictionary:
	return professional.non_compete_violation({})

func prof_churn() -> Dictionary:
	if _prof_firm.is_empty():
		return {"ok": false, "reason": "no_firm"}
	var r: Dictionary = professional.client_churn(_prof_firm, {"roll": -1.0}, rng)
	_persist_professional()
	return r

func professional_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _prof_firm.is_empty():
		var quals: Array = []
		for cert in (_prof_firm.get("qualifications", {}) as Dictionary).keys():
			quals.append(String((professional.QUALIFICATIONS.get(cert, {}) as Dictionary).get("name", cert)))
		out["firm"] = {
			"name": String(_prof_firm.get("name", "")),
			"money": int(_prof_firm.get("money", 0)),
			"reputation": float(_prof_firm.get("reputation", 0.0)),
			"qualifications": quals,
			"partners": (_prof_firm.get("partners", {}) as Dictionary).size(),
			"clients": (_prof_firm.get("clients", {}) as Dictionary).size(),
			"violations": (_prof_firm.get("violations", []) as Array).size(),
			"projects": (_prof_firm.get("projects", []) as Array).size(),
		}
	if not _prof_project.is_empty():
		out["project"] = {
			"id": String(_prof_project.get("id", "")),
			"practice": String(_prof_project.get("practice", "")),
			"practice_name": String((professional.PRACTICE_TYPES.get(String(_prof_project.get("practice", "")), {}) as Dictionary).get("name", _prof_project.get("practice", ""))),
			"fee": int(_prof_project.get("fee", 0)),
			"status": String(_prof_project.get("status", "")),
			"findings": (_prof_project.get("findings", []) as Array).size(),
		}
	return out

func _persist_professional() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["professional"] = {
		"firm": professional.to_dict(_prof_firm),
		"project": professional.to_dict(_prof_project),
	}


# --- 家庭与生活服务业（D49 / R93） ---

func life_service_categories_catalog() -> Array:
	var out: Array = []
	for key in life_services.SERVICE_CATEGORIES.keys():
		out.append({"id": String(key), "name": String((life_services.SERVICE_CATEGORIES[key] as Dictionary).get("name", key))})
	return out

func life_pet_service_catalog() -> Array:
	var out: Array = []
	for key in life_services.PET_CHAIN.keys():
		out.append({"id": String(key), "name": String((life_services.PET_CHAIN[key] as Dictionary).get("name", key))})
	return out

func life_provider() -> Dictionary:
	return _life_provider

func life_new_provider(name: String = "", category: String = "housekeeping") -> Dictionary:
	if not life_services.SERVICE_CATEGORIES.has(category):
		return {"ok": false, "reason": "unknown_category"}
	var nm: String = name if not name.is_empty() else "服务者"
	_life_provider = life_services.new_provider({"id": "provider.player", "name": nm, "category": category})
	_life_order = {}
	_persist_life_services()
	return {"ok": true, "name": String(_life_provider.get("name", nm)), "category": category}

func life_background_check() -> Dictionary:
	if _life_provider.is_empty():
		return {"ok": false, "reason": "no_provider"}
	var r: Dictionary = life_services.background_check(_life_provider, {"roll": -1.0}, rng)
	_persist_life_services()
	return r

func life_new_order(service: String = "", price: int = 1000) -> Dictionary:
	if _life_provider.is_empty():
		return {"ok": false, "reason": "no_provider"}
	var svc: String = service if not service.is_empty() else String(_life_provider.get("category", "housekeeping"))
	var r: Dictionary = life_services.new_order(_life_provider, {"service": svc, "price": maxi(0, price)})
	if bool(r.get("ok", false)):
		_life_order = r["order"]
	_persist_life_services()
	return r

func life_matchmaking() -> Dictionary:
	if _life_provider.is_empty():
		return {"ok": false, "reason": "no_provider"}
	var candidates: Array = [
		{"id": "cand.1", "name": "林小姐", "compatibility": 0.70, "wealth": 0.30},
		{"id": "cand.2", "name": "赵先生", "compatibility": 0.50, "wealth": 0.60},
		{"id": "cand.3", "name": "周女士", "compatibility": 0.80, "wealth": 0.20},
	]
	return life_services.matchmaking(_life_provider, candidates, {"roll": -1.0}, rng)

func life_wedding(budget: int = 50000, quality: float = 0.6) -> Dictionary:
	if _life_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	var r: Dictionary = life_services.wedding_plan(_life_provider, _life_order, {"budget": maxi(0, budget), "quality": clampf(quality, 0.0, 1.0), "roll": -1.0}, rng)
	_persist_life_services()
	return r

func life_housekeeping() -> Dictionary:
	if _life_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	var r: Dictionary = life_services.housekeeping_order(_life_provider, _life_order, {"roll": -1.0}, rng)
	_persist_life_services()
	return r

func life_pet_service(service: String) -> Dictionary:
	if _life_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	if not life_services.PET_CHAIN.has(service):
		return {"ok": false, "reason": "unknown_pet_stage"}
	_life_order["service"] = service
	var r: Dictionary = life_services.pet_service_order(_life_provider, _life_order, {"roll": -1.0}, rng)
	# 与 D11 宠物系统联动：服务结果落到玩家实际宠物身上。
	var target: Dictionary = {}
	for p in pets():
		if p is Dictionary and bool(p.get("alive", true)):
			target = p
			break
	if not target.is_empty() and bool(r.get("ok", false)) and not bool(r.get("incident", false)):
		match service:
			"boarding":
				target["mood"] = clampf(float(target.get("mood", 50.0)) + 8.0, 0.0, 100.0)
				target["bond"] = clampf(float(target.get("bond", 0.0)) + 3.0, 0.0, 100.0)
			"grooming":
				target["mood"] = clampf(float(target.get("mood", 50.0)) + 10.0, 0.0, 100.0)
			"medical":
				target["health"] = clampf(float(target.get("health", 50.0)) + 30.0, 0.0, 100.0)
				economy.add_money(account_id(), -50000, "pet:vet")
			"training":
				target["skill"] = clampf(float(target.get("skill", 0.0)) + 5.0, 0.0, 100.0)
				target["bond"] = clampf(float(target.get("bond", 0.0)) + 4.0, 0.0, 100.0)
			"funeral":
				target["alive"] = false
				target["health"] = 0.0
		(r as Dictionary)["pet_name"] = String(target.get("name", ""))
	_persist_life_services()
	return r

func life_incident(severity: float = 0.5) -> Dictionary:
	if _life_provider.is_empty():
		return {"ok": false, "reason": "no_provider"}
	var r: Dictionary = life_services.service_incident(_life_provider, _life_order, {"severity": clampf(severity, 0.0, 1.0), "roll": -1.0}, rng)
	_persist_life_services()
	return r

func life_resolve_dispute(claim: int = 0, severity: float = 0.5) -> Dictionary:
	if _life_order.is_empty():
		return {"ok": false, "reason": "no_order"}
	var r: Dictionary = life_services.resolve_dispute(_life_provider, _life_order, {"claim": maxi(0, claim), "severity": clampf(severity, 0.0, 1.0)})
	_persist_life_services()
	return r

func life_commission(price: int = 1000) -> Dictionary:
	if _life_provider.is_empty():
		return {"ok": false, "reason": "no_provider"}
	return life_services.platform_commission(maxi(0, price), String(_life_provider.get("category", "housekeeping")))

func life_standardize(invest: int = 100000, level: float = 0.5) -> Dictionary:
	if _life_provider.is_empty():
		return {"ok": false, "reason": "no_provider"}
	return life_services.standardization(String(_life_provider.get("category", "housekeeping")), {"invest": maxi(0, invest), "level": clampf(level, 0.0, 1.0)})

func life_services_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _life_provider.is_empty():
		out["provider"] = {
			"name": String(_life_provider.get("name", "")),
			"category": String(_life_provider.get("category", "")),
			"category_name": String((life_services.SERVICE_CATEGORIES.get(String(_life_provider.get("category", "")), {}) as Dictionary).get("name", _life_provider.get("category", ""))),
			"rating": float(_life_provider.get("rating", 0.0)),
			"trust": float(_life_provider.get("trust", 0.0)),
			"background": String(_life_provider.get("background", "unknown")),
			"orders": (_life_provider.get("orders", []) as Array).size(),
			"disputes": (_life_provider.get("disputes", []) as Array).size(),
		}
	if not _life_order.is_empty():
		out["order"] = {
			"id": String(_life_order.get("id", "")),
			"service": String(_life_order.get("service", "")),
			"price": int(_life_order.get("price", 0)),
			"status": String(_life_order.get("status", "")),
		}
	return out

func _persist_life_services() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["life_services"] = {
		"provider": life_services.to_dict(_life_provider),
		"order": life_services.to_dict(_life_order),
	}


# --- 交通基建与航运（D50 / R94） ---

func tin_infra_types_catalog() -> Array:
	var out: Array = []
	for key in transport_infra.INFRA_TYPES.keys():
		out.append({"id": String(key), "name": String((transport_infra.INFRA_TYPES[key] as Dictionary).get("name", key))})
	return out

func tin_modes_catalog() -> Array:
	var out: Array = []
	for key in transport_infra.MODES.keys():
		out.append({"id": String(key), "name": String((transport_infra.MODES[key] as Dictionary).get("name", key))})
	return out

func tin_project() -> Dictionary:
	return _tin_project

func _tin_default_region() -> Dictionary:
	return {"region": "home", "accessibility": 0.5, "land_price": 10000.0, "gdp": 1000000.0, "population": 100000.0}

func tin_new_project(type: String = "highway", scale: float = 1.0) -> Dictionary:
	if _tin_region.is_empty():
		_tin_region = _tin_default_region()
	_tin_project = transport_infra.new_infra_project({"type": type, "scale": clampf(scale, 0.1, 10.0), "region": String(_tin_region.get("region", "home"))})
	_tin_route = {}
	_persist_transport_infra()
	return {"ok": true, "project": _tin_project}

func tin_tender() -> Dictionary:
	if _tin_project.is_empty():
		return {"ok": false, "reason": "no_infra"}
	var bids: Array = [
		{"id": "bid.a", "price": float(_tin_project.get("cost_estimate", 0)) * 1.02, "qualification_score": 0.70, "relationship": 0.2},
		{"id": "bid.b", "price": float(_tin_project.get("cost_estimate", 0)) * 0.98, "qualification_score": 0.60, "relationship": 0.1},
		{"id": "bid.c", "price": float(_tin_project.get("cost_estimate", 0)) * 1.08, "qualification_score": 0.85, "relationship": 0.0},
	]
	var r: Dictionary = transport_infra.tender_infra(_tin_project, bids, {}, rng)
	_persist_transport_infra()
	return r

func tin_build(pace: float = 0.5) -> Dictionary:
	if _tin_project.is_empty():
		return {"ok": false, "reason": "no_infra"}
	var r: Dictionary = transport_infra.build(_tin_project, {"pace": clampf(pace, 0.0, 1.0), "roll": -1.0}, rng)
	_persist_transport_infra()
	return r

func tin_operate(mode: String = "logistics", fare: float = 50.0) -> Dictionary:
	if _tin_project.is_empty():
		return {"ok": false, "reason": "no_infra"}
	if not transport_infra.MODES.has(mode):
		return {"ok": false, "reason": "unknown_tin_mode"}
	var r: Dictionary = transport_infra.operate(_tin_project, {"mode": mode, "fare": maxf(0.0, fare), "roll": -1.0}, rng)
	_tin_route = {"mode": mode, "fare": fare, "profit": int(r.get("profit", 0)), "on_time_rate": float(r.get("on_time_rate", 0.0)), "suspended": false}
	_persist_transport_infra()
	return r

func tin_regional_impact() -> Dictionary:
	if _tin_project.is_empty():
		return {"ok": false, "reason": "no_infra"}
	if _tin_region.is_empty():
		_tin_region = _tin_default_region()
	var r: Dictionary = transport_infra.regional_impact(_tin_project, _tin_region, {"migration": 1.0})
	_persist_transport_infra()
	return r

func tin_network() -> Dictionary:
	var nodes: Array = [{"hub": true}, {"hub": false}, {"hub": true}, {"hub": false}]
	var routes: Array = [{"a": 0, "b": 1}, {"a": 1, "b": 2}, {"a": 2, "b": 3}]
	return transport_infra.network_effect(nodes, routes, {})

func tin_subsidy(amount: int = -1) -> Dictionary:
	if _tin_project.is_empty():
		return {"ok": false, "reason": "no_infra"}
	var opts: Dictionary = {}
	if amount >= 0:
		opts["amount"] = amount
	var r: Dictionary = transport_infra.subsidy(_tin_project, opts)
	_persist_transport_infra()
	return r

func tin_settle(operating_profit: int = 0) -> Dictionary:
	if _tin_project.is_empty():
		return {"ok": false, "reason": "no_infra"}
	return transport_infra.settle(_tin_project, {"operating_profit": operating_profit})

func tin_accident(cut_corners: float = 0.0) -> Dictionary:
	if _tin_project.is_empty():
		return {"ok": false, "reason": "no_infra"}
	var r: Dictionary = transport_infra.infra_accident(_tin_project, {"cut_corners": clampf(cut_corners, 0.0, 1.0), "roll": -1.0}, rng)
	_persist_transport_infra()
	return r

func tin_monopoly(market_share: float = 0.5, price: float = 100.0) -> Dictionary:
	return transport_infra.monopoly_regulation({"market_share": clampf(market_share, 0.0, 1.0), "price": maxf(0.0, price)})

func tin_disruption(sensitivity: float = 0.5) -> Dictionary:
	if _tin_route.is_empty():
		return {"ok": false, "reason": "no_route"}
	var r: Dictionary = transport_infra.international_disruption(_tin_route, {"sensitivity": clampf(sensitivity, 0.0, 1.0), "roll": -1.0}, rng)
	_persist_transport_infra()
	return r

func tin_panel_data() -> Dictionary:
	var out: Dictionary = {}
	if not _tin_project.is_empty():
		out["project"] = {
			"id": String(_tin_project.get("id", "")),
			"type": String(_tin_project.get("type", "")),
			"type_name": String((transport_infra.INFRA_TYPES.get(String(_tin_project.get("type", "")), {}) as Dictionary).get("name", _tin_project.get("type", ""))),
			"cost_estimate": int(_tin_project.get("cost_estimate", 0)),
			"spent": int(_tin_project.get("spent", 0)),
			"progress": float(_tin_project.get("progress", 0.0)),
			"days_total": float(_tin_project.get("days_total", 0.0)),
			"delayed_days": float(_tin_project.get("delayed_days", 0.0)),
			"status": String(_tin_project.get("status", "")),
			"subsidy": int(_tin_project.get("subsidy", 0)),
			"accident": bool(_tin_project.get("accident", false)),
		}
	if not _tin_route.is_empty():
		out["route"] = {
			"mode": String(_tin_route.get("mode", "")),
			"mode_name": String((transport_infra.MODES.get(String(_tin_route.get("mode", "")), {}) as Dictionary).get("name", _tin_route.get("mode", ""))),
			"fare": float(_tin_route.get("fare", 0.0)),
			"profit": int(_tin_route.get("profit", 0)),
			"on_time_rate": float(_tin_route.get("on_time_rate", 0.0)),
			"suspended": bool(_tin_route.get("suspended", false)),
		}
	if not _tin_region.is_empty():
		out["region"] = {
			"accessibility": float(_tin_region.get("accessibility", 0.0)),
			"land_price": float(_tin_region.get("land_price", 0.0)),
			"gdp": float(_tin_region.get("gdp", 0.0)),
			"population": float(_tin_region.get("population", 0.0)),
		}
	return out

func _persist_transport_infra() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["transport_infra"] = {
		"project": transport_infra.to_dict(_tin_project),
		"route": transport_infra.to_dict(_tin_route),
		"region": transport_infra.to_dict(_tin_region),
	}


## 遗产净额（最小货币单位）：现金 + 存款 − 债务 + 房产估值 − 剩余房贷。
func player_estate_minor() -> float:
	var acct := account_id()
	var total: float = float(economy.cash(acct)) + float(economy.bank(acct)) - float(economy.debt(acct))
	for p in property.owned_properties(player()):
		total += float(property.market_value(p))
		var m: Dictionary = p.get("mortgage", {})
		if not m.is_empty():
			total -= float(m.get("remaining", 0))
	return maxf(0.0, total)

## 法定继承人（按 player.family）：配偶/子女/父母/兄弟姐妹。
func legal_heirs() -> Dictionary:
	var fam: Dictionary = player().get("family", {})
	var spouse: Array = []
	var sid := String(fam.get("spouse_id", ""))
	if sid != "":
		spouse.append(sid)
	return {
		"spouse": spouse,
		"children": _string_ids(fam.get("children_ids", [])),
		"parents": _string_ids(fam.get("parent_ids", [])),
		"siblings": _string_ids(fam.get("sibling_ids", [])),
	}

func _string_ids(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for x in raw:
			out.append(String(x))
	return out

## 死亡结算：按遗嘱或法定继承分配遗产，并把本次死亡记入家族史（legacy.history）。
func settle_inheritance() -> Dictionary:
	var estate: float = player_estate_minor()
	var r: Dictionary = inheritance.settle(estate, player().get("will", {}), legal_heirs())
	# 未成年子女监护归属（R51.5）：优先遗嘱/指定监护人，其次法定顺位。
	var guard: Dictionary = legal_guardian()
	r["guardianship"] = guard
	var hist: Array = state.legacy.get("history", [])
	hist.append({
		"kind": "death",
		"name": String(player().get("name", "")),
		"death_minutes": now_minutes(),
		"estate": float(r.get("estate", 0.0)),
		"tax": float(r.get("tax", 0.0)),
		"net": float(r.get("net", 0.0)),
		"escheat": bool(r.get("escheat", false)),
		"allocations": r.get("allocations", []),
		"guardian": String((guard.get("guardian", {}) as Dictionary).get("id", "")),
		"minors": guard.get("minors", []),
	})
	state.legacy["history"] = hist
	_inheritance_settled = true
	return r

## 是否已完成死亡结算。
func inheritance_settled() -> bool:
	return _inheritance_settled

## 人生结算（R12.5）：姓名/年龄/最终称号/大事记时间线 + 遗产估算与继承人。
func death_summary() -> Dictionary:
	var timeline: Array = state.legacy.get("history", []) if state != null else []
	var s: Dictionary = survival.life_summary(player(), {
		"death_minutes": now_minutes(),
		"timeline": timeline,
		"final_title": _final_title(),
	})
	s["estate_minor"] = player_estate_minor()
	s["heirs"] = legal_heirs()
	return s

func _final_title() -> String:
	var job: Dictionary = player().get("job", {})
	var title := String(job.get("title", "")) if job is Dictionary else ""
	return title if title != "" else "凡人"

## 持久化生存运行时（成瘾复发/营养过量天数/死亡标志/遗嘱）到 state.sim_runtime。
func _persist_survival() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["survival"] = survival.to_dict()

# --- 心理与精神健康（D4） ---

## 人格派生标签（阈值/组合，供面板与叙述层）。
func personality_tags() -> Array:
	return personality.derive_tags(player().get("attrs", {}).get("personality", {}))

## 当前情绪状态（平静/焦虑/抑郁/亢奋）。
func emotion_state() -> String:
	var psych: Dictionary = player().get("attrs", {}).get("psychological", {})
	return mental.emotion_state(float(psych.get("mood", 50.0)), float(psych.get("stress", 40.0)))

## 精神疾病目录（供解析器链接「心理咨询 <病种>」）。
func mental_disorders_catalog() -> Array:
	return mental.disorders_catalog()

## 治疗方式目录（咨询/药物/CBT/住院/重症干预）。
func mental_treatment_catalog() -> Array:
	return mental.treatments_catalog()

## 刷新心理结算：推进三维病程、按压力与长期低值掷骰新发、回写玩家心理与精神疾病数组。
## 返回本时段新发作列表。
func _refresh_mental(minutes: int) -> Array:
	var events: Array = []
	if is_dead():
		return events
	mental.advance(minutes, rng)
	var psych: Dictionary = player().get("attrs", {}).get("psychological", {})
	var stress: float = float(psych.get("stress", 40.0))
	# 幸福长期低值抬高精神疾病风险（R44.8）。
	var happy_mult: float = happiness.disorder_risk_multiplier(
		float(psych.get("happiness", 50.0)), float(psych.get("meaning", 50.0)), day_index())
	if stress >= float(MentalHealthScript.STRESS_DISORDER_THRESHOLD) or happy_mult > 1.05:
		for hit in mental.roll_triggers(player().get("attrs", {}).get("personality", {}), stress, now_minutes(), rng, "stress", happy_mult):
			events.append({"type": "mental_disorder", "name": String(hit.get("name", ""))})
	_update_happiness()
	_sync_mental()
	return events

## 依关系/事业/健康/信仰/意义感结算幸福与意义，写入心理属性（R44.7）。
func _update_happiness() -> void:
	if is_dead():
		return
	var attrs: Dictionary = player().get("attrs", {})
	var phys: Dictionary = attrs.get("physiological", {})
	var values: Dictionary = attrs.get("values", {})
	var fam: Dictionary = player().get("family", {})
	# 关系：好感均值映射到 0..100（无关系取人群基线 50）。
	var relations: Array = player().get("relations", [])
	var rel_score: float = 50.0
	if not relations.is_empty():
		var acc: float = 0.0
		for r in relations:
			if r is Dictionary:
				acc += clampf((float(r.get("favor", 0.0)) + 100.0) / 2.0, 0.0, 100.0)
		rel_score = acc / float(relations.size())
	# 事业：有工作按绩效，无业取 40。
	var job: Dictionary = player().get("job", {})
	var career_score: float = 40.0
	if not job.is_empty():
		career_score = clampf(float(job.get("performance", 60.0)), 0.0, 100.0)
	# 信仰：物质—精神轴偏向精神即高。
	var faith_score: float = clampf(float(values.get("material_spiritual", 50.0)), 0.0, 100.0)
	# 皈依后信仰分量随境界抬升（R55.4）。
	var faith_realm: int = spirituality.faith_realm_index(_spirit)
	if String(_spirit.get("faith", "")) != "":
		faith_score = clampf(maxf(faith_score, 60.0 + float(faith_realm) * 8.0), 0.0, 100.0)
	# 意义感分量：追求（精神轴 + 信仰境界）、家庭（有配偶/子女）、成就（数量）、价值观一致性。
	var pursuit: float = clampf(faith_score + float(faith_realm) * 4.0, 0.0, 100.0)
	var family_c: float = 30.0
	if String(fam.get("spouse_id", "")) != "":
		family_c += 35.0
	family_c += minf(35.0, float((fam.get("children_ids", []) as Array).size()) * 15.0)
	var ach_count: int = (player().get("achievements", []) as Array).size()
	var achievement: float = clampf(30.0 + float(ach_count) * 5.0, 0.0, 100.0)
	var consistency: float = clampf(100.0 - absf(float(values.get("conservative_open", 50.0)) - 50.0) * 2.0, 0.0, 100.0)
	happiness.update(player(), {
		"relations": rel_score,
		"career": career_score,
		"health": clampf(float(phys.get("health", 50.0)), 0.0, 100.0),
		"faith": faith_score,
		"pursuit": pursuit,
		"family": family_c,
		"achievement": achievement,
		"values_consistency": consistency,
	})

## 回写 player.health.mental（schema 白名单字段）。
func _sync_mental() -> void:
	var health: Dictionary = player().get("health", {})
	health["mental"] = mental.mental_entries(now_minutes())
	player()["health"] = health

## 持久化精神疾病运行时到 state.sim_runtime。
func _persist_mental() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["mental"] = mental.to_dict()

## 情绪事件调整（如放松/打击）：写入心情与压力，返回调整后状态。
func apply_emotion_event(event: String) -> Dictionary:
	return mental.adjust_mood_stress(player(), event)

## 放松/正念：缓解压力、提振心情（无对应治疗，仅日常调节）。
func relax() -> Dictionary:
	var before: Dictionary = player().get("attrs", {}).get("psychological", {})
	var r: Dictionary = apply_emotion_event("praise")
	_sync_mental()
	return {
		"ok": true,
		"mood": float(r.get("mood", 0.0)),
		"stress": float(r.get("stress", 0.0)),
		"before_stress": float(before.get("stress", 0.0)),
	}

## 强制发作指定精神疾病（供重大事件/疫情心理冲击/认知污染等跨域触发），并回写。
func mental_onset(key: String) -> Dictionary:
	var attrs: Dictionary = player().get("attrs", {})
	var psych: Dictionary = attrs.get("psychological", {})
	var r: Dictionary = mental.onset(key, attrs.get("personality", {}), float(psych.get("stress", 40.0)), now_minutes())
	_sync_mental()
	_persist_mental()
	return r

## 精神疾病治疗：method 为治疗键；key 为空时取最严重活跃病种。会推进治疗时长并结算费用。
func mental_treat(method: String, key: String = "") -> Dictionary:
	if not mental.TREATMENTS.has(method):
		return {"ok": false, "reason": "unknown_treatment"}
	if String(key).is_empty():
		key = mental.most_severe_active_key()
	if String(key).is_empty() or not mental.DISORDERS.has(key):
		return {"ok": false, "reason": "no_active_disorder"}
	var r: Dictionary = mental.treat(key, method, rng, true)
	if not bool(r.get("ok", false)):
		return r
	var t: Dictionary = mental.TREATMENTS[method]
	var cost := int(t.get("cost", 0))
	if cost > 0:
		if economy.cash(account_id()) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "mental:%s" % method)
		sync_finances()
	var minutes := int(t.get("minutes", 0))
	if minutes > 0:
		advance(minutes, {"asleep": method == "hospitalization"})
	_sync_mental()
	r["key_name"] = mental.disorder_name(String(key))
	r["method_name"] = String(t.get("name", method))
	return r

## 精神健康面板数据（情绪/人格/幸福 + 病程列表）。
func mental_panel_data() -> Dictionary:
	var psych: Dictionary = player().get("attrs", {}).get("psychological", {})
	var p: Dictionary = player().get("attrs", {}).get("personality", {})
	var dims: Array = []
	var names: Dictionary = personality.DIM_NAMES
	for dim in personality.BIG_FIVE:
		dims.append({"label": String(names.get(dim, dim)), "value": str(snappedf(float(p.get(dim, 50.0)), 0.1))})
	var tags: Array = []
	for t in personality_tags():
		tags.append(_tag_name(String(t)))
	var cases: Array = []
	for c in mental.all_cases():
		if not (c is Dictionary):
			continue
		var key := String(c.get("key", ""))
		var active := bool(c.get("active", false))
		var phase := "发作期" if active else ("缓解期" if str(c.get("phase", "")) == "remission" else "慢性期")
		cases.append({
			"label": mental.disorder_name(key),
			"value": "%s · 强度%.0f · 间隔%.0f天 · 单次%.0f天 · 发作%d次%s" % [
				phase, float(c.get("intensity", 0.0)),
				float(c.get("frequency_days", 0.0)),
				float(c.get("duration_minutes", 0.0)) / 1440.0,
				int(c.get("episodes", 0)),
				" · 治疗中" if bool(c.get("in_treatment", false)) else "",
			],
		})
	return {
		"emotion": mental.EMOTION_NAMES.get(emotion_state(), "平静"),
		"mood": float(psych.get("mood", 50.0)),
		"stress": float(psych.get("stress", 40.0)),
		"happiness": float(psych.get("happiness", 50.0)),
		"meaning": float(psych.get("meaning", 50.0)),
		"dims": dims,
		"tags": tags,
		"cases": cases,
	}

## 性格标签中文名。
func _tag_name(tag: String) -> String:
	const TAG_NAMES: Dictionary = {
		"perfectionist": "完美主义", "social_butterfly": "社交达人", "lone_wolf": "独行",
		"anxious_type": "敏感焦虑", "open_minded": "开放探索", "agreeable": "温和亲和",
		"risk_taker": "冒险", "resilient": "坚韧稳定", "achiever": "自律成就",
		"dramatic": "情绪外显", "traditional": "传统守成", "solitary_cold": "孤僻冷淡",
	}
	return String(TAG_NAMES.get(tag, tag))

# --- 精神追求与信仰（D15） ---

## 精神追求目录（冥想/修行/哲学阅读/写作/自省/志愿服务/艺术创作）。
func pursuits_catalog() -> Array:
	return spirituality.pursuits_catalog()

## 信仰/哲学流派目录（R55.4）。
func faiths_catalog() -> Array:
	return spirituality.faiths_catalog()

## 精神危机出口目录（宗教/哲学/心理/志愿）。
func crisis_exits_catalog() -> Array:
	return spirituality.crisis_exits_catalog()

## 执行一次精神追求（R55.3、R55.5）：按投入时长降低压力、提升意义/幸福，并可能漂移人格与价值观。
func pursue_spirit(kind: String, minutes: int) -> Dictionary:
	if not spirituality.PURSUITS.has(kind):
		return {"ok": false, "reason": "unknown_pursuit"}
	var attrs: Dictionary = player().get("attrs", {})
	var psych: Dictionary = attrs.get("psychological", {})
	var values: Dictionary = attrs.get("values", {})
	var persona: Dictionary = attrs.get("personality", {})
	var hours: float = maxf(0.0, float(minutes)) / 60.0
	var cum: Dictionary = _spirit.get("persona_drift", {})
	var r: Dictionary = spirituality.pursue(_spirit, kind, float(minutes), rng, persona, cum)
	_spirit["persona_drift"] = cum
	psych["stress"] = clampf(float(psych.get("stress", 40.0)) + float(r.get("stress", 0.0)), 0.0, 100.0)
	psych["mood"] = clampf(float(psych.get("mood", 50.0)) - float(r.get("stress", 0.0)), 0.0, 100.0)
	attrs["psychological"] = psych
	var vdrift: Dictionary = r.get("value_drift", {}) if r.get("value_drift") is Dictionary else {}
	for axis in vdrift.keys():
		spirituality.adjust_values(values, String(axis), hours * float(vdrift[axis]))
	attrs["personality"] = persona
	attrs["values"] = values
	player()["attrs"] = attrs
	_update_happiness()
	_sync_mental()
	_persist_spirituality()
	return {
		"ok": true, "kind": kind, "name": spirituality.pursuit_name(kind),
		"realm": spirituality.realm_name(int(r.get("realm_index", 0))),
		"realm_unlocked": bool(r.get("realm_unlocked", false)),
		"stress": float(r.get("stress", 0.0)), "hours": hours,
		"personality_drifted": bool(r.get("personality_drifted", false)),
	}

## 皈依/加入信仰或哲学流派（R55.4）。
func convert_faith(faith: String) -> Dictionary:
	var r: Dictionary = spirituality.convert(_spirit, faith)
	if bool(r.get("ok", false)):
		_update_happiness()
		_persist_spirituality()
	return r

## 深化信仰：按小时累计深度并解锁境界（R55.4）。
func deepen_faith(minutes: int) -> Dictionary:
	var r: Dictionary = spirituality.deepen_faith(_spirit, float(minutes), rng)
	if not bool(r.get("ok", false)):
		return r
	var attrs: Dictionary = player().get("attrs", {})
	var psych: Dictionary = attrs.get("psychological", {})
	psych["stress"] = clampf(float(psych.get("stress", 40.0)) + float(r.get("stress", 0.0)), 0.0, 100.0)
	attrs["psychological"] = psych
	player()["attrs"] = attrs
	_update_happiness()
	_sync_mental()
	_persist_spirituality()
	r["faith_name"] = spirituality.faith_name(String(_spirit.get("faith", "")))
	r["realm"] = spirituality.realm_name(int(r.get("realm_index", 0)))
	return r

## 当前精神危机（无则返回空事件）。依意义/幸福/中年窗口与信仰动摇判定（R55.6）。
func spirit_crisis() -> Dictionary:
	var psych: Dictionary = player().get("attrs", {}).get("psychological", {})
	var birth: int = int(player().get("birth_minutes", 0))
	var age: float = maxf(0.0, float(now_minutes() - birth) / MINUTES_PER_YEAR)
	var happy: float = float(psych.get("happiness", 50.0))
	var meaning: float = float(psych.get("meaning", 50.0))
	var midlife: float = happiness.midlife_crisis_weight(age, happy, meaning)
	var r: Dictionary = spirituality.check_crisis(_spirit, happy, meaning, midlife, rng)
	if String(r.get("event", "")) != "":
		_spirit["crisis"] = String(r["event"])
		_persist_spirituality()
	return r

## 通过出口化解当前精神危机（宗教/哲学/心理/志愿），提升意义、降低压力（R55.6）。
func resolve_spirit_crisis(exit_kind: String) -> Dictionary:
	var crisis := String(_spirit.get("crisis", ""))
	if crisis.is_empty():
		return {"ok": false, "reason": "no_crisis"}
	var r: Dictionary = spirituality.resolve_crisis(_spirit, crisis, exit_kind)
	if not bool(r.get("ok", false)):
		return r
	var attrs: Dictionary = player().get("attrs", {})
	var psych: Dictionary = attrs.get("psychological", {})
	psych["stress"] = clampf(float(psych.get("stress", 40.0)) + float(r.get("stress", 0.0)), 0.0, 100.0)
	psych["mood"] = clampf(float(psych.get("mood", 50.0)) - float(r.get("stress", 0.0)), 0.0, 100.0)
	attrs["psychological"] = psych
	player()["attrs"] = attrs
	_update_happiness()
	_sync_mental()
	_persist_spirituality()
	r["crisis"] = crisis
	return r

## 精神追求面板数据（价值观三轴/信仰境界/追求深度/危机）。
func spirit_panel_data() -> Dictionary:
	var values: Dictionary = player().get("attrs", {}).get("values", {})
	var axes: Array = []
	for axis in spirituality.VALUES:
		axes.append({"label": String(spirituality.VALUE_NAMES.get(axis, axis)), "value": str(snappedf(float(values.get(axis, 50.0)), 0.1))})
	var pursuits: Array = []
	var depths: Dictionary = _spirit.get("depth", {})
	for kind in spirituality.PURSUITS.keys():
		var hours: float = float(depths.get(kind, 0.0))
		if hours <= 0.0:
			continue
		pursuits.append({"label": spirituality.pursuit_name(String(kind)), "value": "%s · 累计%.1f小时" % [
			spirituality.realm_name(spirituality.realm_index(_spirit, String(kind))), hours]})
	var faith_key := String(_spirit.get("faith", ""))
	var crisis := String(_spirit.get("crisis", ""))
	return {
		"axes": axes,
		"faith": spirituality.faith_name(faith_key),
		"has_faith": faith_key != "",
		"faith_realm": spirituality.realm_name(spirituality.faith_realm_index(_spirit)),
		"faith_depth": float(_spirit.get("faith_depth", 0.0)),
		"pursuits": pursuits,
		"crisis": crisis,
		"crisis_exits": spirituality.crisis_exits_catalog() if crisis != "" else [],
	}

## 精神追求运行时状态（供测试与叙述层读取）。
func spirit_state() -> Dictionary:
	return _spirit

## 随游戏内时钟检查精神危机（R55.6），返回事件列表。
func _refresh_spirit() -> Array:
	var events: Array = []
	if is_dead():
		return events
	var ev := String(spirit_crisis().get("event", ""))
	if ev != "":
		events.append({"type": "spirit_crisis", "name": ev})
	return events

## 持久化精神追求运行时到 state.sim_runtime。
func _persist_spirituality() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	(state.sim_runtime as Dictionary)["spirituality"] = spirituality.to_dict(_spirit)

# --- 宠物 ---

## 可领养物种目录（供解析「领养 <宠物>」）。
func pet_species_catalog() -> Array:
	var out: Array = []
	for key in pet.SPECIES.keys():
		out.append({"id": String(key), "name": String((pet.SPECIES[key] as Dictionary).get("name", key))})
	return out

func pets() -> Array:
	return player().get("pets", [])

func find_pet(pet_id: String) -> Dictionary:
	for p in pets():
		if typeof(p) == TYPE_DICTIONARY and String(p.get("id", "")) == pet_id:
			return p
	return {}

## 领养宠物：扣款并写入 player.pets（schema 对齐，含 id/content_key）。
func adopt_pet(species: String, pet_name: String = "") -> Dictionary:
	var r: Dictionary = pet.acquire(species, pet_name if pet_name != "" else species)
	if not bool(r.get("ok", false)):
		return r
	var rec: Dictionary = (r["pet"] as Dictionary).duplicate(true)
	rec["id"] = _make_uuid()
	rec["content_key"] = "pet.%s" % species
	rec["adopted_minutes"] = now_minutes()
	var cost := int(rec.get("cost", 0))
	if cost > 0:
		if economy.cash(account_id()) < cost:
			return {"ok": false, "reason": "insufficient_funds", "cost": cost}
		economy.add_money(account_id(), -cost, "pet:buy")
		sync_finances()
	var arr: Array = player().get("pets", [])
	arr.append(rec)
	player()["pets"] = arr
	return {"ok": true, "pet": rec, "cost": cost}

## 喂养全部宠物，返回被喂养的名字。
func feed_pets(amount: float = 30.0) -> Array:
	var done: Array = []
	for p in pets():
		if p is Dictionary and bool(pet.feed(p, amount).get("ok", false)):
			done.append(String(p.get("name", "")))
	return done

## 训练全部宠物，返回被训练的名字。
func train_pets(hours: float = 1.0) -> Array:
	var done: Array = []
	for p in pets():
		if p is Dictionary and bool(pet.train(p, hours, rng).get("ok", false)):
			done.append(String(p.get("name", "")))
	return done

## 随游戏内时钟推进宠物生命周期；返回宠物死亡事件。
func _advance_pets(minutes: int) -> Array:
	var events: Array = []
	for p in pets():
		if not (p is Dictionary) or not bool(p.get("alive", true)):
			continue
		var ev: Dictionary = pet.advance(p, float(minutes) / float(MINUTES_PER_DAY), rng)
		if String(ev.get("event", "")) == "pet_death":
			events.append({"type": "pet_death", "name": String(p.get("name", ""))})
	return events

## 生成确定性 UUID（与 NpcSystem 同格式）。
func _make_uuid() -> String:
	const DIGITS: String = "0123456789abcdef"
	var hex := ""
	for _i in 32:
		hex += DIGITS[int(rng.next_float() * 16.0) % 16]
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]

## 妊娠到期则分娩；返回新生儿档案（无变化返回空）。
func _check_delivery() -> Dictionary:
	if is_dead():
		return {}
	var preg: Dictionary = player().get("family", {}).get("pregnancy", {})
	if preg.is_empty() or now_minutes() < int(preg.get("due_minutes", 0)):
		return {}
	return deliver_child()

## 分娩：生成子女 NPC（继承父母能力/人格），落档到 world_delta.npcs 与
## player.family.children_ids，并记入家族史（legacy.lineage/history）。
func deliver_child() -> Dictionary:
	var fam: Dictionary = player().get("family", {})
	var preg: Dictionary = fam.get("pregnancy", {})
	var partner_id := String(preg.get("partner_id", fam.get("spouse_id", "")))
	var spouse := find_person(partner_id)
	var gender := "male" if rng.next_float() < 0.5 else "female"
	_child_seq += 1
	# 子女 NPC 使用独立序号段，避免与熟人（1..N）等个体 id 冲突。
	var child: Dictionary = npcs.generate(_child_seq + 100000, {
		"world_seed": _seed, "region_id": _home_region_id,
		"now_minute": now_minutes(), "individualized": true, "lod_tier": 0,
		"age": 0, "gender": gender,
	})
	var inherited: Dictionary = family.give_birth(player(), spouse, String(child.get("name", "")), gender)
	var attrs: Dictionary = child.get("attributes", {})
	attrs["ability"] = inherited.get("ability", {})
	attrs["personality"] = inherited.get("personality", {})
	child["attributes"] = attrs
	var parents: Array = [String(player().get("id", ""))]
	if partner_id != "":
		parents.append(partner_id)
	child["family"] = {"parent_ids": parents}
	_register_child(child, partner_id)
	fam.erase("pregnancy")
	player()["family"] = fam
	return child

func _register_child(child: Dictionary, partner_id: String = "") -> void:
	var cid := String(child.get("id", ""))
	var npcs_arr: Array = state.world_delta.get("npcs", [])
	npcs_arr.append(child)
	state.world_delta["npcs"] = npcs_arr
	var fam: Dictionary = player().get("family", {})
	var kids: Array = fam.get("children_ids", [])
	if not kids.has(cid):
		kids.append(cid)
	fam["children_ids"] = kids
	player()["family"] = fam
	relations.ensure_relation(player(), cid)
	_link_siblings(child)
	_link_partner_child(child, partner_id)
	var lin: Array = state.legacy.get("lineage", [])
	lin.append({
		"name": String(child.get("name", "")),
		"birth_minutes": int(child.get("birth_minutes", 0)),
		"summary": "出生于 %s" % _home_region_id,
	})
	state.legacy["lineage"] = lin
	var hist: Array = state.legacy.get("history", [])
	hist.append({
		"kind": "birth",
		"name": String(child.get("name", "")),
		"birth_minutes": int(child.get("birth_minutes", 0)),
		"parent_ids": (child.get("family", {}) as Dictionary).get("parent_ids", []),
	})
	state.legacy["history"] = hist

## 族谱反查：把新生儿与其兄弟姐妹互链（双向 sibling_ids）。
func _link_siblings(child: Dictionary) -> void:
	var cid := String(child.get("id", ""))
	for other in children():
		var oid := String(other.get("id", ""))
		if oid == "" or oid == cid:
			continue
		var cf: Dictionary = child.get("family", {})
		var cs: Array = cf.get("sibling_ids", [])
		if not cs.has(oid):
			cs.append(oid)
		cf["sibling_ids"] = cs
		child["family"] = cf
		var of: Dictionary = other.get("family", {})
		var os: Array = of.get("sibling_ids", [])
		if not os.has(cid):
			os.append(cid)
		of["sibling_ids"] = os
		other["family"] = of

## 族谱反查：把新生儿挂到配偶名下（NPC.family.children_ids）。
func _link_partner_child(child: Dictionary, partner_id: String) -> void:
	if partner_id == "":
		return
	var partner := find_person(partner_id)
	if partner.is_empty():
		return
	var cid := String(child.get("id", ""))
	var pf: Dictionary = partner.get("family", {})
	var pkids: Array = pf.get("children_ids", [])
	if not pkids.has(cid):
		pkids.append(cid)
	pf["children_ids"] = pkids
	partner["family"] = pf

# --- 收养与监护（R51 / D11）---

## 养子女（player.family.adopted_ids）。
func adopted_children() -> Array:
	var out: Array = []
	for cid in player().get("family", {}).get("adopted_ids", []):
		var c := find_person(String(cid))
		if not c.is_empty():
			out.append(c)
	return out

## 收养一名子女：生成 NPC（独立序号段），登记为法定子女与养子女，记入家族史。
## 收养不写妊娠/出生记录，仅在 lineage/history 记「收养」条目。
func adopt_child(child_name: String = "", age: int = 3) -> Dictionary:
	_adopt_seq += 1
	var gender := "male" if rng.next_float() < 0.5 else "female"
	var child: Dictionary = npcs.generate(_adopt_seq + ADOPT_SEQ_BASE, {
		"world_seed": _seed, "region_id": _home_region_id,
		"now_minute": now_minutes(), "individualized": true, "lod_tier": 0,
		"age": maxi(0, age), "gender": gender,
	})
	if child_name != "":
		child["name"] = child_name
	child["stage"] = parenting.stage_of(maxi(0, age))
	child["adopted"] = true
	child["family"] = {"parent_ids": [String(player().get("id", ""))]}
	var cid := String(child.get("id", ""))
	var npcs_arr: Array = state.world_delta.get("npcs", [])
	npcs_arr.append(child)
	state.world_delta["npcs"] = npcs_arr
	var fam: Dictionary = player().get("family", {})
	var kids: Array = fam.get("children_ids", [])
	if not kids.has(cid):
		kids.append(cid)
	fam["children_ids"] = kids
	var adopted: Array = fam.get("adopted_ids", [])
	if not adopted.has(cid):
		adopted.append(cid)
	fam["adopted_ids"] = adopted
	player()["family"] = fam
	relations.ensure_relation(player(), cid)
	_link_siblings(child)
	var lin: Array = state.legacy.get("lineage", [])
	lin.append({
		"name": String(child.get("name", "")),
		"birth_minutes": int(child.get("birth_minutes", 0)),
		"summary": "收养于 %s" % _home_region_id,
	})
	state.legacy["lineage"] = lin
	var hist: Array = state.legacy.get("history", [])
	hist.append({
		"kind": "adopt",
		"name": String(child.get("name", "")),
		"adopt_minutes": now_minutes(),
		"parent_ids": [String(player().get("id", ""))],
	})
	state.legacy["history"] = hist
	return {"ok": true, "child": child}

## 指定监护人（player.family.guardian_ids，单值）。指定的对象须存在于世界。
func assign_guardian(person_id: String) -> Dictionary:
	if person_id == "" or find_person(person_id).is_empty():
		return {"ok": false, "reason": "person_not_found"}
	var fam: Dictionary = player().get("family", {})
	fam["guardian_ids"] = [person_id]
	player()["family"] = fam
	return {"ok": true, "guardian_ids": fam["guardian_ids"]}

## 已指定的监护人档案。
func guardians() -> Array:
	var out: Array = []
	for gid in player().get("family", {}).get("guardian_ids", []):
		var g := find_person(String(gid))
		if not g.is_empty():
			out.append(g)
	return out

## 未成年子女（年龄 < ADULT_AGE 且在世）。
func minor_children() -> Array:
	var out: Array = []
	var now := now_minutes()
	for c in children():
		if not bool(c.get("alive", true)):
			continue
		if _child_age(c, now) < ADULT_AGE:
			out.append(c)
	return out

func _child_age(child: Dictionary, now: int) -> int:
	var birth := int(child.get("birth_minutes", 0))
	return maxi(0, int(float(now - birth) / MINUTES_PER_YEAR))

## 未成年子女的法定监护人（R51.5）：优先已指定监护人，其次在世配偶/父母/成年子女/兄弟姐妹/熟人。
func legal_guardian() -> Dictionary:
	var minors: Array = []
	for c in minor_children():
		minors.append(String(c.get("id", "")))
	if minors.is_empty():
		return {"guardian": {}, "minors": [], "ok": false}
	var candidates: Array = []
	for g in guardians():
		candidates.append({"id": String(g.get("id", "")), "name": String(g.get("name", "")), "suitability": 95.0})
	var sid := String(player().get("family", {}).get("spouse_id", ""))
	if sid != "":
		candidates.append({"id": sid, "name": String(spouse().get("name", "")), "suitability": 85.0})
	for pid in player().get("family", {}).get("parent_ids", []):
		var p := find_person(String(pid))
		if not p.is_empty():
			candidates.append({"id": String(pid), "name": String(p.get("name", "")), "suitability": 88.0})
	for c in children():
		if bool(c.get("alive", true)) and _child_age(c, now_minutes()) >= ADULT_AGE:
			candidates.append({"id": String(c.get("id", "")), "name": String(c.get("name", "")), "suitability": 75.0})
	for sib in player().get("family", {}).get("sibling_ids", []):
		var s := find_person(String(sib))
		if not s.is_empty():
			candidates.append({"id": String(sib), "name": String(s.get("name", "")), "suitability": 65.0})
	for a in _acquaintances:
		candidates.append({"id": String(a.get("id", "")), "name": String(a.get("name", "")), "suitability": 45.0})
	return inheritance.guardianship(minors, candidates)

# --- 子女成长与早夭（R51.3/R51.4/R51.8）---

## 按游戏内时钟推进子女成长：整数年龄增长时做年度成长结算，成年后独立。
func _grow_children() -> Array:
	var events: Array = []
	var now := now_minutes()
	for c in children():
		if not bool(c.get("alive", true)):
			continue
		var age := _child_age(c, now)
		if age >= ADULT_AGE:
			if not bool(c.get("independent", false)):
				parenting.reach_adulthood(c)
				events.append({"type": "child_adult", "name": String(c.get("name", ""))})
			continue
		var grown := int(c.get("grown_age", -1))
		if age > grown:
			var care := float(c.get("care_quality", 60.0))
			for _y in range(grown + 1, age + 1):
				_grow_one_year(c, care)
			c["grown_age"] = age
			c["stage"] = parenting.stage_of(age)
	return events

## 单年成长：把 NPC 的 attributes.ability 作为基因写入 ParentingSystem 结算，再回写 properties。
func _grow_one_year(child: Dictionary, care: float) -> void:
	var attrs: Dictionary = child.get("attributes", {})
	child["ability"] = attrs.get("ability", {})
	parenting.raise_child(child, care, 60.0, null)
	attrs["ability"] = child.get("ability", {})
	child["attributes"] = attrs
	child.erase("ability")

## 未成年子女早夭（R51.8）：按推进时长折算年化概率，命中则标记死亡并记入家族史。
func _check_child_mortality(minutes: int) -> Array:
	var events: Array = []
	var minors := minor_children()
	if minors.is_empty():
		return events
	var years: float = float(minutes) / MINUTES_PER_YEAR
	var rate: float = clampf(ParentingScript.EARLY_DEATH_RATE * years, 0.0, ParentingScript.EARLY_DEATH_RATE)
	for c in minors:
		if rng.next_float() >= rate:
			continue
		c["alive"] = false
		c["death_minutes"] = now_minutes()
		events.append({"type": "child_death", "name": String(c.get("name", ""))})
		var hist: Array = state.legacy.get("history", [])
		hist.append({
			"kind": "child_death",
			"name": String(c.get("name", "")),
			"death_minutes": now_minutes(),
		})
		state.legacy["history"] = hist
	return events

## 跨月则结算名下房产（贷款本息/物业/租金/折旧/断供法拍）并回写财务镜像。
func _maybe_settle_property(prev_minutes: int, cur_minutes: int) -> Dictionary:
	if property.owned_properties(player()).is_empty():
		return {}
	if cur_minutes / (SETTLE_INTERVAL_DAYS * MINUTES_PER_DAY) <= prev_minutes / (SETTLE_INTERVAL_DAYS * MINUTES_PER_DAY):
		return {}
	var r: Dictionary = property.monthly_settle(player(), economy, account_id())
	sync_finances()
	return r

## 指定所在区域：登记为活动区并绑定气候带（供旅行/搬迁接线）。
func set_home_region(region_id: String, opts: Dictionary = {}) -> bool:
	if geo != null and geo.count() > 0 and not geo.has_node(region_id):
		return false
	_home_region_id = region_id
	if not opts.has("population"):
		opts = _geo_region_opts(region_id)
	regions.register_region(region_id, opts)
	regions.enter(region_id, now_minutes())
	if not weather.has_region(region_id):
		weather.register_region(region_id, _zone_for_region(region_id))
	_write_player_region(region_id)
	_listings.clear()
	_ensure_property_market()
	return true

## 区域视图（供地图/面板展示）：仅暴露非敏感展示字段。
func regions_view() -> Array:
	var out: Array = []
	if regions == null:
		return out
	for id in regions.region_ids():
		var r = regions.get_region(id)
		if r == null:
			continue
		out.append({
			"region_key": String(id),
			"population": r.population,
			"price_index": r.price_index,
			"economy": r.economy,
			"safety": r.safety,
			"climate": r.climate,
		})
	return out

## 当前区域天气快照（供天气面板）：condition/temperature/humidity/wind/phase[/warning]。
func weather_now() -> Dictionary:
	var rid: String = current_region_id()
	if rid == "" or weather == null or not weather.has_region(rid):
		return {}
	var now: int = now_minutes()
	var st = weather.state_at(rid, now)
	var minute: int = WeatherScript.minute_of_day(now)
	var out: Dictionary = {
		"condition": st.condition_name,
		"condition_key": st.condition,
		"precipitation_mm": st.precipitation_mm,
		"temperature": "%d°C" % int(round(st.temperature_c)),
		"humidity": "%d%%" % int(round(st.humidity_pct)),
		"wind": "%.1f m/s" % st.wind_ms,
		"phase": "白昼" if minute >= 360 and minute < 1080 else "夜晚",
		"zone": weather.climate_zone_name(weather.zone_of(rid)),
	}
	var warnings: Array = weather.disaster_warnings(rid, WeatherScript.day_of_minute(now))
	if not warnings.is_empty():
		out["warning"] = String(warnings[0].get("message", ""))
	return out

## 天气面板数据：当前天气 + 未来 7 日预报（structured rows）。
func weather_panel_data() -> Dictionary:
	var out: Dictionary = weather_now()
	if out.is_empty():
		return out
	out["forecast"] = weather_forecast_rows()
	return out

## 未来 N 日预报（供天气面板展示）：[{label, value}]。
func weather_forecast_rows(days: int = 7) -> Array:
	var rid: String = current_region_id()
	if rid == "" or weather == null or not weather.has_region(rid):
		return []
	var fc: Array = weather.forecast(rid, now_minutes(), 0, days)
	var out: Array = []
	for row in fc:
		var day: int = int(row.get("day", 0))
		var lead: int = int(row.get("lead", 0))
		var label: String = "今日" if lead == 0 else ("明日" if lead == 1 else _short_date(day))
		var hi: int = int(round(float(row.get("temperature_high_c", 0.0))))
		var lo: int = int(round(float(row.get("temperature_low_c", 0.0))))
		var prec: float = float(row.get("precipitation_mm", 0.0))
		out.append({
			"label": label,
			"value": "%s %d~%d°C 降水%.1fmm" % [String(row.get("condition_name", "")), lo, hi, prec],
		})
	return out

func _short_date(day_index: int) -> String:
	var cal: Dictionary = GregorianScript.from_absolute_minutes(day_index * MINUTES_PER_DAY)
	return "%d/%d" % [int(cal.get("month", 1)), int(cal.get("day", 1))]

# --- D8 个人金融：证券投资与银行存贷 ---

## 证券行情目录（含玩家持仓数量）。
func securities_catalog() -> Array:
	var out: Array = []
	for key in bank.security_keys():
		var q: Dictionary = bank.security_quote(String(key))
		q["qty"] = bank.holding_qty(String(key))
		out.append(q)
	return out

## 买入证券：key 支持代码或中文名；qty 为份数。返回成交明细。
func buy_security(key: String, qty: int) -> Dictionary:
	var sid: String = _resolve_security(key)
	if sid == "":
		return {"ok": false, "reason": "unknown_security"}
	var r: Dictionary = bank.buy_security(economy, account_id(), sid, qty)
	if bool(r.get("ok", false)):
		sync_finances()
		_persist_finance()
	return r

## 卖出证券：返回成交明细。
func sell_security(key: String, qty: int) -> Dictionary:
	var sid: String = _resolve_security(key)
	if sid == "":
		return {"ok": false, "reason": "unknown_security"}
	var r: Dictionary = bank.sell_security(economy, account_id(), sid, qty)
	if bool(r.get("ok", false)):
		sync_finances()
		_persist_finance()
	return r

func _resolve_security(key: String) -> String:
	var raw: String = key.strip_edges()
	if raw == "":
		return ""
	if bank.security_quote(raw).size() > 0:
		return raw
	for item in bank.security_keys():
		var q: Dictionary = bank.security_quote(String(item))
		if String(q.get("name", "")) == raw:
			return String(item)
	return ""

## 银行贷款：按金额与期限发放，计入负债并回写资产镜像。
func bank_loan(amount_minor: int, term_days: int = 365) -> Dictionary:
	if amount_minor <= 0:
		return {"ok": false, "reason": "bad_amount"}
	var principal: int = bank.take_loan(economy, account_id(), amount_minor, term_days)
	if principal <= 0:
		return {"ok": false, "reason": "rejected"}
	sync_finances()
	_persist_finance()
	return {"ok": true, "principal": principal, "term_days": term_days, "rating": bank.credit_rating(account_id())}

## 开立定期存款：期限按天计，利率取当前定期挂牌利率。
func open_fixed_deposit(amount_minor: int, term_days: int) -> Dictionary:
	if amount_minor <= 0 or term_days <= 0:
		return {"ok": false, "reason": "bad_amount"}
	var day: int = now_minutes() / MINUTES_PER_DAY
	if not bank.open_fixed_deposit(economy, account_id(), amount_minor, day, term_days):
		return {"ok": false, "reason": "insufficient_cash"}
	sync_finances()
	_persist_finance()
	return {"ok": true, "principal": amount_minor, "term_days": term_days, "rate": bank.fixed_rate()}

## 按税目申报缴纳：base_major 为对应计税基数（主币单位），返回应纳与实缴。
func pay_tax(tax_type: String, base_major: float) -> Dictionary:
	if not BaselineScript.TAX_TYPES.has(tax_type):
		return {"ok": false, "reason": "unknown_tax"}
	var due_major: float = tax.liability(tax_type, base_major)
	var due_minor: int = int(round(due_major * float(BaselineScript.MONEY_MINOR_SCALE)))
	var collected: int = tax.collect(economy, account_id(), "government", due_minor, tax_type)
	if collected > 0:
		sync_finances()
		_persist_finance()
	return {
		"ok": collected > 0, "tax_type": tax_type, "due_minor": due_minor,
		"collected_minor": collected, "reason": "insufficient_cash" if collected <= 0 else "",
	}

## 买一张彩票并即时开奖：返回是否中奖与奖金（最小货币单位）。
func play_lottery() -> Dictionary:
	if not bank.buy_lottery(economy, account_id()):
		return {"ok": false, "reason": "insufficient_cash"}
	var payout: int = bank.draw_lottery(economy, account_id())
	sync_finances()
	_persist_finance()
	return {"ok": true, "payout": payout, "won": payout > 0}

## 偿还银行贷款：金额上限为现金与负债的较小值。
func repay_bank_loan(amount_minor: int) -> Dictionary:
	if amount_minor <= 0:
		return {"ok": false, "reason": "bad_amount"}
	var paid: int = bank.repay_loan(economy, account_id(), amount_minor)
	if paid <= 0:
		return {"ok": false, "reason": "nothing_to_repay"}
	sync_finances()
	_persist_finance()
	return {"ok": true, "paid": paid, "remaining": economy.debt(account_id())}

## 金融面板数据：信用/利率/定期/贷款/持仓与组合盈亏。
func finance_panel_data() -> Dictionary:
	var id: String = account_id()
	var deposits: Array = []
	for entry in bank.fixed_deposits(id):
		var d: Dictionary = entry
		deposits.append({
			"principal": int(d.get("principal", 0)), "rate": float(d.get("rate", 0.0)),
			"start_day": int(d.get("start_day", 0)), "term_days": int(d.get("term_days", 0)),
			"matured": bool(d.get("matured", false)),
		})
	return {
		"credit": bank.credit_rating(id),
		"demand_rate": bank.demand_rate(), "fixed_rate": bank.fixed_rate(), "loan_rate": bank.loan_rate(),
		"debt_minor": economy.debt(id), "cash_minor": economy.cash(id), "bank_minor": economy.bank(id),
		"fixed_deposits": deposits,
		"portfolio": bank.portfolio(),
		"securities": securities_catalog(),
	}

## 手动触发金融运行态落盘（存取款等不改变证券持仓的操作）。
func persist_finance() -> void:
	_persist_finance()

func _persist_finance() -> void:
	if state == null or not (state.sim_runtime is Dictionary):
		return
	var data: Dictionary = bank.to_dict()
	data["last_settle_day"] = _last_finance_day
	(state.sim_runtime as Dictionary)["finance"] = data

## 按日结算贷款利息与定期存款到期；跨多日时一次补算。
func _settle_finance_daily() -> void:
	var day: int = now_minutes() / MINUTES_PER_DAY
	if _last_finance_day < 0:
		_last_finance_day = day
		return
	var days: int = day - _last_finance_day
	if days <= 0:
		return
	var id: String = account_id()
	if economy.debt(id) > 0:
		bank.accrue_loan_interest(economy, id, days)
	var matured: int = bank.mature_fixed_deposits(economy, id, day)
	_last_finance_day = day
	if matured > 0:
		sync_finances()
	_persist_finance()

## 把经济运行账户余额回写到 player.finances（最小货币单位 → 主单位）。
func sync_finances() -> void:
	var id := account_id()
	if not economy.has_account(id):
		return
	var scale := float(BaselineScript.MONEY_MINOR_SCALE)
	var f: Dictionary = player().get("finances", {})
	f["cash"] = float(economy.cash(id)) / scale
	f["bank"] = float(economy.bank(id)) / scale
	f["debt"] = float(economy.debt(id)) / scale
	player()["finances"] = f

## 推进 minutes 分钟的游戏内模拟（生理/营养/成瘾/寿命判定），并同步游戏内时钟。
## opts 可含 asleep / labor_intensity / age_years / fatal 等，透传给 Survival。
## 返回 {minutes, dead, dying, events}。
func advance(minutes: int, opts: Dictionary = {}) -> Dictionary:
	var events: Array = []
	if minutes <= 0:
		return {"minutes": 0, "dead": survival.is_dead(), "dying": survival.is_dying(), "events": events}
	var r: Dictionary = survival.advance(player(), minutes, opts)
	var before_minutes: int = now_minutes()
	# 游戏内时钟（存档字段）随模拟推进；UI 日历由 main 镜像到 WorldClock。
	var clock: Dictionary = state.clock
	clock["absolute_minutes"] = int(clock.get("absolute_minutes", 0)) + minutes
	# 活动区域随分钟推进（人口/经济日级结算）并写回存档增量；天气按当前时刻查询式演化，无需 tick。
	regions.tick_minute(int(clock["absolute_minutes"]))
	# 证券市场报价随游戏内时间连续演化（GBM，同种子可复现）。
	bank.advance_securities(float(minutes) / MINUTES_PER_YEAR)
	_settle_finance_daily()
	_persist_finance()
	# 领域实体（案件/工程/灾害/催收/异常/手术）离线补算，随游戏内时钟推进并回写领域状态。
	domain_wake.advance_to(int(clock["absolute_minutes"]))
	_apply_wake_results()
	_persist_domain_wake()
	_persist_regions()
	_persist_survival()
	if bool(r.get("dead", false)) and not _inheritance_settled:
		settle_inheritance()
	if bool(r.get("dead", false)):
		_auto_execute_funeral()
		events.append({"type": "death"})
	elif bool(r.get("dying", false)):
		events.append({"type": "dying"})
	else:
		# 生存：妊娠到期分娩。
		var born: Dictionary = _check_delivery()
		if not born.is_empty():
			events.append({"type": "birth", "name": String(born.get("name", ""))})
		# 监狱刑期按日推进（刑满/假释/越狱后同步法律状态）。
		_prison_tick(before_minutes, now_minutes())
		# 持有房产按月结算（贷款/物业/租金/折旧/断供法拍）。
		_maybe_settle_property(before_minutes, now_minutes())
		# 工厂工资按月结算（资金不足拖欠并罢工）。
		_mfg_tick(before_minutes, now_minutes())
		# 形象：年龄/健康折减、医美效果到期回收并同步魅力。
		_appearance_tick(minutes)
		# 军旅薪酬按月发放。
		_military_tick(before_minutes, now_minutes())
		# 公司与职场按月推进（营业/工资/派系博弈）。
		_company_tick(before_minutes, now_minutes())
		_workplace_tick(before_minutes, now_minutes())
		# 子女成长（年度属性结算/成年独立）与早夭。
		events.append_array(_grow_children())
		events.append_array(_check_child_mortality(minutes))
		# 宠物随日推进（饥饿/健康/走失/寿终）。
		events.append_array(_advance_pets(minutes))
		# 精神健康：三维病程推进、压力触发、幸福与意义结算。
		events.append_array(_refresh_mental(minutes))
		# 精神追求：检查精神危机触发（R55.6）。
		events.append_array(_refresh_spirit())
		# 语言：长期未用按闲置天数衰减（R64）。
		_decay_languages(before_minutes, now_minutes())
		# 农业：作物按日生长、仓储按日损耗（R66）。
		_advance_farm(before_minutes, now_minutes())
	# 矿业/能源：能源价格按年周期演化（离线亦结算）。
	_mining_tick(before_minutes, now_minutes())
	# 时尚品牌：相关度随年岁自然衰减。
	_fashion_tick(before_minutes, now_minutes())
	# 农林牧渔：渔场资源恢复、林木按日生长。
	_primary_tick(before_minutes, now_minutes())
	_persist_mental()
	_persist_spirituality()
	_persist_language()
	_persist_farm()
	return {
		"minutes": minutes,
		"dead": bool(r.get("dead", false)),
		"dying": bool(r.get("dying", false)),
		"events": events,
	}

func is_dead() -> bool:
	return survival.is_dead()

func is_dying() -> bool:
	return survival.is_dying()
