# 浮生录 — 逐域缺口审计（D1–D50）

> 本文件记录对 `design.md` 逐域细节规格（D1–D50）的可实施性审计结论与修复路线。审计方式：以只读子代理分三批复核 design、requirements、content-catalog、shared/schemas 与 consistency vectors。
> 修复策略（已定）：**横切优先**；存档 schema **一次大扩展 + schema_version 迁移**；UI **扩到全量面板**；语言定为**独立类型（0..100）**。

## 0. 总体结论

规格的**领域语义**已较完整，缺口集中在**可实施细节**：数值公式、数据结构、内容定义、UI 入口、动词、跨域契约、测试。逐域正文多为定性描述，缺少可直接编码的常量与结构。

## 1. 系统性问题（跨全部域）

1. **数值基线覆盖仍不全（已收敛，低）**：单一真源已迁至 `shared/consistency/baseline/*.json`（按域拆分，现 **76 域**），由 `tools/genbaseline` 生成两端常量并由 CI/`scripts/test.sh` 校验（task 46 覆盖核心/生存/区域/地理交通/气候天气/时代/经济；task 48.3 补 SEIR/碳排环保/工程/医疗/体育/医美；task 48.4 补心理/残障养老/数字/消费者保护/民间借贷/应急；task 48.5 补婚育/育儿/职场/房产/农业/宠物；task 48.6 批量迁移剩余全部系数型标量域，并令 `worldsim.macro`、`sim.gregorian` 改为引用生成基线单一真源；对齐测试数据驱动化，遍历 `BASELINE_DOMAINS`/`BaselineDomains` 逐值比对，新增域无需改测试代码）。仅剩纯实现类常量（哈希盐/枚举序号/LOD/存档 schema 版本）不纳入基线，因为它们不构成跨端数值契约。
2. **存档/领域 schema 未扩展（高）**：`player` 缺 family/memory/pet/军籍/残障/土地/数字资产/案件/病症三维；`finances/legal/health` 过粗；`world_delta` 多为 `additionalProperties` 空壳；缺 case/disaster/anomaly/factory/IP/sports/org/land/digital/order/itinerary/medical/project/event/awards 等 schema。
3. **内容目录与 R56 硬指标脱节（已收敛，低）**：新增 `tools/contentgen/generate.py` 按 R56 下限确定性补齐全部内容类别（地点 1000、场所类型 124、职业 200、技能 140、物品 1000、疾病 80 含精神 20/成瘾 5、证书 30、娱乐 100、事件 300、成就 300、图鉴 500、交通 12、金融标的 56、制造贸易 50、奖项 40、组织 30、异常实体 2000、大型活动 20、第一产业 35、语言 10、节日 10）；`tools/contentbuilder coverage` 对 R56 硬阻断并并入 `scripts/test.sh`；content-catalog §23 记录规模对齐表与 era 门闩。D35–D43、D45–D50 专属节见 content-catalog §22。
4. **UI 入口（已收敛，低）**：`ui.md` 面板清单已由 12 扩至 43，覆盖经营、组织、案件、救援、环保、市政、债务、维权、福利、殡葬、玄学、医疗、精神健康、精神追求、语言与文化、残障与养老、农业与乡土、文娱、工程、专业/生活服务、交通基建、家庭宠物、体育、活动、奖项、数字、疫情、战争、宏观行情、天气预报、人生结算（条件可见）等域；`panel_registry.gd` 同步注册（条件可见新增 `COND_DEAD`），主壳 `VERB_PANELS` 动词映射补全；43 个面板均已接入内容装配（`panel_content.gd`），无数据时以「引导性空态」呈现，不阻塞入口（各域模拟填充数据后自动显示）。
5. **动词表（已收敛，低）**：`verb-registry.md` 新增「政务、服务与组织」节（缴费/办证/落户/土地流转/IP 授权/进出口/办案/救灾/审计/招投标/搬家/算命/移植/接种/参战/转会/参展/申报奖项/实名认证等）与全量面板查询动词，所有域均有入口动词。
6. **跨域接口只标注无契约（中）**：天气/中断/罢工 modifier 字典、数据泄露→案件、能源价格→宏观、荣誉→传承、跨境海关等。
7. **休眠唤醒补算契约已定义并接入运行时（收敛，中）**：`client/sim/domain_wake.gd`（`DomainWake`）已定义案件、灾害、在建工程、逾期催收、异常暴露、手术/试验的确定性离线演化（时间守恒 + 幂等，测试见 `cross_domain_test.gd`）；`RegionManager` 注入 `domain_wake` 并在 `SimHost` 运行时随游戏内时钟推进活动区域、写回 `world_delta.regions`（读档恢复），`SimHost.advance()` 亦调用 `domain_wake.advance_to(clock)` 推动已注册领域实体（`SimHost.domain_register()`）。**尚余**：各玩法系统在产生案件/工程/催收等实体时向 `DomainWake` 注册条目；领域实体状态暂未落档。
8. **后端权威边界未逐域标注（中）**：碳市场、区域医疗、城市规划、交通基建、灾害等同时改区域与宏观，未声明权威归属与合并锚点。
9. **测试点系统性缺失（中）**：D37/D38/D40/D41/D42/D43/D46 无专属测试；多为域无边界的测试。
10. **硬冲突（高）**：
    - D20 语言等级 0..100 与技能 0..20 矛盾（已决议：语言独立类型）。
    - `npc.schema.json` 的 `relations` 引用单个 relation，而 `player.relations` 是数组。
    - design Data Models 的 `Player.family`、`NPC.memory` 在 schema 中不存在。

## 2. 逐域缺口（要点）

### D1 天气生态与时代
- 10 个气候带参数（T_base/A_season/A_diurnal/相位/湿度气压风速映射）缺失；天气 modifier 只有接口无幅度；灾害年期望频率无量化；9 个时代 `start_year` 与推进曲线缺失；`climate_trend` 键未落地；存档无天气/时代全局态；R41.3 预报无 UI 入口。

### D2 混合地图、场所与枢纽
- 12 种交通方式与枢纽边的速度/票价/班次/首末班缺失；出行公式（拥堵/等待/换乘）系数缺失；场所 Resource 字段契约与数值源缺失；枢纽网络与时刻表内容缺失；`region_delta` 字段不足；跨境海关接口未定义。

### D3 营养、成瘾、临终与遗嘱
- **已接线**：`立遗嘱` 动词写入 `player.will`（`written_minutes`/`beneficiaries`），死亡触发 `settle_inheritance()` 并输出 `death_summary()` 人生结算，死亡时主壳打开「人生结算」面板（`ending`）；生存运行时（死亡标志/成瘾复发/营养过量天数/遗嘱）已由 `GameState.sim_runtime.survival` 持久化（`SurvivalSystem.to_dict()`/`from_dict()`，`SimHost._persist_survival()`）；营养失衡分级（轻度 <30 / 重度 <15）与长期过量风险（连续超阈 30 日）按 `NUTRITION_*` 阈值判定；**长期过量致病已接线**：`SurvivalSystem.apply_excess_diseases()` 按超出天数换算严重度（`NUTRITION_EXCESS_SEVERITY_PER_DAY/MAX`）写入 `player.health.diseases`（蛋白→痛风、碳水→糖尿病、脂肪→高脂血症、维生素→维生素过多症、矿物质→矿物质过量症，去重且严重度只上调），并把参考过量天数同步到 `player.health.nutrition_excess_days`；成瘾五类参数（`ADDICTION_SPECIES` 的 dose_gain/tolerance_growth/withdrawal_intensity/relapse_rate/treatment_days/withdrawal_days/physiological）与戒断/治疗系数均来自单一真源。

### D4 人格、精神疾病与幸福
- **已接线**：`PersonalitySystem`（`personality.gd`）提供大五人格出生值（父母均值 × `PERSONALITY_HEREDITY_WEIGHT` + 基线 + 噪声）与**一生累计漂移上限**（`PERSONALITY_LIFETIME_DRIFT_CAP`，成年后乘 `PERSONALITY_ADULT_DRIFT_FACTOR`，`drift()`）；阈值/组合派生标签（`derive_tags()`，12 种）、对话风格、职业适配、社交匹配与决策权重；`SimHost.personality_tags()` 暴露标签。`MentalHealthSystem`（`mental_health.gd`）含**22 病种完整表**（症状/易感因子/触发/基础发生率/复发率/慢性化率）与**三维病程**（`frequency_days` 发作间隔 / `intensity` 强度 0..100 / `duration_minutes` 单次时长），链路为易感→触发→发作→缓解/慢性化→复发（`advance()`/`maybe_relapse()`）；`trigger_probability()` 含触发匹配加成与幸福长期低值乘子（`mult`），`roll_triggers()` 逐病种掷骰，`onset()` 供重大事件强制触发；治疗五法（心理咨询/药物/CBT/住院/重症干预，`MH_TREATMENTS`）结果三态（根治/缓解/无效）含误诊、副作用与依从性（`treat()`）；运行时经 `GameState.sim_runtime.mental` 持久化（`to_dict()`/`from_dict()`），病程回写 `player.health.mental`（`mental_entries()`）。`HappinessSystem`（`happiness.gd`）按关系/事业/健康/信仰/意义感加权结算（`_update_happiness()`），长期低值（`HAPPY_LOW_THRESHOLD`/`HAPPY_LOW_DAYS_FOR_RISK`）抬高精神疾病风险（`disorder_risk_multiplier()`），极端低值触发危机（`crisis_event()`），中年窗口提高中年危机权重（`midlife_crisis_weight()`）。UI：新增「精神健康」面板（`mental`，第 39 面板）渲染情绪/幸福/大五人格/标签/病程；指令 `心理咨询`/`心理治疗`/`精神科用药`/`重症干预`/`放松` 与「看心理」面板入口。

### D5 技能树、科研、艺术与体育
- 经验公式 `base` 与各 modifier 归一缺失；平台期/遗忘速率缺失；科研成果质量权重与科研资源数值缺失；艺术/体育评分与伤病参数缺失；技能内容不足（约 46/140）；科研/艺术/体育无 UI 与 schema。

### D6 形象与医美
- 医美项目表完全缺失（content-catalog 无节）；魅力公式体型/声音修正未定义；形象字段不完整；非法诊所失败率/并发症/衰减/人像比对失败率无数值；无面板。

### D7 军旅、职场关系与融资
- 军衔晋升年限/考核/军功无数值；兵种技能需求缺失；军籍/公司/融资轮次无结构；职场博弈概率缺失；融资估值/对赌无公式与状态机；无 UI。

### D8 金融、税制与宏观
- `worldsim` 指标不完整（缺基准利率/汇率/股指/房价/PMI）；个人金融缺贷款摊还/信用卡/保险/衍生品/信用分/税务；税率表缺失；宏观-微观插值对齐未定义；金融标的不足（仅类别/40）；宏观行情无 UI。

### D9 物品、房产与网络消费
- 物品内容字段与 1000 目标脱节；房产**已接线**看房/买房/卖房/出租（`SimHost.property_*()`，房源按（种子, 区域）确定性生成、名下房产随 `player.assets` 持久化），持有按月结算（`advance()` 跨月触发 `property.monthly_settle()` 还贷/物业/租金/折旧/断供法拍），**尚余**贷款余额/利率/租约/租客/产权年限/装修入面板；订单→物流无 schema；消费心理无数值；无订单/物流入口。

### D10 网络社交、NPC 记忆与区域全人口
- `npc.memory` 缺失；`npc.relations` 类型错误；非个体化人口快照结构不足；社交平台扩散系数与 post/message 结构缺失；动态/私信/直播无 UI。

### D11 育儿、继承与宠物
- `player.family` **已接线**：`spouse_id`（婚恋）、`children_ids`（生育，子女 NPC 落 `world_delta.npcs`）、`pregnancy`（`怀孕` 写入，到期由 `advance()` 分娩）、`parent_ids`（子女反查父母）、`sibling_ids`（分娩时子女间互链）、`guardian_ids`（`指定监护人 <人物>` 写入单值监护人）、`adopted_ids`（`收养` 动词生成收养子女 NPC，落独立 id 序号段 `ADOPT_SEQ_BASE` 并计入法定子女，记 `legacy.history` 收养条目）、`player.will`（`立遗嘱`）；死亡触发 `settle_inheritance()` 按遗嘱或法定顺序分配并记 `legacy.history`，并解析未成年子女监护归属（`legal_guardian()`：指定监护人 95 > 父母 88 > 配偶 85 > 成年子女 75 > 兄弟姐妹 65 > 熟人 45）写入结算；`death_summary()` 输出人生结算。子女成长**已接线**：`advance()` 调用 `_grow_children()` 做年度成长结算（`ParentingSystem.raise_child()`，属性 = 基因×0.5 + 照护×0.2 + 教育×0.2 + 随机×0.1）并更新阶段/成年独立，`_check_child_mortality()` 按 `PARENT_EARLY_DEATH_RATE` 年化折算做早夭判定。宠物**已接线** `领养`/`喂养`/`训练宠物`（`player.pets` 运行时字段 + 「家庭与宠物」面板 + 随日推进）、「家族史与传承」与「家庭与宠物」面板展示养子女/监护人。

### D12 民事、监狱与诉讼
- 案件/证据/判决无 schema；证据-量刑与律师修正无模型；各国法律差异内容缺失；无案件/监狱面板。

### D13 从政、宗教与移民
- 政治职级/政策/宗教归属/签证国籍无字段；宗教/教义/签证政策/法域内容缺失；政策博弈与晋升权重缺失；语言/积分移民条件未定义；无 UI。

### D14 娱乐与旅行
- 娱乐内容不足（约 31/100）且无费用/耗时/效果/衰减/上瘾参数；旅行预订与行程无 schema；兴趣圈层/副业接口未定义；无娱乐活动面板。

### D15 世界观与精神追求
- **已接线**：`SpiritualitySystem`（`spirituality.gd`）提供价值观三轴（利己-利他/保守-开放/物质-精神，`VALUES`）随重大选择微调（`adjust_values()`）与选择一致性评分（`value_consistency()`）；七类精神追求（冥想/修行/哲学阅读/写作/自省/志愿服务/艺术创作，`PURSUITS`）按投入小时降低压力、提升意义/幸福并驱动人格（`drift()`）与价值观漂移（`pursue()`）；信仰/哲学十派（佛教/道家/基督教/伊斯兰教/斯多葛/存在主义/人道主义/儒家/虚无主义/功利主义，`FAITHS`）与修持境界（`REALM_THRESHOLDS`/`REALM_NAMES`，`convert()`/`deepen_faith()`）；四类精神危机（中年/意义丧失/信仰动摇/存在焦虑，`CRISES`+`CRISIS_EXITS`）由意义/幸福/中年窗口与信仰动摇判定（`check_crisis()`）并以宗教/哲学/心理/志愿出口化解（`resolve_crisis()`）；邪教/极端组织卷入风险（`cult_risk()`/`maybe_join_cult()`）。运行时经 `GameState.sim_runtime.spirituality` 持久化（`to_dict()`/`from_dict()`，含人格累计漂移）；皈依后信仰境界抬升幸福/意义分量（`_update_happiness()`）。UI：新增「精神追求」面板（`spirit`，第 40 面板）渲染价值观三轴/信仰修持境界/追求深度/精神危机；指令 `修持 <法门>`/`皈依 <信仰>`/`深化信仰`/`化解危机 <出口>` 与「看精神」面板入口。

### D16 战争与征兵
- 国际关系状态机无数值；war/conscription/casualty 无结构；前线伤亡/军功/被俘无概率且 D96 战斗接口未定；战争经济与占领无数值；无内容/UI。

### D17 流行病与公共卫生
- SEIR 参数/时间步长/向量缺失；virus/outbreak/policy/医疗资源无 schema；挤兑阈值与政策代价缺失；跨域联动剂量缺失；病毒/疫苗内容缺失；无疫情面板。

### D18 基础设施
- 七类设施覆盖/容量/可靠性/价格/状态无字段；账单结算与信用影响无模型（无 credit 字段）；中断频率与抢修工期无量化；无「缴费」动词与账单面板；`InfrastructureOutage` 修饰符未定义。

### D19 组织与社团
- **已接线**：`OrganizationSystem`（`organizations.gd`）含八类组织（工会/行业协会/NGO/兴趣俱乐部/宗教团体/政党/秘密结社/犯罪团伙，`ORG_TYPES`，各带目标/合法性/月会费/最低成员/基础影响力/是否秘密）、四级内部晋升阶梯（`MEMBER_RANKS`，按完成任务数）、五类集体行动（罢工/请愿/募捐/游行/抵制，`ACTIONS`，成功率 = 基础 + 成员规模 + 外部支持 + 对方压力(负) + 舆论，封顶 0.95 / 保底 0.05）、派系斗争（`faction_struggle()`：夺权/分裂/清洗/妥协）、秘密组织暴露机制（`heat`/`counter_intel`/`expose_threshold`/`attempt_expose`/`handle_exposure` 清算留案底与声望损失）与内鬼排查（`plant_mole()`/`detect_mole()`）、破产解散。成员资格存 `player.org_memberships`（`player.schema.json` 新增 `org_membership` 定义），组织运行态经 `GameState.sim_runtime.organizations` 持久化（`_persist_organizations()`；组织由（种子, 区域, 类型序号）确定性生成）。`SimHost` 接线 `join_organization`/`leave_organization`/`pay_org_dues`/`do_org_task`（含晋升津贴）/`org_collective_action`/`organizations_panel_data()`。UI：「组织」面板渲染「我的组织 / 可加入组织」；指令 `加入组织 <组织>`/`退出组织`/`缴会费`/`组织任务`/`罢工`/`请愿`/`募捐`/`游行`/`抵制` 与「看组织」入口。

### D20 语言与文化
- **已接线**：`LanguageSystem`（`language.gd`）语言定为独立类型（0..100），五种语言（汉语/英语/西班牙语/日语/法语，`LANGUAGES`，含官方区域与方言）分口语/听力/读写三项（`COMPONENTS`，权重 0.4/0.3/0.3，`overall()`）；三种学习方法（课程/环境沉浸/自学，`STUDY_METHODS`，各带效率倍率与分项偏好，水平越高增益越小 `study()`/`immerse()`）；长期不用遗忘（`decay()`，30 天宽限后按天衰减）；语言考试与证书（`take_exam()`/`certificates()`/`has_certificate()`）；专业术语门槛（`PROFESSIONAL_TERMS`）与移民/外交/翻译职业解锁（`CAREER_UNLOCKS`/`unlocked_careers()`）；六大节日（春节/元宵/开斋节/中秋/国庆/圣诞，`FESTIVALS`）经 `festival_effects(month, day)` 给出商铺/交通/社交/消费/心情修正；五种文化（中华/美国/日本/法国/阿拉伯，`CULTURES`，含礼仪/禁忌/社交距离/时间观念）文化距离（`social_modifier()`）与文化适应/冲击曲线（`new_cultural_state()`/`adapt()`/`current_adaptation()`）。运行时经 `GameState.sim_runtime.language`/`.culture` 持久化（`to_dict()`/`from_dict()`）。`SimHost` 接线 `languages_catalog()`/`study_language()`/`immerse_language()`/`take_language_exam()`/`adapt_culture()`/`today_festival_effects()`/`language_panel_data()`，`advance()` 按日衰减语言。UI：新增「语言与文化」面板（`language`，第 41 面板）渲染语言能力/语言证书/文化适应/节日民俗；指令 `学语言 <语言> [时长]`/`沉浸 <语言> [天数]`/`语言考试 <语言>`/`适应文化 <文化>` 与「看语言」入口。

### D21 残障与养老
- **已接线**：`DisabilityElderlySystem`（`disability_elderly.gd`）残障四来源（先天/伤病/事故/战争，`SOURCES`）四类型（肢体/视听/智力/精神，`TYPES`）与轻中重三级（`SEVERITIES`/`SEVERITY_PENALTY`），以移动能力（`mobility()` = 1 − 惩罚和 + 辅具加成）统一修正受限动词（`TYPE_VERBS`/`restricted_verbs()`/`available_verbs()`）与就业/社交歧视（`discrimination_penalty()`）；六类辅具（轮椅/助听器/义肢/导盲犬/无障碍改造/康复训练，`DEVICES`，带移动加成与花费）与手术康复部分恢复（`fit_device()`/`surgery_recovery()`/`set_accessible()`）；养老三模式（居家/社区/机构，`CARE_MODES`，带月成本/质量/心情/寿命修正）、退休金（`retirement_pension()`）与社保记录（`enroll_social_security()`）、临终关怀（`hospice_care()`）；护理成本与护工事件/追责（`caregiver_cost()`/`caregiver_event()`/`hold_accountable()`）；认知障碍影响决策能力/遗嘱效力并引入监护（`has_cognitive_impairment()`/`decision_capacity()`/`is_will_valid()`/`establish_guardianship()`）。运行时经 `GameState.sim_runtime.disability` 持久化（`to_dict()`/`from_dict()`）。`SimHost` 接线 `acquire_disability()`/`fit_disability_device()`/`disability_surgery()`/`set_accessible_place()`/`choose_care_mode()`/`settle_care()`/`hospice_care()`/`establish_guardianship()`/`disability_panel_data()`，辅具/康复/无障碍/养老结算扣费。UI：新增「残障与养老」面板（`disability`，第 42 面板）渲染残障状态/辅具与康复/养老与社保/监护与决策；指令 `装辅具 <辅具>`/`康复训练`/`无障碍改造`/`选养老 <模式>`/`临终关怀`/`指定监护 <监护人>` 与「看养老」入口；测试 `disability_elderly_test.gd` 覆盖模块纯逻辑。

### D22 农业与乡土
- **已接线**：`AgricultureSystem`（`agriculture.gd`）六种作物（水稻/小麦/棉花/油菜/蔬菜/药材，`CROPS`，分粮/经济/蔬/药四类用途，各有基础产量/价格/生长天数/水需/地力消耗/保鲜率）与五种牲畜（生猪/肉牛/肉鸡/鸭/鱼，`LIVESTOCK`，分畜牧/家禽/水产，含日粮/繁殖率/疫病风险/市价）；四种土地取得方式（承包/购买/流转/租赁，`LAND_MODES`/`LAND_MODE_NAMES`）与地力/轮作/土地估值（`acquire_land()`/`improve_fertility()`/`rotate()`/`land_asset_value()`）及土地流转/征收（`land_transfer()`/`land_requisition()`）；种植（`plant()`）与田间管理（`fertilize()`/`irrigate()`/`weed()`）、按日生长转成熟（`grow()`）；收成（`harvest()`，产量受土壤/气候/灾害/技能/技术/田间管理影响并消耗地力）；养殖与繁育/疫病（`add_livestock()`/`feed_livestock()`/`breed_livestock()`/`livestock_disease()`）；销售五渠道（自给/集市/订单农业/合作社/期货，`MARKET_CHANNELS`，含价格倍率）与仓储保鲜/滞销/订单（`sell()`/`storage_spoil()`/`unsalable()`/`place_order()`/`fulfill_order()`）、合作社/期货（`join_cooperative()`/`futures_contract()`/`settle_futures()`）、年度结算与灾害（`settle_year()`/`reset_year()`/`strike_disaster()`/`rural_hollowing()`）、补贴（`apply_subsidy()`）。运行时经 `GameState.sim_runtime.farm` 持久化（`to_dict()`/`from_dict()`）。`SimHost` 接线 `farm_state()`/`agri_crops_catalog()`/`agri_livestock_catalog()`/`acquire_farm_land()`/`plant_crop()`/`grow_farm()`/`harvest_crop()`/`add_farm_livestock()`/`feed_farm_livestock()`/`sell_produce()`/`apply_farm_subsidy()`/`farm_panel_data()`，`advance()` 按日推进作物生长与仓储损耗。UI：新增「农业与乡土」面板（`agriculture`，第 43 面板）渲染土地/在田作物/养殖/仓储/经营概况；指令 `承包土地 [面积]`/`播种 <作物>`/`收割`/`养畜 <牲畜>`/`卖粮 <作物>`/`农业补贴` 与「看农业」入口；测试 `agriculture_test.gd` 覆盖模块纯逻辑。

### D23 数字生活与黑客
- **已接线**：`DigitalSystem`（`digital.gd`）数字身份（平台账号/实名/隐私/数据条目/联系人与数据泄露牵连、`new_identity()`/`create_account()`/`verify_real_name()`/`set_privacy()`/`add_data()`/`leak_data()`，泄露抬升 `exposure_heat`）与数字资产（账号/虚拟物品/加密钱包被盗与追回，`add_asset()`/`steal_asset()`/`recover_asset()`）；网络安全职业（合法方向：渗透测试/安全防护/应急响应/数据泄露处置，`SECURITY_JOBS`，`security_job()`/`handle_breach()`，无法律风险）；黑客（游戏内虚构抽象判定，四类目标个人/企业/政府/黑产，`HACK_TARGETS`，按犯罪技能树 hacking 等级 ×5 判定成败，结算收益、暴露概率与法律后果 `hack()`/`legal_consequence()`，不建模任何现实手法）；电子竞技（训练/战队/赛事/转会/伤病，`new_esports_career()`/`train()`/`play_match()`/`career_injury()`）；内容平台（直播/短视频，`CONTENT_PLATFORMS`，播放/涨粉/打赏/平台分成/带货 GMV `publish_content()`、翻车掉粉与封号 `scandal()`/`platform_ban()`、算法茧房 `algorithm_feed()`、网络成瘾 `internet_addiction()`）。运行时（身份/创作者/电竞）经 `GameState.sim_runtime.digital` 持久化（`to_dict()`/`from_dict()`）。`SimHost` 接线 `digital_state()`/`digital_platforms_catalog()`/`digital_hack_targets_catalog()`/`digital_security_jobs_catalog()`/`open_digital_account()`/`verify_digital_identity()`/`add_digital_asset()`/`digital_security_work()`/`digital_hack()`/`publish_digital_content()`/`digital_addiction()`/`digital_panel_data()`，网络安全/黑客/内容收益入账。「数字与平台」面板（`digital`）渲染数字身份/平台账号/数字资产/内容创作/电竞生涯；指令 `开账号 <平台>`/`实名认证`/`网络兼职 <类型>`/`发布内容 [平台]`/`黑客攻击 <目标>` 与「看数字」入口；测试 `digital_test.gd` 覆盖模块纯逻辑。

### D24 后期科技
- 事故/失重/辐射/深海健康惩罚无数值；长期气候变化不可实施（依赖 D1 与 `climate_trend`）；航天/深海/生物科技职业与装备内容缺失；无阶段面板与测试。

### D25 知识产权与媒体工业
- IP 不是可交易资产；侵权胜率无公式；媒体经营与舆情无字段；IP/媒体内容缺失；缺授权/转让/质押/维权动词。

### D26 制造业、工业与供应链
- 工厂/产线无运行时结构；产能公式无系数；良品率/工时无基线；design 有经营面板而 `ui.md` 无；制造品类定义字段缺失；断电/罢工停线接口未定义。

### D27 国际贸易、海关与物流
- 五种运输方式时效/费用/损耗/容量无数值；关务与结算（关税/增值税/汇率/Incoterms/信用证）无算法与 `TradeOrder`；贸易战/制裁接口未定；缺进出口/签约动词。

### D28 矿业、能源与资源
- 矿难/职业病无概率公式；能源价格作为宏观输入无接口（worldsim 缺项）；储量/品位/枯竭无数值；缺冶炼/电网运营动词。

### D29 农林牧渔深化
- 渔业资源恢复/休渔无数值；林权/碳汇无计价；枪支政策归属与狩猎许可接口未定义；缺休渔/护林/造林动词与测试。

### D30 餐饮与食品工业
- 菜谱/成本毛利/定价/翻台率无公式；门店/连锁无状态；食安事故链无参数；依赖缺失的经营面板；无子测试。

### D31 时尚、设计与奢侈品
- 作品评分公式不完整；鉴定/仿品无概率；品牌溢价/老化/复兴无数值；缺鉴定/拍卖/联名动词与测试。

### D32 体育产业与赛事
- 无体育实体结构（生涯/俱乐部/联赛）；转会/薪酬/伤病/俱乐部盈亏无公式；联赛/球队/赛事内容缺失；无面板与动词。

### D33 会展、演出与大型活动
- 活动无状态机与账目结构；票务/容量/上座/超售/事故/赞助无数值；每类活动定义字段缺失；缺售票/审批/赞助动词与测试。

### D34 荣誉、奖项与名人堂
- 无 awards/honors 字段与名人堂传承结构；评审规则/门槛/周期与黑幕暴露无数值；奖项定义缺失；无面板/动词；任务 34.1 测试错位。

### D35 安保、警务与刑侦
- 案件状态机无字段与转移条件；破案率/误判无公式；案件/证据/搜查令/线人/卧底无 schema；警务内容缺失；无案件面板与办案动词；D35↔D12 契约未定。

### D36 应急、消防与灾害救援
- 响应时间→伤亡映射与分诊算法缺失；disaster/救援任务/装备无 schema；救援场景/分诊/装备内容缺失；出警/灭火/急救动词缺失；D36↔D1/D18/D19 接口未定。

### D37 环保、碳排与可持续发展
- 碳核算/碳定价/配额/罚款/ESG 无模型；企业碳账户/污染事件无 schema；环保产业与碳标的内容缺失；无排污/回收/买碳配额动词与面板；碳市场权威边界未定。

### D38 市政公用与邮政
- 养护/施工/服务考核/特许经营/快递时效与理赔无模型；市政设施与邮政包裹无 schema；与 D18 设施边界未定；缺寄件/报修/特许经营动词与面板。

### D39 债务服务、当铺与小贷
- 利率上限/折当率/催收阈值/坏账/暴力催收无模型；`finances.debt` 无法表达多笔贷款/典当/抵押/信用分；借贷产品内容缺失；缺典当/赎回/众筹动词；灰色催收法律接口未定。

### D40 消费者保护与产品质量
- 三包/质保/召回/举证/维权成功率无模型；订单/投诉/召回无 schema；缺陷/召回/维权内容缺失；缺召回/索赔/集体维权动词；D40↔D9/D12/D30 接口未定。

### D41 收养、寄养与社会救助
- 收养资格评分/匹配/低保线/救助金额/慈善透明无模型；收养/寄养/监护/救助/慈善无 schema；救助项目内容缺失；缺寄养/低保申请动词与面板。

### D42 殡葬、器官捐献与纪念
- 殡葬费用/墓地价格/器官分配/捐献撤销/遗产不足无模型；葬礼/墓地/捐献/纪念碑无 schema；殡葬服务内容缺失；缺火化/海葬/祭扫/移植动词与面板。

### D43 玄学、命理与民俗信仰
- 成功率随机基准、安慰剂/确认偏误系数、诈骗追责概率缺失；服务/信仰/护身符/许愿无 schema；算命/风水/占星等内容与话术缺失；缺动词与面板。

### D44 隐秘异常收容体系
- 缺 anomaly 状态树与 2000 实体 schema；能力线曲线/暴露阈值/记忆删除剂量/认知抗性/对抗战斗无数值；收容管理与阵营任务交互未细化；D44↔D4/D12/传承接口未定。

### D45 医疗、生命科技与医药产业
- 分科/诊断/手术成功率/并发症/医保/区域医疗水平/临床试验周期与通过率无数值；就医/手术/试验/研发无 schema；分科/手术/试验内容缺失；缺移植/辅助生殖/研发动词与面板。

### D46 文娱内容产业
- 作品质量/口碑/销量/播放/分成/票务/订阅/广告/爆款/审查无公式；作品/团队/发行/IP 无 schema；游戏/动漫/网文/影视/综艺/音乐内容缺失；缺研发/改编/授权动词与面板。

### D47 建筑、工程与城市规划
- 资质门槛/中标评分/施工周期成本/质量判定/规划修正量无模型；工程/招投标/规划无 schema；工程类型/资质/规划内容缺失；缺勘察/造价/规划/拆迁动词与面板；规划→区域属性权威边界未定。

### D48 专业服务业
- 执业门槛/声誉接单/收费/执业风险/合伙人分成无模型；事务所/合伙人/项目无 schema；事务所类型/项目/风险内容缺失；缺审计/咨询/尽调动词与面板。

### D49 家庭与生活服务业
- 服务定价/平台抽成/背景核查/纠纷事故无模型；服务订单/家政/婚介/宠物服务无 schema；服务项目内容缺失；缺相亲/保洁/搬家/维修等动词与面板。

### D50 交通基建与航运
- 建设周期/成本/安全/票价/班期/准点/盈亏/补贴/区域修正无模型；基建项目/线路/班次/物流网络无 schema；工程与班期内容缺失；缺航线/班期/物流经营动词与面板；基建→宏观权威边界未定。

## 3. 修复路线（横切优先）

按依赖顺序：

1. **任务 48 — 全域数值基线与一致性向量**：把 D1–D50 余下跨端常量迁入 `shared/consistency/baseline/*.json` 单一真源，扩展生成器与一致性向量；补齐公式所需的系数表。
2. **任务 49 — 领域状态 schema 一次大扩展 + 迁移**：扩展 `player`/`save`/`worldsim`/`npc`，新增 case/disaster/anomaly/factory/IP/sports/org/land/digital/order/itinerary/medical/project/event/awards 等 schema，统一 `schema_version` 迁移；修复 `npc.relations` 类型与 `family`/`memory` 缺失。
3. **任务 50 — 内容目录补齐**：为 D35–D43、D45–D50 增补 content-catalog 专属节，对所有域补齐「完整表」的参数与 R56 数量目标。
4. **任务 51 — UI 全量面板与动词表**：`ui.md` 扩到全量面板（含经营、组织、案件、救援、医疗、工程、文娱、专业/生活服务、福利、殡葬、玄学、数字、体育、活动、奖项、疫情、战争、宏观/预报等），`verb-registry.md` 补齐缺失动词。
5. **任务 52 — 跨域接口与权威/补算契约**：定义统一事件与 modifier 字典、逐域权威边界、休眠唤醒补算契约。
6. **任务 53 — 测试覆盖补齐**：为每域补边界/失败测试，扩展跨语言一致性向量。

## 4. 决策记录

- 修复组织：横切优先。
- 存档 schema：一次大扩展 + `schema_version` 迁移。
- UI：扩到全量面板。
- D20 语言：独立类型，0..100 分项（口语/听力/读写），独立遗忘速率。
