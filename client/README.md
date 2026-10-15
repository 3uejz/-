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
ui/         主界面壳（main.tscn）与面板（注册表 44 面板）、面板内容装配（panel_content.gd）
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

## 面板与表现层

- **44 个面板**全部接入内容装配（`ui/panels/panel_content.gd`）：核心面板直接读玩家字典；
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
