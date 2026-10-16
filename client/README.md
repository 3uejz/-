# client/ — Godot 4 客户端

Godot 4.7.2-stable 桌面端工程。玩法由中文文字指令驱动，表现层为局部 3D 场景（切换加载，当前以程序化占位为主）。

- 引擎二进制：`/workspace/.toolchain/godot`
- headless：`/workspace/.toolchain/godot --headless --path client ...`
- 约定与命令见技能 `godot-client`。

## 骨架

```
autoload/   GameState / WorldClock / TickScheduler / SpeedController / Net（Autoload 单例）
sim/        确定性模拟系统（110+ 领域系统；rng.gd=SplitMix64，gregorian.gd=公历映射，baseline.gd=数值基线）
sim/sim_host.gd     玩法接线层：绑定 GameState、惰性挂载系统、按分钟推进、回写经济镜像
sim/flavor.gd       文案变化层：为高频动作生成确定性、时段场景化的叙事变体
sim/time_driver.gd  实时驱动：现实秒 × 倍速 → 游戏分钟（余数累积、单帧封顶）
command/    中文指令解析（parser/intent/verb_registry）与执行（intent_executor.gd：意图 → 系统 → 叙事/面板）
ui/         主界面壳（main.tscn）与面板（注册表 45 面板）、面板内容装配（panel_content.gd）
presentation/ 局部 3D 表现层（place_bindings.gd 场所绑定、scenes/placeholder_place.tscn 差异化占位场景）
assets/     美术资产目录与契约（见 assets/README.md：命名/LOD/替换工作流）
art/        叙事插画（illustrations/）
net/        REST 客户端与网关
content/    内容包加载（清单/差量/校验）
tests/      headless 测试（test_base.gd 基类 + 各 suite）
```

## 玩法接线

`main.gd` 在 `_ready()` 中经 `_init_simulation()` 建立 `SimHost`（绑定 `/root/GameState`）
与 `IntentExecutor`，并把执行器注入指令通路（`set_command_handler(_on_intent)`）：

```
文字/按钮 → CommandParser → CommandIntent → IntentExecutor → SimHost（模拟系统）
          → 叙事回显 + 时钟推进（GameState.clock ↔ WorldClock）+ 面板打开 + 存读档
```

指令输入的解析目录（物品/技能）来自 `SimHost` 注册的起步目录；未链接到目录的名称由执行器按名称回退匹配。
执行器经 `sim/flavor.gd` 为等待/睡/吃/锻炼/工作/学习等动作生成时段场景化的措辞变体。

## 挂机实时世界

除指令推进外，`main.gd._process()` 每帧按「现实增量 × 倍速」自动推进游戏内时钟与生理，
构成挂机实时世界（R1 / M0）：

```
_process(delta) → TimeDriver.consume(SpeedController.get_speed(), delta)
               → SimHost.advance(分钟) + TickScheduler.tick(now) + 刷新状态栏
```

- `sim/time_driver.gd`（`TimeDriver`）：把现实秒按倍速换算为游戏分钟，余数累积防漂移、单帧封顶 1 天。
- 快进目标（`SpeedController.target_minutes`）到达即停并回落 1 倍速；玩家死亡时暂停推进。
- **headless（测试/CI）下自动关闭**（`_auto_time_supported()` 判 `DisplayServer.get_name()`），
  保证测试确定性；可用 `set_auto_time()`/`auto_time_enabled()` 显式开关。

## 世界运行时

`SimHost` 在绑定时建立种子确定性的世界运行时（R5/R50、D1/D2）：

- `sim/geo.gd`（`GeoData`）按世界种子生成六级地理；玩家所在城市由 `player.nation` 解析（无有效值时降级首发国家 CN），登记为**活动区域**并绑定气候带。
- `sim/region_manager.gd`（`RegionManager`）在 `SimHost.advance()` 中随游戏内时钟推进活动区域的人口/经济日级结算；`sim/domain_wake.gd`（`DomainWake`）注入其中，供案件/灾害/工程等条目在休眠窗口补算。
- `sim/weather.gd`（`WeatherSystem`）按区域 + 当前时刻**查询式**演化，无需逐帧 tick。
- 主壳 `_panel_context()` 经 `current_region_id()`/`regions_view()`/`weather_now()`/`weather_panel_data()` 向地图与天气面板提供所在区域、实时天气与未来 7 日预报；旅行/搬迁经 `set_home_region()` 切换。
- 地图面板（`看地图`）内嵌 `ui/map/map_view.tscn` 绘制可缩放的 2D 混合地图，并注入 `SimHost.geo`。
- 地理由种子确定性生成、不入档（design：存档只记变化量）；区域增量在 `advance()` 后写入 `world_delta.regions`（符合 `region_delta` 契约，经济/气候等收进 `snapshot`），读档时经 `load_deltas()` 恢复并按地理重建气候。
- 宏观→微观：买卖经 `SimHost.region_price_index()` 把所在区域物价指数传入 `items.buy/sell`（`region_mult`，缺省 1.0），物价随区域与年份通胀而变。
- 所在区域持久化：`player.region_id`（可选，见 `player.schema.json`）记录当前区域；`set_home_region()` 写入、读档时优先按它解析，缺省回落按 `player.nation` 推导。地理与气候不入档。
- 领域实体离线补算：`SimHost.advance()` 调 `domain_wake.advance_to(clock)` 随游戏内时钟推进已注册的案件/工程/灾害/催收/异常/手术（`SimHost.domain_register()` 注册，规则见 `sim/domain_wake.gd`）。

## 核心人生闭环

`SimHost` 把恋爱/婚姻、房产与继承接入指令层，构成可玩的人生闭环：

- `sim/npc.gd`（`NpcSystem`）+ `sim/relations.gd`（`RelationsSystem`）：绑定时按（种子, 区域, 序号）确定性生成所在城市熟人名册（`_ensure_acquaintances()`），建立初始五维关系；`acquaintances()`/`find_person()` 供解析目录与社交链接。
- 婚恋（`sim/family.gd` `FamilySystem`）：`表白`/`求婚` 经解析器链接熟人，`affection` 达标时 `SimHost.marry_with()` 写入 `player.family.spouse_id` 并纳入家庭圈层；`离婚` 经 `divorce()` 清档。婚姻状态随存档恢复（`_ensure_acquaintances()` 依据 `spouse_id` 重建）。
- 生育与族谱：`怀孕` 经 `try_conceive()` 写入 `player.family.pregnancy`（`due_minutes = now + 280 天`）；`advance()` 到期触发 `deliver_child()`，生成子女 NPC（继承父母能力/人格）落档到 `world_delta.npcs` 与 `player.family.children_ids`，并记入 `legacy.lineage`/`history`；`children()` 读取名下子女；分娩后反向补齐族谱（`_link_siblings()` 子女间互填 `sibling_ids`、`_link_partner_child()` 把子女挂到配偶 `family.children_ids`）。
- 收养与监护：`收养` 经 `SimHost.adopt_child()` 生成收养子女 NPC（独立 id 序号段 `ADOPT_SEQ_BASE`），计入 `player.family.children_ids` 与 `adopted_ids`，并记 `legacy.history` 收养条目；`指定监护人 <人物>` 经 `assign_guardian()` 写入 `player.family.guardian_ids`；`legal_guardian()` 在死亡结算时解析未成年子女监护归属（指定监护人 > 父母 > 配偶 > 成年子女 > 兄弟姐妹 > 熟人）。
- 子女成长与早夭（`sim/parenting.gd` `ParentingSystem`）：`advance()` 经 `_grow_children()` 做年度成长结算（属性 = 基因×0.5 + 照护×0.2 + 教育×0.2 + 随机×0.1，更新阶段/成年独立），`_check_child_mortality()` 按 `PARENT_EARLY_DEATH_RATE` 年化折算做早夭判定并记 `legacy.history`。

- 房产（`sim/property.gd` `PropertySystem`）：`看房`/`买房`/`卖房`/`出租` 经 `SimHost.property_*()` 交易；房源按（种子, 区域）确定性生成、不入档，已购房源从挂牌移除；名下房产随 `player.assets` 持久化；`advance()` 跨月触发 `property.monthly_settle()` 结算贷款本息/物业/租金/折旧/断供法拍并回写财务镜像。
- 宠物（`sim/pet.gd` `PetSystem`）：`领养`/`喂养`/`训练宠物` 经 `SimHost.adopt_pet()`/`feed_pets()`/`train_pets()` 落档到 `player.pets`（`id`/`content_key`/`species`/`name`/`age`/`hunger`/`mood`/`health`/`training`/`bond`/`alive`/`lost`）；`advance()` 按日推进饥饿/衰老/走失/寿终并回报 `pet_death` 事件；「家庭与宠物」面板渲染宠物近况。
- 继承与人生结算（`sim/inheritance.gd` `InheritanceSystem`）：`立遗嘱` 写入 `player.will`；死亡时 `advance()` 触发 `settle_inheritance()`，按遗嘱或法定顺序（配偶→子女→父母→兄弟姐妹）分配遗产净额，并记入 `legacy.history`；`death_summary()` 输出姓名/年龄/最终称号与遗产估算。
- 存档与运行态：`GameState.sim_runtime.survival` 持久化生存运行时（`SurvivalSystem.to_dict()`：成瘾复发/营养过量天数/死亡标志/遗嘱），读档经 `_persist_survival()`/`from_dict()` 还原。
- 人生结算面板：死亡时主壳在消息流输出结算并打开「人生结算」面板（`ending`，条件可见），由 `panel_content.ending()` 渲染生平/终号/遗嘱/遗产/法定继承人/人生大事记。
- 人格与精神健康（`sim/personality.gd` `PersonalitySystem`、`sim/mental_health.gd` `MentalHealthSystem`、`sim/happiness.gd` `HappinessSystem`）：大五人格与阈值派生标签（`personality_tags()`）驱动对话风格/职业适配/关系速度；22 病种三维病程（频率/强度/时长）经 `advance()` 推进并在压力超阈或幸福长期低值时掷骰新发（`roll_triggers()`），`mental_onset()` 供重大事件强制触发；`心理咨询`/`心理治疗`/`精神科用药`/`重症干预`/`放松` 指令经 `SimHost.mental_treat()`/`relax()` 结算疗效三态（根治/缓解/无效，含误诊与副作用）并扣费；`player.health.mental` 回写病程，运行时经 `GameState.sim_runtime.mental` 持久化（`to_dict()`/`from_dict()`）；`_update_happiness()` 按关系/事业/健康/信仰/意义感结算幸福。「精神健康」面板渲染情绪/幸福/大五人格/标签/病程。
- 精神追求与信仰（`sim/spirituality.gd` `SpiritualitySystem`）：价值观三轴（利己-利他/保守-开放/物质-精神）随选择微调、七类精神追求（冥想/修行/哲学阅读/写作/自省/志愿服务/艺术创作）按小时降压力并漂移人格与价值观、十派信仰/哲学与修持境界、四类精神危机及出口化解、邪教卷入风险；`修持 <法门>`/`皈依 <信仰>`/`深化信仰`/`化解危机 <出口>` 指令经 `SimHost.pursue_spirit()`/`convert_faith()`/`deepen_faith()`/`resolve_spirit_crisis()` 结算；运行时经 `GameState.sim_runtime.spirituality` 持久化（`to_dict()`/`from_dict()`）；皈依后信仰境界抬升幸福/意义分量。「精神追求」面板渲染价值观/信仰境界/追求深度/精神危机。
- 组织与社团（`sim/organizations.gd` `OrganizationSystem`）：八类组织（工会/行业协会/NGO/兴趣俱乐部/宗教团体/政党/秘密结社/犯罪团伙）、四级晋升阶梯、五类集体行动（罢工/请愿/募捐/游行/抵制，成功率由规模/支持/压力/舆论决定）、派系斗争、秘密组织暴露清算与内鬼排查、破产解散；`加入组织 <组织>`/`退出组织`/`缴会费`/`组织任务`/`罢工`/`请愿`/`募捐`/`游行`/`抵制` 指令经 `SimHost.join_organization()`/`leave_organization()`/`pay_org_dues()`/`do_org_task()`/`org_collective_action()` 结算；成员资格随 `player.org_memberships` 持久化，组织运行态经 `GameState.sim_runtime.organizations` 持久化（组织由（种子, 区域, 类型序号）确定性生成）。「组织」面板渲染「我的组织 / 可加入组织」。

- 语言与文化（`sim/language.gd` `LanguageSystem`）：语言独立类型（0..100），五种语言分口语/听力/读写三项（权重 0.4/0.3/0.3），三种学习方法（课程/环境沉浸/自学）水平越高增益越小，长期不用按天遗忘（30 天宽限）；考试发证、专业术语门槛与移民/外交/翻译职业解锁、六大节日修正（商铺/交通/社交/消费/心情）、五种文化距离与适应/冲击曲线；`学语言 <语言> [时长]`/`沉浸 <语言> [天数]`/`语言考试 <语言>`/`适应文化 <文化>` 指令经 `SimHost.study_language()`/`immerse_language()`/`take_language_exam()`/`adapt_culture()` 结算；语言档案随 `GameState.sim_runtime.language`、文化适应随 `GameState.sim_runtime.culture` 持久化；`advance()` 按日衰减语言。「语言与文化」面板渲染语言能力/语言证书/文化适应/节日民俗。

- 残障与养老（`sim/disability_elderly.gd` `DisabilityElderlySystem`）：残障四来源/四类型/轻中重三级以移动能力统一修正受限动词与就业/社交歧视；六类辅具与康复训练部分恢复；养老三模式（居家/社区/机构）含退休金/社保/临终关怀；认知障碍影响决策能力与遗嘱效力并引入监护制度；`装辅具 <辅具>`/`康复训练`/`无障碍改造`/`选养老 <模式>`/`临终关怀`/`指定监护 <监护人>` 指令经 `SimHost.fit_disability_device()`/`disability_surgery()`/`set_accessible_place()`/`choose_care_mode()`/`hospice_care()`/`establish_guardianship()` 结算；运行态随 `GameState.sim_runtime.disability` 持久化；「残障与养老」面板渲染残障状态/辅具与康复/养老与社保/监护与决策。

- 农业与乡土（`sim/agriculture.gd` `AgricultureSystem`）：六种作物（粮/经济/蔬/药四类用途，各有生长天数/产量/水需/地力消耗/保鲜率）与五种牲畜（畜牧/家禽/水产，含日粮/繁殖率/疫病风险），四种土地取得方式（承包/购买/流转/租赁）与地力/轮作/估值；`承包土地 [面积]`/`播种 <作物>`/`收割`/`养畜 <牲畜>`/`卖粮 <作物>`/`农业补贴` 指令经 `SimHost.acquire_farm_land()`/`plant_crop()`/`harvest_crop()`/`add_farm_livestock()`/`sell_produce()`/`apply_farm_subsidy()` 结算，收成受土壤/气候/灾害/技能/技术/田间管理影响；`advance()` 按日推进作物生长与仓储损耗；运行态随 `GameState.sim_runtime.farm` 持久化；「农业与乡土」面板渲染土地/在田作物/养殖/仓储/经营概况。

- 数字生活与平台（`sim/digital.gd` `DigitalSystem`）：数字身份（平台账号/实名/隐私/数据条目与数据泄露牵连）与数字资产（账号/虚拟物品/加密钱包被盗与追回）；网络安全职业（渗透测试/安全防护/应急响应/数据泄露处置，合法无法律风险）；黑客（游戏内虚构抽象判定，四类目标，按 hacking 技能判定成败并结算收益/暴露概率/法律后果，不建模任何现实手法）；电子竞技（训练/战队/赛事/转会/伤病）；内容平台（直播/短视频，播放/涨粉/打赏/分成/带货与翻车封号、算法茧房、网络成瘾）；`开账号 <平台>`/`实名认证`/`网络兼职 <类型>`/`发布内容 [平台]`/`黑客攻击 <目标>` 指令经 `SimHost.open_digital_account()`/`verify_digital_identity()`/`digital_security_work()`/`publish_digital_content()`/`digital_hack()` 结算；运行时随 `GameState.sim_runtime.digital` 持久化；「数字与平台」面板渲染数字身份/平台账号/数字资产/内容创作/电竞生涯。
- 后期科技（`sim/late_tech.gd` `LateTechSystem`）：科技阶段（信息→智能→星际，逐级严格解锁）；新兴职业（机器人运维/AI 训练师/航天工程师/宇航员/深海勘探/AI 伦理/生物科技/太空矿工/星球殖民者，含技能门槛与薪资）；高风险高回报任务（太空旅行/空间站工作/深海作业/星球殖民，事故与伤亡判定）；极端环境健康惩罚（失重/辐射/深海高压）；自动化冲击（失业率与社会保障议题）；生物科技延寿（联动寿命）；`解锁科技`/`应聘科技职业 <职业>`/`科技任务 <任务>`/`生物延寿 [投入]` 指令经 `SimHost.unlock_late_tech_stage()`/`apply_late_tech_career()`/`risk_late_tech_mission()`/`invest_biotech_lifespan()` 结算；运行时随 `GameState.sim_runtime.late_tech` 持久化；「后期科技」面板渲染科技阶段/科技职业/高风险任务。
- 知识产权与媒体（`sim/ip_media.gd` `IpMediaSystem`）：知识产权（版权/专利/商标/商业秘密，各有保护年限/登记费/许可费率）登记、续展、到期进入公有领域、许可/转让/质押，以及侵权监测（相似度/取证）与诉讼（胜率由证据/律师/法院倾向线性决定，胜诉结算赔偿与禁令）；媒体机构（新闻社/出版社/影视公司/MCN/平台）作品发行（票房/销量与声誉由质量/宣发/舆论/运气决定）、负面报道与危机公关/撤稿、平台审核与版权下架，以及抢注/恶意诉讼/抄袭揭露/造谣担责等边界；`登记知识产权 <类型>`/`知识产权授权 <IP> [规模]`/`知识产权转让 <IP> [价格]`/`知识产权质押 <IP> [金额]`/`知识产权维权 <IP>`/`开办媒体 <类型>`/`发行作品 <标题>` 指令经 `SimHost.register_ip_asset()`/`license_ip_asset()`/`transfer_ip_asset()`/`pledge_ip_asset()`/`sue_ip_infringer()`/`register_media_outlet()`/`release_media_work()` 结算；运行时随 `GameState.sim_runtime.ip_media` 持久化；「知识产权与媒体」面板渲染知识产权/媒体机构。
- 制造业与供应链（`sim/manufacturing.gd` `ManufacturingSystem`）：七类岗位（普工/技工/工程师/厂长/采购/品控/研发，各含技能/工资/产出/质量/供应）、四种经营模式（开厂/代工/自建品牌/技术授权，各含资本门槛/资质/品牌加成与升级路径）、三张配方（钢制零件/塑料件/电路板，原料单耗归一）、供应商与断料/涨价风险、产能三因子（设备/人力/效率，报告瓶颈）、良品率（基础+品控/工程师/研发+自动化−普工占比）、成品库存与订单交付（品牌加成结算收入）、五类产线中断（停电/断料/设备故障/罢工/缺勤）与安全/自动化/环保限产、资金链；`开办工厂 [模式]`/`招工 <岗位> [人数]`/`采购原料 <原料> [数量]`/`生产 <配方> [批次]`/`接单 <配方> [数量]`/`交付订单 [序号]`/`改进经营模式 <模式>` 指令经 `SimHost.found_factory()`/`mfg_hire()`/`mfg_purchase()`/`mfg_produce()`/`mfg_accept_order()`/`mfg_deliver_order()`/`mfg_set_mode()` 结算；运行时随 `GameState.sim_runtime.manufacturing` 持久化；「经营」面板增补工厂概况/产线人员/原料库存/成品库存/订单分区。
- 国际贸易、海关与物流（`sim/trade.gd` `TradeSystem`）：外贸单据七阶段（询盘→签约→报关→检验检疫→运输→清关→交付，`STAGES`/`STAGE_NAMES`）；五种运输方式（海运/空运/铁路/快递/管道，`TRANSPORT_MODES`，含时效/吨公里运费/损耗率/运力与最低收费）与运费报价（`estimate_freight()`，超载拒绝）；完税价格/关税/增值税/落地成本结算（`calculate_duties()`/`declare_customs()`）；汇率换算（`convert()`/`fx_rate()`/`has_currency()`）与结算方式（信用证/汇付/保理/赊销，`SETTLEMENTS`/`settlement_fee()`）、汇率对冲与损益（`hedge_fx()`/`fx_loss()`）；贸易壁垒（加税/配额/反倾销/原产地，`BARRIERS`/`apply_barrier()`）与风险事件（贸易战/制裁/战争，`RISK_EVENTS`/`risk_event()`，含改航线与滞留）；Incoterms 责任划分（`INCOTERMS`/`INCOTERM_DUTIES`）；跨境服务（货代/报关行/海外仓/跨境电商，`SERVICES`/`add_service()`）；检验检疫/清关/交付与滞港费/货损/退运（`quarantine_inspect()`/`clear_customs()`/`deliver()`/`settle_demurrage()`/`damage_loss()`/`return_shipment()`）；`出口 <商品> [货值]`/`规划运输 <方式>`/`签订外贸合同 <术语>`/`报关`/`清关`/`外贸交付`/`结汇` 指令经 `SimHost.export_shipment()`/`plan_trade_transport()`/`sign_trade_contract()`/`declare_shipment()`/`clear_shipment()`/`deliver_shipment()`/`settle_shipment()` 结算（报关扣税费、交付入出口收入、结汇计手续费）；运行时随 `GameState.sim_runtime.trade` 持久化；「经营」面板增补外贸单据分区。
- 矿业、能源与资源（`sim/mining_energy.gd` `MiningEnergySystem`）：四类矿种（铁矿/铜矿/煤矿/金矿，含基础品位/储量/冶炼收得率/价格）；矿权特许（`acquire_concession()`，需资质与最低资本）；勘探（`explore()`，按投入揭示储量与品位）；开采（`extract()`，产量随安全与储量、消耗并枯竭停产）与转运（`transport_ore()`）；冶炼（`smelt()`，按品位与收得率折算金属）与出售（`sell()`）；安全投入与矿难概率（`safety_invest()`/`accident_rate()`/`accident_check()`，塌方/瓦斯爆炸/冒顶/尘肺）与环保追责（`environmental_liability()`）；能源价格周期（`tick_energy()` 确定性正弦，随游戏内时钟按年演化）、期货/长约（`futures_contract()`/`settle_futures()`/`long_term_contract()`）、新能源项目（风电/光伏/核电/储能，`new_energy_project()`/`grid_dispatch()`/`carbon_trade()`/`apply_subsidy()`）；资源城市衰退（`resource_city_decline()`）与战略资源管制囤积（`set_strategic_control()`/`stockpile()`/`tradable_ratio()`）；`开矿 <矿种>`/`取得矿权`/`勘探 [预算]`/`开采 [数量]`/`冶炼 [数量]`/`卖矿 [数量]`/`建能源项目 <类型>` 指令经 `SimHost.open_mine()`/`acquire_mine_concession()`/`explore_mine()`/`extract_ore()`/`smelt_ore()`/`sell_metal()`/`build_energy_project()` 结算；运行时随 `GameState.sim_runtime.mining`（`mine`/`energy`）持久化；「经营」面板增补矿场概况/能源价格/新能源项目分区。
- 农林牧渔深化（`sim/primary_industry.gd` `PrimaryIndustrySystem`）：鱼种（鳕鱼/金枪鱼/虾）与渔场船队（`new_fishery()`/`add_boat()`）；休渔（`start_closed_season()`/`is_closed_season()`，违规捕捞追责）；捕捞与资源恢复（`catch_fish()`/`recover_resource()`，过度捕捞使恢复变慢）、水产养殖（`harvest_aquaculture()`）与风暴（`storm_check()`）；林分（用材林/防护林/经济林）与林权（`new_forest()`/`grant_forest_rights()`）、采伐造林（`log_trees()`/`reforest()`）、护林防火（`patrol_fire()`/`fire_check()`）、木材市场与碳汇（`timber_market()`/`carbon_sink()`）；狩猎（`new_hunter()`/`hunting_license()`/`hunt()`/`illegal_hunt()`/`legal_consequence()`，含罚款与通缉等级）；生态（`new_ecology()`/`over_develop()`）；`建渔场`/`捕鱼 <鱼种> [数量]`/`休渔`/`承包林场 [林分]`/`采伐 [数量]`/`造林 [数量]`/`申请狩猎许可`/`狩猎 <猎物> [数量]` 指令经 `SimHost.new_fishery()`/`fish_catch()`/`start_closed_season()`/`new_forest()`/`log_trees()`/`reforest()`/`apply_hunting_license()`/`hunt()` 结算；运行时随 `GameState.sim_runtime.primary`（`fishery`/`forest`/`hunter`/`ecology`）持久化；「农业与乡土」面板增补渔场/林场/狩猎/生态分区。
- 餐饮与食品工业（`sim/dining.gd` `DiningSystem`）：菜谱（家常小炒/红烧肉/蒜蓉海鲜/牛肉面，`ingredients` 归一推导单份成本）与菜单/定价/毛利（`add_to_menu()`/`set_price()`/`recipe_margin()`）；选址与翻台率（`choose_location()`/`location_quality()`/`expected_turnover()`/`demand()`）；单日经营（`sell_day()`，堂食/外卖按渠道计营收、抽成、食材成本、房租与工资）；员工（主厨/厨师/服务员/店长，`hire()`/`daily_payroll()`）；扩张模式（单店/连锁/中央厨房/连锁加盟/食品工业，`can_enter_mode()`/`expand_to()`，需资本与标准化达标）；食安认证（卫生 A 级/HACCP/ISO 22000/有机，`certify()`）；食品工业（加工/保质/渠道分销，`process_food()`/`spoilage()`/`distribute()`）；风险（食安事故与召回，`food_safety_incident()`/`recall_product()`）；评价与营销（`review_stars()`/`rank_listing()`/`marketing_campaign()`/`viral_event()`）；`建餐厅`/`加菜 <菜名>`/`定菜价 <菜名> <价格>`/`营业 [渠道]`/`雇厨 <岗位> <人数>`/`扩张餐饮 <模式>`/`食品认证 <认证>`/`营销推广 <方式> [预算]`/`加工食品 <菜名> <数量>`/`分销食品 <菜名> <数量> [渠道]` 指令经 `SimHost.open_restaurant()`/`restaurant_add_menu()`/`restaurant_set_price()`/`restaurant_sell_day()`/`restaurant_hire()`/`restaurant_expand()`/`restaurant_certify()`/`restaurant_marketing()`/`restaurant_process()`/`restaurant_distribute()` 结算；运行时随 `GameState.sim_runtime.dining`（`restaurant`）持久化；「经营」面板增补餐厅概况/菜单/员工/预包装库存/食安认证分区。
- 时尚、设计与奢侈品（`sim/fashion.gd` `FashionSystem`）：学科（服装/珠宝/工业/平面/家居）与品牌定位（大众/轻奢/奢侈/设计师）；作品评分（技能×0.45 + 灵感×0.20 + 潮流契合×0.35 − 抄袭惩罚，`create_design()`/`grade_of()`）；潮流周期（新兴→上升→顶峰→退潮，`new_trend()`/`advance_trend()`/`leading_or_following()`）；时装周与联名（`fashion_week()`/`collab()`）；限量发售与品牌经营（`limited_edition()`/`open_store()`/`run_marketing()`/`brand_aging()`/`renew_brand()`）；代言人（`endorse()`/`endorser_scandal()`）；奢侈品市场（`authenticate()`/`secondhand_price()`/`auction()`/`collectible_value()`/`counterfeit_hit()`）；抄袭指控（`plagiarism_accusation()`）；`建品牌 <定位>`/`创作设计 <学科>`/`时装周 [季节]`/`联名 [合作热度]`/`限量发售 <品类> [数量]`/`设计师营销 <方式> [预算]`/`品牌复兴 [预算]`/`鉴定真伪 <品类>` 指令经 `SimHost.new_brand()`/`fashion_design()`/`fashion_week()`/`fashion_collab()`/`fashion_limited_edition()`/`fashion_marketing()`/`fashion_renew()`/`fashion_authenticate()` 结算；运行时随 `GameState.sim_runtime.fashion`（`brand`/`trend`）持久化；「经营」面板增补品牌概况/时尚潮流/作品/库存分区。
- 体育产业与赛事（`sim/sports_industry.gd` `SportsIndustrySystem`）：运动员职业化（青训→职业合同→转会→巅峰→退役，`new_pro()`/`youth_graduate()`/`sign_pro_contract()`/`transfer()`/`offer_contract()`/`retire()`）；身价估值与赞助（`market_value()`/`sponsorship()`）；赛事体系（联赛/杯赛/奥运/世界杯/全运，`new_league()`/`register_club()`/`schedule_season()`/`play_match()`/`standings()`/`apply_promotion_relegation()`/`national_callup()`/`international_tournament()`）；丑闻与合规（兴奋剂/假球/赌球/转会黑幕，`doping_test()`/`set_doping()`/`commit_scandal()`/`investigate()`）；伤病与康复（`injury_risk()`/`injure()`/`rehab()`）；俱乐部经营（`club_matchday_income()`/`club_season_income()`/`club_finance()`/`club_bankrupt()`）；`开启球涯`/`比赛`/`转会 [转会费]`/`代言合同 [金额]`/`运动康复 [天数]`/`兴奋剂检测`/`退役` 指令经 `SimHost.start_sports_career()`/`sports_play_match()`/`sports_transfer()`/`sports_sponsorship()`/`sports_rehab()`/`sports_doping_test()`/`sports_retire()` 结算；运行时随 `GameState.sim_runtime.sports`（`player`/`club`/`rival`/`league`）持久化；「体育」面板渲染球员生涯/所属球会/积分榜分区（入口「看球队」/「看体育」）。
- 会展、演出与大型活动（`sim/events_expo.gd` `EventsExpoSystem`）：活动类型（演唱会/音乐节/漫展/博览会/发布会/体育赛事/婚礼庆典）；流程（场地租赁→报批→招商→票务→安保→现场→复盘，`new_event()`/`rent_venue()`/`apply_approval()`/`add_sponsor()`/`sell_tickets()`/`set_security()`/`hold_event()`/`after_action_review()`）；赞助层级（冠名/金牌/银牌/物资）与上座率（`expected_fill_rate()`/`add_hype()`）；风险（超售/踩踏/天气/舆情/安保失效/艺人违约，`scalping()`/`artist_breach()`/`refund_wave()`/`ticket_fraud()`/`accident_liability()`）；策划职业路径（`new_planner()`/`career_progress()`）；`活动策划 [角色]`/`办活动 <类型>`/`租场地 [费用]`/`报批`/`拉赞助 <层级>`/`售票 [数量]`/`布置安保 [等级]`/`举办活动`/`活动复盘` 指令经 `SimHost.start_event_career()`/`events_new()`/`events_rent_venue()`/`events_approval()`/`events_sponsor()`/`events_sell_tickets()`/`events_set_security()`/`events_hold()`/`events_review()` 结算；运行时随 `GameState.sim_runtime.events`（`event`/`planner`）持久化；「活动与展会」面板渲染我的活动/策划职业分区。
- 荣誉、奖项与名人堂（`sim/honors.gd` `HonorsSystem`）：六大领域奖项（学术/艺术/体育/商业/公共/军事，各含门槛/周期/威望/通过线与评审权重）；候选人档案与提名（`new_candidate()`/`set_achievement()`/`set_jury_relation()`/`nominate()`）；确定性评审（加权和 + 偏好加成 + 黑幕/政治化修正，`evaluate()`/`award()`）；黑幕（买奖/学术造假/评审腐败，`mark_scandal()`/`has_scandal()`/`has_revealed_scandal()`/`expose_scandal()`）；名人堂与传承（`new_hall()`/`enshrine()`/`hall_size()`/`hall_entries_of()`/`revoke()`/`inherit_evaluation()`）；并列与影响（`resolve_tie()`/`honor_effects()`）；`荣誉档案 [成就]`/`提名 <奖项>`/`评审 <奖项>`/`领奖 <奖项>`/`买奖 <奖项>`/`揭露黑幕` 指令经 `SimHost.start_honor_profile()`/`honors_nominate()`/`honors_evaluate()`/`honors_award()`/`honors_buy()`/`honors_expose()` 结算；运行时随 `GameState.sim_runtime.honors`（`candidate`/`hall`）持久化；「奖项与荣誉」面板渲染荣誉档案/已获荣誉/名人堂分区（入口「看奖项」/「名人堂」）。
- 安保、警务与刑侦（`sim/police.gd` `PoliceSystem`）：公职分工（警察/法医/刑侦/经侦/缉毒，各含技能侧重与证据加成）；案件状态机（勘查→取证→追查→侦破/冷案，`new_case()`/`survey()`/`collect()`/`advance()`/`attempt_solve()`）；证据链（物证/人证/供词/监控/电子记录/鉴定，`evidence_score()`/`add_evidence()`）；程序与合规（搜查令 `request_warrant()`，非法取证被排除；`legality_score()`/`abuse_power()`/`collude()`）；侦查手段（`interrogate()`/`use_informant()`/`deploy_undercover()`/`tech_surveillance()`）；破案率与冤假错案（`solve_probability()`，证据薄弱+逼供→误判）；民营安保（`new_security_firm()`/`take_contract()`/`resolve_contract()`/`assign_staff()`）；`立案 <罪名>`/`勘查`/`取证 <证据种类> [强度]`/`搜查令`/`审讯 [压力]`/`线人`/`卧底`/`技侦`/`侦破`/`开安保公司 <名称>`/`承接安保 <业务>`/`履约安保` 指令经 `SimHost.police_start_case()` 等结算；运行时随 `GameState.sim_runtime.police`（`case`/`firm`）持久化；「案件与法律」面板渲染经办案件/证据链/安保公司/安保业务分区（入口「看案件」）。
- 应急、消防与灾害救援（`sim/emergency.gd` `EmergencySystem`）：职业（消防/急救/海警/山地/地震/洪水救援，含基准响应时间与专用装备）；触发流程（报警→出警→救援→善后，`new_incident()`/`dispatch()`/`rescue()`/`aftermath()`/`advance()`）；响应时间模型（随距离上升、随训练/装备/队伍/志愿者下降，`response_time()`）；伤亡与分诊（`estimate_casualties()` 随响应时间单调上升，`triage()` 按红>黄>绿优先救治）；边界（现场二次事故 `secondary_incident()`、救援人员伤亡 `rescuer_casualties()`、指挥失当追责与灾后心理创伤）；志愿救援（`new_volunteer_org()`/`purchase_equipment()`/`recruit_volunteers()`/`volunteer_dispatch()`）；`接警 <类型> [严重度]`/`出警 [距离]`/`现场救援`/`二次事故`/`善后处理`/`开志愿队 <名称>`/`采购救援装备 <项目> [费用]`/`招募志愿者 [人数]`/`志愿出警` 指令经 `SimHost.emergency_new_incident()` 等结算；运行时随 `GameState.sim_runtime.emergency`（`incident`/`org`）持久化；「救援与灾害」面板渲染处置事件/检伤分诊/志愿救援队分区（入口「看灾害」）。
- 环保、碳排与可持续发展（`sim/environment.gd` `EnvironmentSystem`）：市政环保（垃圾分类/回收/污水处理/空气治理/排污许可，`new_city_env()`/`recycle()`/`treat_sewage()`/`air_control()`/`issue_permit()`/`pollution_index()`）；企业碳排（碳平衡/合规购买配额或罚款/碳交易/碳足迹/ESG 评级，`new_enterprise()`/`carbon_balance()`/`compliance()`/`carbon_trade()`/`carbon_footprint()`/`esg_rating()`/`report_carbon()`）；从业（环保企业/NGO/绿色能源/环保工程，`new_career_org()`/`run_project()`）；后果与诉讼（`pollute()`/`expose_pollution()`/`environmental_lawsuit()`）；可持续与边界（`green_subsidy()`/`low_carbon_transition()`/`illegal_discharge()`/`investment_profit_squeeze()`/`nimby()`）；`垃圾分类 [比率]`/`回收 [数量]`/`污水处理 [比率]`/`空气治理 [投入]`/`排污许可 <来源> [额度]`/`碳核算`/`碳交易 [信用]`/`碳履约 [方式]`/`碳申报 [排放]`/`开环保公司 <类型>`/`承接环保项目 <名称> [预算]`/`举报污染`/`环境诉讼`/`申请绿色补贴 [金额]`/`低碳转型 [投入]`/`偷排 [数量]`/`邻避评估 [规模]` 指令经 `SimHost.env_set_garbage_sorting()` 等结算；运行时随 `GameState.sim_runtime.environment`（`city`/`enterprise`/`org`）持久化；「环保与碳市场」面板渲染城市环保/企业碳账户/环保组织分区（入口「看环保」）。

- 市政公用与邮政（`sim/municipal.gd` `MunicipalSystem`）：市政设施（道路/桥梁/公园/环卫/污水/照明/公厕，`new_city()`/`maintain_facility()`/`facility_condition()`/`facility_grade()`/`age_facilities()`/`inspect_parks()`）；施工与通行（`start_construction()`/`advance_construction()`/`start_excavation()`/`commute_impact()`，反复开挖判「拉链路」）；扰民与投诉（`report_nuisance()`/`resolve_complaint()`/`unresolved_complaints()`）；邮政快递（`new_postal_hub()`/`new_parcel()`/`accept_parcel()`/`estimate_delivery()`/`ship()`（丢件/破损/时效）/`postal_overload()`/`file_claim()`）；快递员职业路径（`new_courier()`/`courier_deliver()`/`promote_courier()`，五级）；特许经营与政府购买（`grant_franchise()`/`assess_service_quality()`/`franchise_complaint()`/`government_purchase()`）；`市政养护 <设施> [投入]`/`设施巡检`/`市政施工 <设施> [工期]`/`施工推进 [天数]`/`道路开挖 <设施>`/`市政投诉 [事由]`/`投诉处理 [编号]`/`邮政寄件 [编号]`/`包裹发运`/`包裹理赔`/`快递生涯`/`揽投`/`特许经营 <服务>`/`服务考核 [得分]`/`政府购买 <服务> [预算]` 指令经 `SimHost.municipal_maintain()` 等结算；运行时随 `GameState.sim_runtime.municipal`（`city`/`hub`/`courier`/`license`）持久化；「市政」面板渲染市政设施/通行与扰民/邮政枢纽/快递员分区（入口「看市政」）。

- 债务服务、当铺与小贷（`sim/debt_service.gd` `DebtServiceSystem`）：放贷业务（典当/民间借贷/小额信贷/消费金融/众筹/P2P，`BUSINESSES`，P2P 时代限定 `business_available()`）；借款与放贷人（`new_lender()`/`new_loan()`/`add_collateral()`/`add_joint_guarantee()`）；合规监管（利率上限 `rate_compliant()`/牌照 `license_status()`/`compliance_status()`/`regulate()`）；风控放贷（`assess_credit()`/`disburse()`/`approve_loan()`/`default_loan()`）；合法/灰色双路径催收（`collect()`，合法路径不违法且人身风险为 0，灰色路径产生违法标记与法律后果，合规瑕疵加重，`record_suicide_incident()`）；债务困境（`borrow_to_repay()`/`restructure()`/`personal_bankruptcy()`（时代门控））；边界（`abscond()`/`predatory_loan()`/`illegal_fundraising()`）；`典当 <物品> [金额]`/`赎回`/`借贷 <业务> [金额]`/`放贷 <业务> [金额]`/`信用评估`/`合法催收`/`暴力催收`/`债务重组`/`个人破产`/`套路贷 [虚增]`/`非法集资 [金额]`/`跑路` 指令经 `SimHost.debt_pawn()` 等结算；运行时随 `GameState.sim_runtime.debt`（`lender`/`loan`/`lend`/`pawns`）持久化；「债务与催收」面板渲染负债概览/我的借款/我放出的贷款/放贷人/典当物分区（入口「看债务」）。

## 面板与表现层

- **45 个面板**全部接入内容装配（`ui/panels/panel_content.gd`）：核心面板直接读玩家字典；
  领域面板经 `context` 读取 `world_delta`/`macro`/`epidemic`/`weather`，数据缺失时给引导性空态。
- **3D 表现层**：`place_bindings.gd` 把 13 个场所分组映射到场景；`presentation/scenes/placeholder_place.tscn`
  按分组程序化生成差异化灰盒（`PlaceholderAssets.GROUP_STYLES`）。真实资产放入
  `presentation/scenes/places/<group>.tscn` 即自动替换，零改代码（见 `assets/README.md`）。

## 测试

```bash
# 运行全部客户端测试（含跨语言一致性）
/workspace/.toolchain/godot --headless --path client --script res://tests/consistency_test.gd

# 单套件
/workspace/.toolchain/godot --headless --path client --script res://tests/intent_executor_test.gd
```

共享数值规格见 `shared/consistency/`；两端一致性由 `scripts/test.sh` 统一运行。
