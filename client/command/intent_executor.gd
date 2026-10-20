class_name IntentExecutor
extends RefCounted
## 指令意图执行器：把 CommandIntent 落到 SimHost 与 GameState，产出叙事与面板指令。
## 纯逻辑、确定性、headless 可测；UI 只负责把返回的 narration/panel 呈现出来。
##
## 返回统一为 {ok, narration:[String], minutes:int, panel:String, action:String, error:String}。
## action 供 UI 层执行非模拟动作：save / load / pause / speed / restart（其余为空）。

const MINUTE: int = 1
const HOUR: int = 60
const DAY: int = 1440
const WEEK: int = 10080
const MONTH: int = 43200
const YEAR: int = 525600

const FlavorScript = preload("res://sim/flavor.gd")
const VerbRegistryScript = preload("res://command/verb_registry.gd")

var host                        # SimHost
var panels: Array = []          # 本次执行请求打开的面板 id（复合指令取最后一个）

func _init(sim_host) -> void:
	host = sim_host

# --- 对外入口 ---

func execute(intent) -> Dictionary:
	panels.clear()
	if intent == null:
		return _fail("无指令")
	if not intent.ok and String(intent.verb).is_empty():
		return _fail(intent.error if String(intent.error) != "" else "无法执行该指令")
	if String(intent.verb) == "然后":
		return _compound(intent)
	if host.military_restricts(String(intent.verb)):
		return _fail("服役期间不得执行「%s」；可先退伍。" % String(intent.verb))
	var result: Dictionary = _dispatch(intent)
	if not panels.is_empty():
		result["panel"] = panels.back()
	return result

# --- 复合指令 ---

func _compound(intent) -> Dictionary:
	var lines: Array = []
	var total := 0
	for part in intent.parts:
		var r: Dictionary = execute(part)
		if not bool(r["ok"]):
			return r
		lines.append_array(r["narration"])
		total += int(r["minutes"])
	var panel := ""
	if not panels.is_empty():
		panel = panels.back()
	return _ok(lines, total, panel)

# --- 动词分派 ---

func _dispatch(intent) -> Dictionary:
	match String(intent.verb):
		"帮助", "查看":
			return _help()
		# 时间推进
		"等待", "快进":
			return _wait(intent)
		"睡":
			return _sleep(intent)
		"锻炼":
			return _exercise(intent)
		"工作":
			return _work(intent)
		"学习":
			return _study(intent)
		# 生理与物品
		"吃", "喝":
			return _eat(intent)
		"买":
			return _buy(intent)
		"卖":
			return _sell(intent)
		# 金融
		"存钱":
			return _deposit(intent)
		"取钱":
			return _withdraw(intent)
		"贷款":
			return _bank_loan(intent)
		"还款":
			return _bank_repay(intent)
		"买股票":
			return _security_buy(intent)
		"卖股票":
			return _security_sell(intent)
		"买彩票":
			return _lottery(intent)
		"纳税":
			return _pay_tax(intent)
		# 职业
		"求职", "面试":
			return _job_apply(intent)
		"辞职":
			return _job_resign(intent)
		# 军旅与职场（D7）
		"参军":
			return _military_enlist(intent)
		"军训":
			return _military_train(intent)
		"军务任务":
			return _military_mission(intent)
		"军衔晋升":
			return _military_promote(intent)
		"退伍":
			return _military_discharge(intent)
		"逃兵":
			return _military_desert(intent)
		"办公室政治":
			return _workplace_politics(intent)
		"站队":
			return _workplace_join(intent)
		"骑墙":
			return _workplace_neutral(intent)
		"自组派系":
			return _workplace_found(intent)
		"职场晋升":
			return _workplace_promote(intent)
		# 公司与融资（D7）
		"注册公司":
			return _company_register(intent)
		"公司选址":
			return _company_site(intent)
		"开业":
			return _company_open(intent)
		"打烊":
			return _company_close(intent)
		"进货":
			return _company_stock(intent)
		"定价":
			return _company_price(intent)
		"雇人":
			return _company_hire(intent)
		"扩张":
			return _company_expand(intent)
		"公司纳税":
			return _company_tax(intent)
		"公司融资":
			return _company_finance(intent)
		"融资对赌":
			return _company_vam(intent)
		"公司退出":
			return _company_exit(intent)
		# 社交
		"聊天":
			return _interact(intent, "chat")
		"送礼":
			return _interact(intent, "gift")
		"约会":
			return _interact(intent, "dine")
		"表白":
			return _confess(intent)
		"求婚":
			return _propose(intent)
		"离婚":
			return _divorce(intent)
		"怀孕":
			return _conceive(intent)
		"立遗嘱":
			return _write_will(intent)
		"看房":
			return _list_homes(intent)
		"买房":
			return _buy_home(intent)
		"卖房":
			return _sell_home(intent)
		"出租":
			return _rent_home(intent)
		"领养":
			return _adopt_pet(intent)
		"喂养":
			return _feed_pets(intent)
		"训练宠物":
			return _train_pets(intent)
		"发动态":
			return _social_publish(intent)
		"看动态":
			return _social_feed(intent)
		"收养":
			return _adopt_child(intent)
		"指定监护人":
			return _assign_guardian(intent)
		# 心理与精神健康
		"心理咨询":
			return _mental_treat(intent, "psychotherapy")
		"心理治疗":
			return _mental_treat(intent, "cbt")
		"精神科用药":
			return _mental_treat(intent, "medication")
		"重症干预":
			return _mental_treat(intent, "crisis_intervention")
		"放松":
			return _relax(intent)
		# 形象与医美（D6）
		"形象护理":
			return _appearance_care(intent)
		"医美":
			return _aesthetic_perform(intent)
		"医美维权":
			return _aesthetic_claim(intent)
		"证件核验":
			return _appearance_verify(intent)
		"重办证件":
			return _appearance_reissue(intent)
		# 精神追求与信仰（D15）
		"修持":
			return _pursue_spirit(intent)
		"皈依":
			return _convert_faith(intent)
		"深化信仰":
			return _deepen_faith(intent)
		"化解危机":
			return _resolve_crisis(intent)
		# 组织与社团（D19）
		"加入组织":
			return _join_org(intent)
		"退出组织":
			return _leave_org(intent)
		"缴会费":
			return _pay_org_dues(intent)
		"组织任务":
			return _org_task(intent)
		"罢工":
			return _org_action(intent, "strike")
		"请愿":
			return _org_action(intent, "petition")
		"募捐":
			return _org_action(intent, "fundraiser")
		"游行":
			return _org_action(intent, "march")
		"抵制":
			return _org_action(intent, "boycott")
		# 语言与文化（D20）
		"学语言":
			return _study_language(intent)
		"沉浸":
			return _immerse_language(intent)
		"语言考试":
			return _language_exam(intent)
		"适应文化":
			return _adapt_culture(intent)
		# 残障与养老（D21）
		"装辅具":
			return _fit_device(intent)
		"康复训练":
			return _rehab(intent)
		"无障碍改造":
			return _accessible_retrofit(intent)
		"选养老":
			return _choose_care_mode(intent)
		"临终关怀":
			return _hospice(intent)
		"指定监护":
			return _guardianship(intent)
		# 农业与乡土（D22）
		"承包土地":
			return _acquire_land(intent)
		"播种":
			return _sow(intent)
		"收割":
			return _harvest_crop(intent)
		"养畜":
			return _raise_livestock(intent)
		"卖粮":
			return _sell_produce(intent)
		"农业补贴":
			return _farm_subsidy(intent)
		# 数字生活与黑客（D23）
		"开账号":
			return _open_account(intent)
		"实名认证":
			return _verify_identity(intent)
		"网络兼职":
			return _security_work(intent)
		"发布内容":
			return _publish_content(intent)
		"黑客攻击":
			return _hack_target(intent)
		# 后期科技（D24）
		"解锁科技":
			return _unlock_tech(intent)
		"应聘科技职业":
			return _apply_tech_career(intent)
		"科技任务":
			return _tech_mission(intent)
		"生物延寿":
			return _biotech(intent)
		"自动化评估":
			return _late_tech_automation(intent)
		"极端环境":
			return _late_tech_environment(intent)
		"气候难民":
			return _late_tech_climate(intent)
		"AI伦理事件":
			return _late_tech_ai(intent)
		# 知识产权与媒体（D25）
		"登记知识产权":
			return _register_ip(intent)
		"职务发明":
			return _company_file_ip(intent)
		"知识产权授权":
			return _license_ip(intent)
		"知识产权转让":
			return _transfer_ip(intent)
		"知识产权质押":
			return _pledge_ip(intent)
		"知识产权维权":
			return _sue_ip(intent)
		"开办媒体":
			return _open_media(intent)
		"内容审核":
			return _audit_content(intent)
		"发行作品":
			return _release_work(intent)
		# 制造业与供应链（D26）
		"开办工厂":
			return _found_factory(intent)
		"招工":
			return _mfg_hire(intent)
		"采购原料":
			return _mfg_purchase(intent)
		"生产":
			return _mfg_produce(intent)
		"接单":
			return _mfg_order(intent)
		"交付订单":
			return _mfg_deliver(intent)
		"成品出口":
			return _mfg_export(intent)
		"改进经营模式":
			return _mfg_mode(intent)
		# 国际贸易、海关与物流（D27）
		"出口":
			return _export_shipment(intent)
		"规划运输":
			return _plan_transport(intent)
		"签订外贸合同":
			return _sign_trade(intent)
		"报关":
			return _declare_shipment(intent)
		"清关":
			return _clear_shipment(intent)
		"外贸交付":
			return _deliver_shipment(intent)
		"结汇":
			return _settle_shipment(intent)
		"贸易壁垒":
			return _trade_barrier(intent)
		"外贸风险":
			return _trade_risk(intent)
		"检验检疫":
			return _trade_inspect(intent)
		"货损":
			return _trade_damage(intent)
		"退运":
			return _trade_return(intent)
		# 矿业、能源与资源（D28）
		"开矿":
			return _open_mine(intent)
		"取得矿权":
			return _acquire_mine_concession(intent)
		"勘探":
			return _explore_mine(intent)
		"开采":
			return _extract_ore(intent)
		"冶炼":
			return _smelt_ore(intent)
		"卖矿":
			return _sell_metal(intent)
		"建能源项目":
			return _build_energy_project(intent)
		"资源衰退":
			return _mining_city_decline(intent)
		"战略管制":
			return _mining_strategic_control(intent)
		"资源囤积":
			return _mining_stockpile(intent)
		"安全投入":
			return _mine_safety(intent)
		"矿难":
			return _mine_accident(intent)
		"能源期货":
			return _energy_futures(intent)
		"期货结算":
			return _energy_settle(intent)
		"能源长约":
			return _energy_contract(intent)
		# 农林牧渔深化（D29）
		"建渔场":
			return _new_fishery(intent)
		"捕鱼":
			return _fish_catch(intent)
		"休渔":
			return _start_closed_season(intent)
		"承包林场":
			return _new_forest(intent)
		"采伐":
			return _log_trees(intent)
		"造林":
			return _reforest(intent)
		"林业碳汇":
			return _forest_carbon(intent)
		"申请狩猎许可":
			return _apply_hunting_license(intent)
		"狩猎":
			return _hunt(intent)
		# 餐饮与食品工业（D30）
		"建餐厅":
			return _build_restaurant(intent)
		"加菜":
			return _add_menu(intent)
		"定菜价":
			return _set_menu_price(intent)
		"营业":
			return _open_business(intent)
		"雇厨":
			return _hire_chef(intent)
		"扩张餐饮":
			return _expand_dining(intent)
		"食品认证":
			return _certify_food(intent)
		"营销推广":
			return _promote_food(intent)
		"加工食品":
			return _process_food(intent)
		"分销食品":
			return _distribute_food(intent)
		"产线供餐":
			return _supply_from_factory(intent)
		# 时尚、设计与奢侈品（D31）
		"建品牌":
			return _new_brand(intent)
		"创作设计":
			return _fashion_design(intent)
		"时装周":
			return _fashion_week(intent)
		"联名":
			return _fashion_collab(intent)
		"限量发售":
			return _fashion_limited(intent)
		"设计师营销":
			return _fashion_marketing(intent)
		"品牌复兴":
			return _fashion_renew(intent)
		"二手寄售":
			return _fashion_resell(intent)
		"奢侈品拍卖":
			return _fashion_auction(intent)
		"品牌传承":
			return _fashion_inherit(intent)
		"仿品侵权":
			return _fashion_counterfeit(intent)
		"鉴定真伪":
			return _fashion_authenticate(intent)
		"开启球涯":
			return _start_sports_career(intent)
		"比赛":
			return _sports_match(intent)
		"转会":
			return _sports_transfer(intent)
		"代言合同":
			return _sports_sponsorship(intent)
		"运动康复":
			return _sports_rehab(intent)
		"兴奋剂检测":
			return _sports_doping_test(intent)
		"退役":
			return _sports_retire(intent)
		"国家队征召":
			return _sports_national(intent)
		"国家队集训":
			return _sports_national_camp(intent)
		"国际赛事":
			return _sports_tournament(intent)
		"球迷冲突":
			return _sports_fans(intent)
		"裁判争议":
			return _sports_referee(intent)
		"学业冲突":
			return _sports_academic(intent)
		"活动策划":
			return _start_event_career(intent)
		"办活动":
			return _events_new(intent)
		"租场地":
			return _events_rent_venue(intent)
		"报批":
			return _events_approval(intent)
		"拉赞助":
			return _events_sponsor(intent)
		"售票":
			return _events_sell(intent)
		"布置安保":
			return _events_security(intent)
		"二级市场":
			return _events_secondary(intent)
		"举办活动":
			return _events_hold(intent)
		"活动复盘":
			return _events_review(intent)
		"签约艺人":
			return _events_sign_artist(intent)
		"艺人排期":
			return _events_book_artist(intent)
		"荣誉档案":
			return _honor_profile(intent)
		"提名":
			return _honor_nominate(intent)
		"评审":
			return _honor_evaluate(intent)
		"领奖":
			return _honor_award(intent)
		"评审团投票":
			return _honor_panel_vote(intent)
		"舆论施压":
			return _honor_pressure(intent)
		"买奖":
			return _honor_buy(intent)
		"揭露黑幕":
			return _honor_expose(intent)
		"家族荣誉":
			return _honors_family_legacy(intent)
		"立案":
			return _police_case(intent)
		"勘查":
			return _police_survey(intent)
		"取证":
			return _police_collect(intent)
		"搜查令":
			return _police_warrant(intent)
		"审讯":
			return _police_interrogate(intent)
		"线人":
			return _police_informant(intent)
		"卧底":
			return _police_undercover(intent)
		"技侦":
			return _police_tech(intent)
		"侦破":
			return _police_advance(intent)
		"开安保公司":
			return _security_firm(intent)
		"承接安保":
			return _security_take(intent)
		"履约安保":
			return _security_resolve(intent)
		"接警":
			return _emergency_new(intent)
		"天气灾害":
			return _emergency_weather(intent)
		"出警":
			return _emergency_dispatch(intent)
		"跨区增援":
			return _emergency_mutual_aid(intent)
		"现场救援":
			return _emergency_rescue(intent)
		"二次事故":
			return _emergency_secondary(intent)
		"善后处理":
			return _emergency_aftermath(intent)
		"开志愿队":
			return _volunteer_org(intent)
		"采购救援装备":
			return _volunteer_purchase(intent)
		"招募志愿者":
			return _volunteer_recruit(intent)
		"志愿出警":
			return _volunteer_dispatch(intent)
		"装备维护":
			return _volunteer_maintain(intent)
		"垃圾分类":
			return _env_garbage(intent)
		"回收":
			return _env_recycle(intent)
		"污水处理":
			return _env_sewage(intent)
		"空气治理":
			return _env_air(intent)
		"排污许可":
			return _env_permit(intent)
		"碳核算":
			return _env_carbon_account(intent)
		"碳交易":
			return _env_carbon_trade(intent)
		"碳拍卖":
			return _env_carbon_auction(intent)
		"碳撮合":
			return _env_carbon_market(intent)
		"碳履约":
			return _env_carbon_compliance(intent)
		"碳申报":
			return _env_carbon_report(intent)
		"开环保公司":
			return _env_org(intent)
		"承接环保项目":
			return _env_project(intent)
		"举报污染":
			return _env_expose(intent)
		"环境诉讼":
			return _env_lawsuit(intent)
		"申请绿色补贴":
			return _env_subsidy(intent)
		"低碳转型":
			return _env_transition(intent)
		"偷排":
			return _env_discharge(intent)
		"邻避评估":
			return _env_nimby(intent)
		"市政养护":
			return _municipal_maintain(intent)
		"设施巡检":
			return _municipal_inspect(intent)
		"市政施工":
			return _municipal_construct(intent)
		"施工推进":
			return _municipal_advance(intent)
		"道路开挖":
			return _municipal_excavate(intent)
		"市政投诉":
			return _municipal_complain(intent)
		"投诉处理":
			return _municipal_resolve(intent)
		"邮政寄件":
			return _postal_accept(intent)
		"包裹发运":
			return _postal_ship(intent)
		"包裹理赔":
			return _postal_claim(intent)
		"快递生涯":
			return _courier_career(intent)
		"揽投":
			return _courier_deliver(intent)
		"特许经营":
			return _municipal_franchise(intent)
		"服务考核":
			return _municipal_quality(intent)
		"公用事业报表":
			return _municipal_utility(intent)
		"政府购买":
			return _municipal_purchase(intent)
		"项目招标":
			return _municipal_tender(intent)
		"项目听证":
			return _municipal_hearing(intent)
		"典当":
			return _debt_pawn(intent)
		"赎回":
			return _debt_redeem(intent)
		"借贷":
			return _debt_borrow(intent)
		"放贷":
			return _debt_lend(intent)
		"信用评估":
			return _debt_credit(intent)
		"贷款台账":
			return _debt_ledger(intent)
		"征信报告":
			return _debt_credit_report(intent)
		"还贷款":
			return _debt_repay(intent)
		"合法催收":
			return _debt_collect_legal(intent)
		"暴力催收":
			return _debt_collect_violence(intent)
		"债务重组":
			return _debt_restructure(intent)
		"个人破产":
			return _debt_bankruptcy(intent)
		"套路贷":
			return _debt_predatory(intent)
		"非法集资":
			return _debt_fundraise(intent)
		"跑路":
			return _debt_abscond(intent)
		"消费订单":
			return _consumer_order(intent)
		"商品退换":
			return _consumer_return(intent)
		"三包退换":
			return _consumer_three(intent)
		"商品保修":
			return _consumer_warranty(intent)
		"消费举证":
			return _consumer_burden(intent)
		"消费协商":
			return _consumer_dispute_negotiate(intent)
		"平台投诉":
			return _consumer_platform(intent)
		"消协调解":
			return _consumer_association(intent)
		"热线投诉":
			return _consumer_hotline(intent)
		"集体维权":
			return _consumer_class_action(intent)
		"消费起诉":
			return _consumer_sue(intent)
		"民事开庭":
			return _civil_litigate(intent)
		"民事上诉":
			return _civil_appeal(intent)
		"民事执行":
			return _civil_enforce(intent)
		"实施犯罪":
			return _crime_attempt(intent)
		"刑事受审":
			return _crime_trial(intent)
		"自首":
			return _crime_surrender(intent)
		"刑事上诉":
			return _crime_appeal(intent)
		"潜逃":
			return _crime_flee(intent)
		"化名":
			return _crime_alias(intent)
		"司法行贿":
			return _crime_bribe(intent)
		"监狱劳动":
			return _prison_labor(intent)
		"监狱探视":
			return _prison_visit(intent)
		"狱友交流":
			return _prison_interact(intent)
		"加入狱帮":
			return _prison_gang(intent)
		"监狱违纪":
			return _prison_violation(intent)
		"减刑":
			return _prison_reduce(intent)
		"假释":
			return _prison_parole(intent)
		"越狱":
			return _prison_escape(intent)
		"出狱融入":
			return _prison_reintegrate(intent)
		"质量事故":
			return _consumer_incident_quality(intent)
		"食安事故":
			return _consumer_incident_food(intent)
		"商品召回":
			return _consumer_recall(intent)
		"职业打假":
			return _consumer_fraud(intent)
		"恶意索赔":
			return _consumer_malicious(intent)
		"收养评估":
			return _welfare_apply(intent, "adoption")
		"寄养申请":
			return _welfare_apply(intent, "foster")
		"收养生效":
			return _welfare_finalize(intent)
		"撤销收养":
			return _welfare_revoke_adoption(intent)
		"低保申请":
			return _welfare_apply(intent, "dibao")
		"医疗救助":
			return _welfare_apply(intent, "medical_aid")
		"临时救助":
			return _welfare_apply(intent, "temporary_aid")
		"流浪救助":
			return _welfare_apply(intent, "homeless_relief")
		"救助发放":
			return _welfare_disburse(intent)
		"家庭变故":
			return _welfare_crisis(intent)
		"慈善基金":
			return _welfare_fund_new(intent)
		"慈善捐赠":
			return _welfare_donate(intent)
		"公益支出":
			return _welfare_spend(intent)
		"慈善公示":
			return _welfare_publish(intent)
		"善款审计":
			return _welfare_audit(intent)
		"善款挪用":
			return _welfare_misappropriate(intent)
		"社工入职":
			return _welfare_worker(intent)
		"个案跟进":
			return _welfare_follow_up(intent)
		"个案结案":
			return _welfare_close_case(intent)
		"虐待举报":
			return _welfare_abuse(intent)
		"救助依赖":
			return _welfare_dependency(intent)
		"资格互认":
			return _welfare_recognize(intent)
		"殡葬安排":
			return _funeral_arrange(intent)
		"殡葬执行":
			return _funeral_execute(intent)
		"器官捐献":
			return _funeral_donation(intent)
		"伦理审查":
			return _funeral_ethics(intent)
		"撤销捐献":
			return _funeral_revoke(intent)
		"器官分配":
			return _funeral_allocate(intent)
		"器官移植":
			return _funeral_transplant(intent)
		"立纪念碑":
			return _funeral_memorial(intent)
		"祭扫":
			return _funeral_sweep(intent)
		"数字纪念":
			return _funeral_digital(intent)
		"数字纪念平台":
			return _funeral_digital_platform(intent)
		"遗嘱执行":
			return _funeral_will(intent)
		"开殡仪馆":
			return _funeral_home(intent)
		"殡葬报价":
			return _funeral_quote(intent)
		"殡葬成交":
			return _funeral_sale(intent)
		"殡葬监管":
			return _funeral_regulate(intent)
		"殡葬改革":
			return _funeral_reform(intent)
		"无人认领":
			return _funeral_unclaimed(intent)
		"捐献争议":
			return _funeral_dispute(intent)
		"玄学咨询":
			return _meta_consult(intent)
		"民俗仪式":
			return _meta_folk(intent)
		"开玄学馆":
			return _meta_business(intent)
		"玄学营业":
			return _meta_operate(intent)
		"玄学投诉":
			return _meta_complaint(intent)
		"诈骗查处":
			return _meta_investigate(intent)
		"人设翻车":
			return _meta_fall(intent)
		"组织迷信":
			return _meta_superstition(intent)
		"勾结灰产":
			return _meta_collude(intent)
		"真假难辨":
			return _meta_blur(intent)
		"开启门闩":
			return _anomaly_open_gate(intent)
		"天赋觉醒":
			return _anomaly_rare_talent(intent)
		"查阅条目":
			return _anomaly_encounter(intent)
		"使用能力":
			return _anomaly_use_ability(intent)
		"权限晋升":
			return _anomaly_clearance(intent)
		"加入阵营":
			return _anomaly_join_faction(intent)
		"接受任务":
			return _anomaly_accept_mission(intent)
		"完成任务":
			return _anomaly_complete_mission(intent)
		"服用记忆删除":
			return _anomaly_amnestics(intent)
		"认知对抗":
			return _anomaly_combat(intent)
		"收容失效":
			return _anomaly_breach(intent)
		"身份设定":
			return _anomaly_identity(intent)
		"就医挂号":
			return _medical_register(intent)
		"医学检查":
			return _medical_examine(intent)
		"疾病治疗":
			return _medical_treat(intent)
		"就医手术":
			return _medical_surgery(intent)
		"高阶医疗":
			return _medical_high_end(intent)
		"医疗伦理":
			return _medical_ethics(intent)
		"医药立项":
			return _pharma_start(intent)
		"医药推进":
			return _pharma_advance(intent)
		"医药生产":
			return _pharma_produce(intent)
		"医药销售":
			return _pharma_sell(intent)
		"医药代表":
			return _pharma_rep(intent)
		"假药查缉":
			return _medical_counterfeit(intent)
		"医疗纠纷":
			return _medical_dispute(intent)
		"过度医疗":
			return _medical_over(intent)
		"医疗保险欺诈":
			return _medical_fraud(intent)
		"用药疗程":
			return _medical_drug_course(intent)
		"试验丑闻":
			return _medical_scandal(intent)
		"开工作室":
			return _content_new_studio(intent)
		"招募团队":
			return _content_hire(intent)
		"裁撤团队":
			return _content_fire(intent)
		"立项作品":
			return _content_new_work(intent)
		"项目管理":
			return _content_manage(intent)
		"推进创作":
			return _content_advance(intent)
		"作品发行":
			return _content_release(intent)
		"渠道分成":
			return _content_monetize(intent)
		"作品版权":
			return _content_register_ip(intent)
		"IP改编":
			return _content_adapt(intent)
		"IP运营":
			return _content_operate(intent)
		"IP宇宙":
			return _content_ip_universe(intent)
		"查重抄袭":
			return _content_plagiarism(intent)
		"内容审查":
			return _content_compliance(intent)
		"作品下架":
			return _content_takedown(intent)
		"艺人翻车":
			return _content_scandal(intent)
		"工作室融资":
			return _content_funding(intent)
		"挖角团队":
			return _content_poach(intent)
		"版号审批":
			return _content_approval(intent)
		"粉丝运营":
			return _content_fandom(intent)
		"科研立项":
			return _research_start(intent)
		"科研推进":
			return _research_advance(intent)
		"科研成果":
			return _research_collect(intent)
		"科研专利":
			return _research_patent(intent)
		"科研经费":
			return _research_fund(intent)
		"办工程公司":
			return _eng_new_contractor(intent)
		"承接工程":
			return _eng_take_project(intent)
		"工程推进":
			return _eng_advance(intent)
		"工程监理":
			return _eng_supervise(intent)
		"工程招标":
			return _eng_tender(intent)
		"围标":
			return _eng_rig(intent)
		"招标行贿":
			return _eng_bribe(intent)
		"偷工减料":
			return _eng_cut_corners(intent)
		"工程事故":
			return _eng_accident(intent)
		"拖欠工程款":
			return _eng_arrears(intent)
		"三角债":
			return _eng_debt_chain(intent)
		"规划新城":
			return _eng_new_city(intent)
		"变更用地":
			return _eng_rezone(intent)
		"城建交通":
			return _eng_transport(intent)
		"规划腐败":
			return _eng_planning_corruption(intent)
		"房屋拆迁":
			return _eng_demolition(intent)
		"办地产公司":
			return _eng_new_developer(intent)
		"楼盘预售":
			return _eng_pre_sale(intent)
		"楼盘施工":
			return _eng_develop(intent)
		"楼盘烂尾":
			return _eng_unfinished(intent)
		"开事务所":
			return _prof_new_firm(intent)
		"考执业资质":
			return _prof_acquire(intent)
		"开发客户":
			return _prof_client(intent)
		"立项项目":
			return _prof_new_project(intent)
		"尽职调查":
			return _prof_due_diligence(intent)
		"并购顾问":
			return _prof_ma(intent)
		"独立性审查":
			return _prof_independence(intent)
		"虚假报告":
			return _prof_false_report(intent)
		"内幕交易":
			return _prof_insider(intent)
		"商业贿赂":
			return _prof_bribery(intent)
		"吸收合伙人":
			return _prof_add_partner(intent)
		"合伙人分裂":
			return _prof_split(intent)
		"竞业限制":
			return _prof_non_compete(intent)
		"客户流失":
			return _prof_churn(intent)
		"注册服务者":
			return _life_new_provider(intent)
		"背景核查":
			return _life_background(intent)
		"预约服务":
			return _life_new_order(intent)
		"相亲婚介":
			return _life_matchmaking(intent)
		"婚礼策划":
			return _life_wedding(intent)
		"家政保洁":
			return _life_housekeeping(intent)
		"月嫂照料":
			return _life_maternity(intent)
		"宠物寄养":
			return _life_pet(intent)
		"服务事故":
			return _life_incident(intent)
		"纠纷处理":
			return _life_dispute(intent)
		"平台抽成":
			return _life_commission(intent)
		"服务标准化":
			return _life_standardize(intent)
		"基建立项":
			return _tin_new_project(intent)
		"基建招标":
			return _tin_tender(intent)
		"基建推进":
			return _tin_build(intent)
		"线路运营":
			return _tin_operate(intent)
		"区域影响":
			return _tin_regional(intent)
		"路网效应":
			return _tin_network(intent)
		"线路补贴":
			return _tin_subsidy(intent)
		"基建结算":
			return _tin_settle(intent)
		"基建事故":
			return _tin_accident(intent)
		"定价监管":
			return _tin_monopoly(intent)
		"国际扰动":
			return _tin_disruption(intent)
		# 元指令（交 UI 处理）
		"存档":
			return _action("save", "已请求存档。")
		"读档":
			return _action("load", "已请求读档。")
		"暂停":
			return _action("pause", "已请求暂停。")
		"加速":
			return _action("speed", "已请求调整倍速。")
		"重开":
			return _action("restart", "已请求重开新的一生。")
		_:
			# 面板查询：任意登记的面板动词「看 X」→ 打开对应面板。
			var pid := String(VerbRegistryScript.PANEL_VERBS.get(String(intent.verb), ""))
			if pid != "":
				return _panel(pid, "打开面板：%s。" % String(intent.verb))
			return _stub(String(intent.verb))

# --- 处理器 ---

func _help() -> Dictionary:
	var lines: Array = [
		"可用指令示例：",
		"· 面板：看自己 / 看技能 / 看背包 / 看关系 / 看地图 / 看资产 / 看医疗 / 看心理 / 看精神 / 看语言 / 看养老 / 看行情 / 看天气 …（全部 45 个面板）",
		"· 时间：等待 1 小时 / 睡 8 小时 / 工作 4 小时 / 学习 <技能> 2 小时 / 锻炼 1 小时",
		"· 生活：吃 <食物> / 买 <物品> 2 / 卖 <物品> / 存钱 500 元 / 取钱 200 元",
		"· 社交：聊天 <人物> / 送礼 <人物> / 约会 <人物> / 求职 <岗位>",
		"· 组织：加入组织 <组织> / 缴会费 / 组织任务 / 罢工 / 请愿 / 募捐 / 退出组织",
		"· 语言：学语言 <语言> [时长] / 沉浸 <语言> [天数] / 语言考试 <语言> / 适应文化 <文化>",
		"· 残障与养老：装辅具 <辅具> / 康复训练 / 无障碍改造 / 选养老 <模式> / 临终关怀 / 指定监护 <监护人>",
		"· 农业与乡土：承包土地 [面积] / 播种 <作物> / 收割 / 养畜 <牲畜> / 卖粮 <作物> / 农业补贴",
		"· 数字与平台：开账号 <平台> / 实名认证 / 网络兼职 <类型> / 发布内容 [平台] / 黑客攻击 <目标>",
		"· 后期科技：解锁科技 / 应聘科技职业 <职业> / 科技任务 <任务> / 生物延寿 [投入]",
		"· 知识产权与媒体：登记知识产权 <类型> / 知识产权授权 <IP> [规模] / 知识产权转让 <IP> [价格] / 知识产权质押 <IP> [金额] / 知识产权维权 <IP> / 开办媒体 <类型> / 发行作品 <标题>",
		"· 制造业与供应链：开办工厂 [模式] / 招工 <岗位> [人数] / 采购原料 <原料> [数量] / 生产 <配方> [批次] / 接单 <配方> [数量] / 交付订单 [序号] / 改进经营模式 <模式>",
		"· 国际贸易与物流：出口 <商品> [货值] / 规划运输 <方式> / 签订外贸合同 <术语> / 报关 / 清关 / 外贸交付 / 结汇",
	]
	return _ok(lines, 0, "")

func _wait(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, HOUR)
	return _advance_time(minutes, {}, "wait")

func _sleep(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, 8 * HOUR)
	return _advance_time(minutes, {"asleep": true}, "sleep")

func _exercise(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, HOUR)
	var r: Dictionary = _advance_time(minutes, {"labor_intensity": 0.6}, "exercise")
	# 若指定了技能，一并计入练习；否则尝试体质类技能。
	var sid := _object_id(intent, "skill")
	if sid.is_empty():
		sid = _first_known_skill(["skill.physique", "skill.strength", "skill.sports", "skill.fitness"])
	var lines: Array = r["narration"]
	if not sid.is_empty() and host.skills.has_def(sid):
		var pr: Dictionary = _practice(sid, float(minutes) / 60.0)
		if bool(pr.get("ok", false)):
			lines.append("锻炼了 %s，等级 %d。" % [_skill_name(sid), int(pr.get("level", 0))])
	return _ok(lines, minutes, "")

func _work(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, 8 * HOUR)
	if not host.jobs.is_employed(host.player()):
		return _fail("你目前没有工作，先「求职」。")
	var r: Dictionary = host.jobs.work(host.player(), float(minutes))
	if not bool(r.get("ok", false)):
		return _fail("无法工作：%s" % String(r.get("reason", "")))
	# work() 已扣体力与心情，这里只推进剩余代谢时间，避免重复扣减。
	var adv: Dictionary = _advance_time(minutes, {}, "work")
	var lines: Array = adv["narration"]
	lines.append("工作 %s，绩效 %.0f。" % [_duration_text(minutes), float(r.get("performance", 0.0))])
	return _ok(lines, minutes, "")

func _study(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, 2 * HOUR)
	var sid := _object_id(intent, "skill")
	if sid.is_empty():
		return _fail("请指定要学习的技能。")
	if not host.skills.has_def(sid):
		return _fail("未知技能「%s」。" % sid)
	var r: Dictionary = _practice(sid, float(minutes) / 60.0)
	if not bool(r.get("ok", false)):
		return _fail("无法学习 %s：%s" % [_skill_name(sid), String(r.get("reason", ""))])
	var adv: Dictionary = _advance_time(minutes, {}, "study")
	var lines: Array = adv["narration"]
	lines.append("学习了 %s %s，当前等级 %d。" % [_skill_name(sid), _duration_text(minutes), int(r.get("level", 0))])
	if int(r.get("level_up", 0)) > 0:
		lines.append("技能提升！")
	return _ok(lines, minutes, "")

func _eat(intent) -> Dictionary:
	var item_id := _object_id(intent, "item")
	if not item_id.is_empty():
		if not host.items.has_def(item_id):
			return _fail("未知物品「%s」。" % item_id)
		var d: Dictionary = host.items.get_def(item_id)
		var cat := String(d.get("category", ""))
		if cat != "food" and cat != "medicine":
			return _fail("「%s」不能吃/喝。" % _item_name(item_id))
		var res: Dictionary = host.items.use(host.player(), item_id)
		if not bool(res.get("ok", false)):
			return _fail("无法食用：%s。" % String(res.get("reason", "")))
		host.sync_finances()
		return _ok(["你用了 %s。" % _item_name(item_id)], 0, "")
	# 无具体物品：一餐概况，直接补充饱食与营养。
	var food := {"protein": 10.0, "carbs": 24.0, "fat": 7.0, "vitamins": 6.0, "minerals": 4.0, "satiety": 38.0}
	var r: Dictionary = host.survival.eat(host.player(), food)
	if not bool(r.get("applied", false)):
		return _fail("无法进食。")
	host.sync_finances()
	return _ok([FlavorScript.time_line("eat", host.now_minutes()),
		"你吃了一餐，饱食度 +%.0f。" % float(r.get("satiety_added", 0.0))], 0, "")

func _buy(intent) -> Dictionary:
	var item_id := _object_id(intent, "item")
	if item_id.is_empty():
		return _fail("请指定要购买的物品。")
	if not host.items.has_def(item_id):
		return _fail("未知物品「%s」。" % item_id)
	var qty := _quantity(intent)
	var r: Dictionary = host.items.buy(host.player(), host.economy, host.account_id(), item_id, qty, null, "", "market", host.region_price_index())
	if not bool(r.get("ok", false)):
		return _fail("购买失败：%s。" % String(r.get("reason", "")))
	host.sync_finances()
	var cost := float(r.get("cost_minor", 0)) / 100.0
	return _ok([FlavorScript.time_line("buy", host.now_minutes()),
		"你买了 %s×%d，花费 %.0f 元。" % [_item_name(item_id), qty, cost]], 0, "")

func _sell(intent) -> Dictionary:
	var item_id := _object_id(intent, "item")
	if item_id.is_empty():
		return _fail("请指定要出售的物品。")
	var qty := _quantity(intent)
	var r: Dictionary = host.items.sell(host.player(), host.economy, host.account_id(), item_id, qty, null, "", "market", 0.6, host.region_price_index())
	if not bool(r.get("ok", false)):
		return _fail("出售失败：%s。" % String(r.get("reason", "")))
	host.sync_finances()
	var proceeds := float(r.get("proceeds_minor", 0)) / 100.0
	return _ok([FlavorScript.time_line("sell", host.now_minutes()),
		"你卖出 %s×%d，得到 %.0f 元。" % [_item_name(item_id), qty, proceeds]], 0, "")

func _deposit(intent) -> Dictionary:
	var minor := _amount_minor(intent)
	var acct: String = host.account_id()
	if minor <= 0:
		minor = host.economy.cash(acct)
	if minor <= 0:
		return _fail("没有可存入的现金。")
	if intent.params.has("duration"):
		var days: int = maxi(1, _duration_minutes(intent, 365 * DAY) / DAY)
		var fr: Dictionary = host.open_fixed_deposit(minor, days)
		if not bool(fr.get("ok", false)):
			return _fail("定期存款失败。")
		return _ok(["存入定期 %.0f 元，期限 %d 天，年息 %.2f%%。" % [
			float(minor) / 100.0, days, float(fr.get("rate", 0.0)) * 100.0]], 0, "")
	if not host.bank.deposit(host.economy, acct, minor):
		return _fail("存款失败。")
	host.sync_finances()
	host.persist_finance()
	return _ok([FlavorScript.time_line("bank", host.now_minutes()),
		"存入 %.0f 元。" % (float(minor) / 100.0)], 0, "")

func _pay_tax(intent) -> Dictionary:
	var raw: String = String(intent.params.get("method", ""))
	if raw.is_empty():
		raw = _object_id(intent, "tax")
	var tax_type: String = "income"
	var labels: Dictionary = {
		"个税": "income", "个人所得税": "income", "企业税": "corporate", "企业所得税": "corporate",
		"增值税": "vat", "消费税": "consumption", "房产税": "property", "遗产税": "inheritance",
		"印花税": "stamp", "社保": "social_security",
	}
	for label in labels.keys():
		if raw.contains(String(label)):
			tax_type = String(labels[label])
			break
	var base_major: float = float(_amount_minor(intent)) / 100.0
	if base_major <= 0.0:
		var salary: float = float((host.player().get("job", {}) as Dictionary).get("salary", 0.0))
		base_major = salary * 12.0
	if base_major <= 0.0:
		return _fail("请指定计税基数，或先拥有一份工作。")
	var r: Dictionary = host.pay_tax(tax_type, base_major)
	if not bool(r.get("ok", false)):
		return _fail("缴税失败：现金不足或税目无效。")
	return _ok(["应纳 %.0f 元，实缴 %.0f 元。" % [
		float(r.get("due_minor", 0)) / 100.0, float(r.get("collected_minor", 0)) / 100.0]], 0, "")

func _lottery(_intent) -> Dictionary:
	var r: Dictionary = host.play_lottery()
	if not bool(r.get("ok", false)):
		return _fail("现金不足，买不了彩票。")
	if bool(r.get("won", false)):
		return _ok(["彩票中奖，获得 %.0f 元。" % (float(r.get("payout", 0)) / 100.0)], 0, "")
	return _ok(["彩票未中奖。"], 0, "")

func _bank_loan(intent) -> Dictionary:
	var minor := _amount_minor(intent)
	if minor <= 0:
		return _fail("请指定贷款金额。")
	var days: int = maxi(1, _duration_minutes(intent, 365 * DAY) / DAY)
	var r: Dictionary = host.bank_loan(minor, days)
	if not bool(r.get("ok", false)):
		return _fail("贷款未获批。")
	return _ok(["贷款 %.0f 元，期限 %d 天，信用 %d。" % [
		float(r.get("principal", 0)) / 100.0, days, int(r.get("rating", 0))]], 0, "")

func _bank_repay(intent) -> Dictionary:
	var minor := _amount_minor(intent)
	if minor <= 0:
		minor = host.economy.debt(host.account_id())
	var r: Dictionary = host.repay_bank_loan(minor)
	if not bool(r.get("ok", false)):
		return _fail("没有需要偿还的贷款。")
	return _ok(["还款 %.0f 元，剩余负债 %.0f 元。" % [
		float(r.get("paid", 0)) / 100.0, float(r.get("remaining", 0)) / 100.0]], 0, "")

func _security_key(intent) -> String:
	var key := _object_id(intent, "asset")
	if key.is_empty():
		key = String(intent.params.get("method", ""))
	if key.is_empty():
		key = String(intent.params.get("name", ""))
	return key

func _security_buy(intent) -> Dictionary:
	var key := _security_key(intent)
	if key.is_empty():
		return _fail("请指定证券代码，如「买股票 科技成长 10」。")
	var r: Dictionary = host.buy_security(key, _quantity(intent))
	if not bool(r.get("ok", false)):
		return _fail("买入失败：%s。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["买入 %s %d 份，成交价 %.2f，支出 %.0f 元。" % [
		String(r.get("key", key)), int(r.get("qty", 0)), float(r.get("price", 0.0)),
		float(r.get("cost", 0)) / 100.0]], 0, "")

func _security_sell(intent) -> Dictionary:
	var key := _security_key(intent)
	if key.is_empty():
		return _fail("请指定证券代码，如「卖股票 科技成长 10」。")
	var r: Dictionary = host.sell_security(key, _quantity(intent))
	if not bool(r.get("ok", false)):
		return _fail("卖出失败：%s。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["卖出 %s %d 份，成交价 %.2f，回款 %.0f 元。" % [
		String(r.get("key", key)), int(r.get("qty", 0)), float(r.get("price", 0.0)),
		float(r.get("proceeds", 0)) / 100.0]], 0, "")

func _withdraw(intent) -> Dictionary:
	var minor := _amount_minor(intent)
	var acct: String = host.account_id()
	if minor <= 0:
		minor = host.economy.bank(acct)
	if minor <= 0:
		return _fail("没有可支取的存款。")
	if not host.bank.withdraw(host.economy, acct, minor):
		return _fail("取款失败。")
	host.sync_finances()
	return _ok([FlavorScript.time_line("bank", host.now_minutes()),
		"取出 %.0f 元。" % (float(minor) / 100.0)], 0, "")

func _job_apply(intent) -> Dictionary:
	var job_id := _object_id(intent, "location")
	if job_id.is_empty():
		var openings: Array = host.jobs.openings(host.player())
		return _ok(["当前有 %d 个岗位可应聘；用「求职 <岗位>」申请。" % openings.size()], 0, "")
	if not host.jobs.has_def(job_id):
		return _fail("未知岗位「%s」。" % job_id)
	var r: Dictionary = host.jobs.apply(host.player(), job_id, host.rng, host.now_minutes())
	if r.is_empty():
		return _fail("求职失败。")
	if bool(r.get("hired", false)):
		return _ok(["你应聘 %s 成功，已入职。" % _job_name(job_id)], 0, "")
	if String(r.get("reason", "")) == "unqualified":
		return _ok(["你不符合 %s 的条件。" % _job_name(job_id)], 0, "")
	return _ok(["你应聘 %s 未通过，面试得分 %.0f。" % [_job_name(job_id), float(r.get("score", 0.0))]], 0, "")

func _job_resign(intent) -> Dictionary:
	if not host.jobs.is_employed(host.player()):
		return _fail("你目前没有工作。")
	var r: Dictionary = host.jobs.resign(host.player(), host.now_minutes())
	if not bool(r.get("ok", false)):
		return _fail("辞职失败。")
	return _ok(["你辞去了工作。"], 0, "")

func _interact(intent, type: String) -> Dictionary:
	var target := _object_id(intent, "person")
	if target.is_empty():
		return _fail("请指定人物。")
	var r: Dictionary = host.relations.apply_interaction(host.player(), target, type, {"minute": host.now_minutes()})
	if not bool(r.get("ok", false)):
		return _fail("互动失败：%s" % String(r.get("reason", "")))
	return _ok([FlavorScript.time_line("interact", host.now_minutes()),
		"你与 %s 互动（%s）。" % [target, String(r.get("level", ""))]], 0, "")

func _confess(intent) -> Dictionary:
	var target := _object_id(intent, "person")
	if target.is_empty():
		return _fail("请指定人物。")
	if host.find_person(target).is_empty():
		return _fail("你与对方还不熟。")
	var p: Dictionary = host.player()
	var rel: Dictionary = host.relations.ensure_relation(p, target)
	var charm := _attr(p, "ability", "charm", 50.0)
	var mood := _attr(p, "psychological", "mood", 50.0)
	var r: Dictionary = host.family.confess(float(rel.get("favor", 0.0)), charm, mood, 50.0, host.rng)
	if bool(r.get("success", false)):
		host.relations.apply_interaction(p, target, "dine", {"minute": host.now_minutes(), "romance": true})
		return _ok(["你向 %s 表白，对方答应了。" % _person_name(target)], 0, "")
	return _ok(["你向 %s 表白，对方婉拒了。" % _person_name(target)], 0, "")

func _propose(intent) -> Dictionary:
	var target := _object_id(intent, "person")
	if target.is_empty():
		return _fail("请指定人物。")
	var rel: Dictionary = host.relations.get_relation(host.player(), target)
	if rel.is_empty():
		return _fail("你与 %s 还不熟。" % _person_name(target))
	var charm := _attr(host.player(), "ability", "charm", 50.0)
	var r: Dictionary = host.family.propose(float(rel.get("favor", 0.0)), float(rel.get("intimacy", 0.0)), charm, host.rng)
	if not bool(r.get("ok", false)):
		return _fail("还不到求婚的时候，需要更高的好感与亲密度。")
	if bool(r.get("success", false)):
		host.marry_with(target)
		return _ok(["你向 %s 求婚成功，你们结婚了。" % _person_name(target)], 0, "")
	return _ok(["你向 %s 求婚，对方暂时没有答应。" % _person_name(target)], 0, "")

func _divorce(_intent) -> Dictionary:
	var r: Dictionary = host.divorce()
	if not bool(r.get("ok", false)):
		return _fail("你目前没有配偶。")
	return _ok(["你结束了这段婚姻。"], 0, "")

func _person_name(person_id: String) -> String:
	var npc: Dictionary = host.find_person(person_id)
	return String(npc.get("name", person_id))

func _conceive(_intent) -> Dictionary:
	var r: Dictionary = host.try_conceive()
	if not bool(r.get("ok", false)):
		match String(r.get("reason", "")):
			"not_married":
				return _fail("你还没有结婚。")
			"already_pregnant":
				return _fail("你们已经有孩子在孕育中了。")
			_:
				return _fail("暂时不能受孕。")
	var due := int((r.get("pregnancy", {}) as Dictionary).get("due_minutes", 0))
	return _ok(["你们开始迎接新生命，预计在游戏第 %d 天前后分娩。" % (due / 1440 + 1)], 0, "")

func _write_will(_intent) -> Dictionary:
	var p: Dictionary = host.player()
	var fam: Dictionary = p.get("family", {})
	var bens: Array = []
	var sid := String(fam.get("spouse_id", ""))
	if sid != "":
		bens.append({"id": sid, "share": 1.0})
	else:
		var kids: Array = fam.get("children_ids", [])
		if kids.is_empty():
			return _fail("你还没有配偶或子女，暂时无人可继承。")
		var share := 1.0 / float(kids.size())
		for cid in kids:
			bens.append({"id": String(cid), "share": share})
	p["will"] = {"written_minutes": host.now_minutes(), "beneficiaries": bens}
	return _ok(["你立下遗嘱，指定了 %d 位继承人。" % bens.size()], 0, "")

func _list_homes(_intent) -> Dictionary:
	var rows: Array = []
	for p in host.property_listings():
		rows.append("%s（%s %.0f㎡）约 %.1f 万元，月供约 %.0f 元" % [
			String(p.get("name", "")), String(p.get("layout", "")), float(p.get("area_sqm", 0.0)),
			float(p.get("price", 0)) / 10000.0, float(p.get("monthly_payment", 0)) / 100.0])
	for p in host.property_owned():
		rows.append("【自有】%s（%s %.0f㎡）估值约 %.1f 万元%s" % [
			String(p.get("name", "")), String(p.get("layout", "")), float(p.get("area_sqm", 0.0)),
			float(p.get("price", 0)) / 10000.0, "，已出租" if bool(p.get("rented", false)) else ""])
	if rows.is_empty():
		return _ok(["当前没有可看的房源。"], 0, "")
	return _ok(["房源信息："] + rows, 0, "")

func _buy_home(intent) -> Dictionary:
	var prop_id := _object_id(intent, "property")
	if prop_id.is_empty():
		return _fail("请指定房源。")
	var r: Dictionary = host.property_purchase(prop_id)
	if not bool(r.get("ok", false)):
		return _fail("购买失败：%s。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你买下了这套房，首付 %.1f 万元，月供 %.0f 元。" % [
		float(r.get("down", 0)) / 10000.0, float(r.get("monthly_payment", 0)) / 100.0]], 0, "")

func _sell_home(intent) -> Dictionary:
	var prop_id := _object_id(intent, "property")
	if prop_id.is_empty():
		return _fail("请指定房产。")
	var r: Dictionary = host.property_sell(prop_id)
	if not bool(r.get("ok", false)):
		return _fail("出售失败：%s。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你卖掉了这套房，净得 %.1f 万元。" % (float(r.get("net", 0)) / 10000.0)], 0, "")

func _rent_home(intent) -> Dictionary:
	var prop_id := _object_id(intent, "property")
	if prop_id.is_empty():
		return _fail("请指定房产。")
	var r: Dictionary = host.property_rent(prop_id)
	if not bool(r.get("ok", false)):
		return _fail("出租失败：%s。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已出租，月租 %.0f 元。" % (float(r.get("monthly_rent", 0)) / 100.0)], 0, "")

func _adopt_pet(intent) -> Dictionary:
	var species := _object_id(intent, "pet_species")
	if species.is_empty():
		return _fail("请指定要领养的宠物种类。")
	var r: Dictionary = host.adopt_pet(species)
	if not bool(r.get("ok", false)):
		match String(r.get("reason", "")):
			"insufficient_funds":
				return _fail("资金不足，无法领养。")
			"unknown_species":
				return _fail("没有这种宠物。")
			_:
				return _fail("暂时无法领养。")
	var pet_rec: Dictionary = r.get("pet", {})
	return _ok(["你领养了一只「%s」（%s）。" % [
		String(pet_rec.get("name", species)), String(pet_rec.get("species", species))]], 0, "")

func _feed_pets(_intent) -> Dictionary:
	var done: Array = host.feed_pets()
	if done.is_empty():
		return _fail("你没有需要喂养的宠物。")
	return _ok(["你喂饱了：%s。" % ", ".join(done)], 0, "")

func _social_publish(intent) -> Dictionary:
	var platform: String = String(intent.params.get("social_platform", ""))
	if platform.is_empty():
		return _fail("请指定社交平台。")
	var r: Dictionary = host.social_publish(platform, "分享今日近况。", 0.1, false)
	if not bool(r.get("ok", false)):
		return _fail("无法发布动态。")
	var post: Dictionary = r.get("post", {})
	return _ok(["在%s发布动态，触达 %d，获赞 %d。" % [String(post.get("platform", platform)), int(float(post.get("reach", 0.0)) * 100.0), int(post.get("likes", 0))]], 0, "")

func _social_feed(intent) -> Dictionary:
	var d: Dictionary = host.social_panel_data()
	if int(d.get("post_count", 0)) == 0:
		return _ok(["还没有动态。"], 0, "social")
	var posts: Array = d.get("posts", [])
	return _ok(["共 %d 条动态，最近一条：%s" % [int(d.get("post_count", 0)), String((posts[0] as Dictionary).get("content", ""))]], 0, "social")

func _train_pets(_intent) -> Dictionary:
	var done: Array = host.train_pets()
	if done.is_empty():
		return _fail("你没有可以训练的宠物。")
	return _ok(["你训练了：%s。" % ", ".join(done)], 0, "")

func _adopt_child(_intent) -> Dictionary:
	var r: Dictionary = host.adopt_child()
	if not bool(r.get("ok", false)):
		return _fail("暂时无法收养子女。")
	var child: Dictionary = r.get("child", {})
	return _ok(["你收养了 %s，从此担起养育之责。" % String(child.get("name", "一名子女"))], 0, "")

func _assign_guardian(intent) -> Dictionary:
	var target := _object_id(intent, "person")
	if target.is_empty():
		return _fail("请指定要托付的人。")
	var r: Dictionary = host.assign_guardian(target)
	if not bool(r.get("ok", false)):
		return _fail("未找到此人，无法指定为监护人。")
	return _ok(["你指定 %s 为子女的监护人。" % _person_name(target)], 0, "")

func _mental_treat(intent, method: String) -> Dictionary:
	var key := _object_id(intent, "mental_disorder")
	var r: Dictionary = host.mental_treat(method, key)
	if not bool(r.get("ok", false)):
		match String(r.get("reason", "")):
			"no_active_disorder":
				return _fail("你目前没有需要治疗的精神疾病。")
			"insufficient_funds":
				return _fail("资金不足，无法支付治疗费用。")
			"unknown_treatment":
				return _fail("暂不支持该治疗方式。")
			_:
				return _fail("治疗未能进行。")
	var outcome := String(r.get("outcome", "ineffective"))
	var outcome_cn: String = String({"cured": "根治", "remitted": "缓解", "ineffective": "无效"}.get(outcome, outcome))
	var lines: Array = ["接受了「%s」，对 %s 的结果：%s。" % [
		String(r.get("method_name", method)), String(r.get("key_name", "")), outcome_cn]]
	if bool(r.get("misdiagnosed", false)):
		lines.append("存在误诊，疗效打折。")
	if bool(r.get("side_effect", false)):
		lines.append("出现药物副作用。")
	return _ok(lines, 0, "")

func _relax(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, HOUR)
	host.apply_emotion_event("praise")
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var et: String = host.emotion_state()
	lines.append("你静心放松，情绪趋于%s。" % _emotion_cn(et))
	return _ok(lines, minutes, "")

func _emotion_cn(state: String) -> String:
	match state:
		"anxious":
			return "焦虑"
		"depressed":
			return "低落"
		"manic":
			return "亢奋"
		_:
			return "平静"

# --- 精神追求与信仰（D15） ---

func _pursue_spirit(intent) -> Dictionary:
	var kind := _object_id(intent, "pursuit")
	if kind.is_empty():
		return _fail("未指定修持法门；可修持冥想、修行、哲学阅读、写作、自省、志愿服务或艺术创作。")
	if not host.spirituality.PURSUITS.has(kind):
		return _fail("未知的修持法门。")
	var minutes := _duration_minutes(intent, HOUR)
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var r: Dictionary = host.pursue_spirit(kind, minutes)
	if not bool(r.get("ok", false)):
		return _fail("此次修持未能进行。")
	lines.append("你投入「%s」%d 分钟，心境%s。" % [String(r.get("name", kind)), minutes, ("更进一层（%s）" % String(r.get("realm", ""))) if bool(r.get("realm_unlocked", false)) else "渐趋平和"])
	return _ok(lines, minutes, "")

func _convert_faith(intent) -> Dictionary:
	var faith := _object_id(intent, "faith")
	if faith.is_empty():
		return _fail("未指定信仰；可皈依佛教、道家、基督教、伊斯兰教或斯多葛、存在主义等流派。")
	var r: Dictionary = host.convert_faith(faith)
	if not bool(r.get("ok", false)):
		return _fail("无法皈依该信仰。")
	return _ok(["你皈依了「%s」（%s），从此有了精神寄托。" % [String(r.get("name", faith)), "宗教" if String(r.get("type", "")) == "religion" else "哲学"]], 0, "")

func _deepen_faith(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, HOUR)
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var r: Dictionary = host.deepen_faith(minutes)
	if not bool(r.get("ok", false)):
		return _fail("你尚未皈依任何信仰，无从深化。")
	lines.append("你潜心修持「%s」%d 分钟，境界%s。" % [String(r.get("faith_name", "")), minutes, String(r.get("realm", ""))])
	return _ok(lines, minutes, "")

func _resolve_crisis(intent) -> Dictionary:
	var exit_kind := _object_id(intent, "crisis_exit")
	if exit_kind.is_empty():
		return _fail("请指定化解出口：宗教熏修、哲学省思、心理疏导或志愿服务。")
	var r: Dictionary = host.resolve_spirit_crisis(exit_kind)
	if not bool(r.get("ok", false)):
		return _fail("当前没有需要化解的精神危机。" if String(r.get("reason", "")) == "no_crisis" else "该出口不适用于当前危机。")
	return _ok(["你以「%s」化解了精神危机，内心重归澄明。" % _exit_cn(String(r.get("via", exit_kind)))], 0, "")

func _exit_cn(kind: String) -> String:
	match kind:
		"religion":
			return "宗教熏修"
		"philosophy":
			return "哲学省思"
		"psychology":
			return "心理疏导"
		"volunteering":
			return "志愿服务"
		_:
			return kind

# --- 组织与社团（D19） ---

func _join_org(intent) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		return _fail("未指定要加入的组织；可打开「组织」面板了解可加入的工会、协会、NGO、俱乐部或阵营。")
	var r: Dictionary = host.join_organization(oid)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	return _ok(["你加入了「%s」，缴纳首次会费 %.0f 元。" % [String(r.get("name", oid)), float(r.get("dues", 0))]], 0, "")

func _leave_org(intent) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		var memberships: Array = host.organizations_panel_data().get("memberships", [])
		if memberships.size() == 1:
			oid = String((memberships[0] as Dictionary).get("id", ""))
		else:
			return _fail("请指定要退出哪个组织。")
	var r: Dictionary = host.leave_organization(oid, false)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	var lines: Array = ["你退出了「%s」。" % String(r.get("name", oid))]
	var cost := int(r.get("exit_cost", 0))
	if cost > 0:
		lines.append("退出成本 %.0f 元。" % float(cost))
	if float(r.get("legal_risk", 0.0)) > 0.0:
		lines.append("叛逃留下法律隐患（风险 %.0f%%）。" % (float(r.get("legal_risk", 0.0)) * 100.0))
	return _ok(lines, 0, "")

func _pay_org_dues(intent) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		var memberships: Array = host.organizations_panel_data().get("memberships", [])
		if memberships.size() == 1:
			oid = String((memberships[0] as Dictionary).get("id", ""))
		else:
			return _fail("请指定要缴纳会费的组织。")
	var r: Dictionary = host.pay_org_dues(oid)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	return _ok(["你缴纳了 %.0f 元会费，尚欠 %.0f 元。" % [float(r.get("paid", 0)), float(r.get("dues_owed", 0))]], 0, "")

func _org_task(intent) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		var memberships: Array = host.organizations_panel_data().get("memberships", [])
		if memberships.size() == 1:
			oid = String((memberships[0] as Dictionary).get("id", ""))
		else:
			return _fail("请指定要承接任务的组织。")
	var r: Dictionary = host.do_org_task(oid)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	var lines: Array = []
	if bool(r.get("success", false)):
		lines.append("你完成了组织交办的事务，累计 %d 件。" % int(r.get("tasks_completed", 0)))
		if bool(r.get("promoted", false)):
			lines.append("你获得晋升，现任「%s」，开始领取津贴。" % String(r.get("rank_name", "")))
	else:
		lines.append("此次事务未能办妥，声望略有损失。")
	return _ok(lines, 0, "")

func _org_action(intent, action: String) -> Dictionary:
	var oid := _object_id(intent, "organization")
	if oid.is_empty():
		var memberships: Array = host.organizations_panel_data().get("memberships", [])
		if memberships.size() == 1:
			oid = String((memberships[0] as Dictionary).get("id", ""))
		else:
			return _fail("请指定要发起行动的组织。")
	var r: Dictionary = host.org_collective_action(oid, action)
	if not bool(r.get("ok", false)):
		return _fail(_org_reason(String(r.get("reason", ""))))
	var lines: Array = ["你组织了「%s」（成功率 %.0f%%）。" % [_org_action_cn(action), float(r.get("probability", 0.0)) * 100.0]]
	if bool(r.get("success", false)):
		lines.append("行动奏效，组织影响力上升。")
	else:
		lines.append("行动受挫，组织影响力受损。")
	if bool(r.get("exposed", false)):
		lines.append("组织因此暴露并瓦解，你留下案底（通缉等级 %d）。" % int(r.get("wanted_level", 0)))
	return _ok(lines, 0, "")

func _org_action_cn(action: String) -> String:
	return String(host.organizations.ACTIONS.get(action, {}).get("name", action))

func _org_reason(reason: String) -> String:
	match reason:
		"not_found":
			return "未找到该组织"
		"already_member":
			return "你已是该组织成员"
		"not_member":
			return "你并未加入该组织"
		"disbanded":
			return "该组织已经解散"
		"insufficient_funds":
			return "资金不足"
		"recovering":
			return "仍处于恢复期"
		"already_done":
			return "该项目不可重复进行"
		"no_grounds":
			return "没有可主张的维权事由"
		"existing_claim":
			return "已有未结民事案件"
		"unknown_care":
			return "未知护理方式"
		"unknown_project":
			return "未知医美项目"
		"nothing_due":
			return "当前没有欠缴会费"
		"unknown_action":
			return "不支持该集体行动"
		_:
			return reason if reason != "" else "操作未能完成"

# --- 语言与文化（D20） ---

func _study_language(intent) -> Dictionary:
	var lang := _object_id(intent, "language")
	if lang.is_empty():
		return _fail("未指定语言；可学汉语、英语、西班牙语、日语或法语。")
	var minutes := _duration_minutes(intent, HOUR)
	var adv: Dictionary = _advance_time(minutes, {}, "study")
	var lines: Array = adv["narration"]
	var r: Dictionary = host.study_language(lang, "course", float(minutes) / 60.0)
	if not bool(r.get("ok", false)):
		return _fail("无法学习该语言。")
	lines.append("你修习「%s」%.0f 小时，综合等级升至 %.1f。" % [_language_name(lang), float(minutes) / 60.0, float(r.get("overall", 0.0))])
	return _ok(lines, minutes, "")

func _immerse_language(intent) -> Dictionary:
	var lang := _object_id(intent, "language")
	if lang.is_empty():
		return _fail("未指定语言；可在海外环境中沉浸学习。")
	var minutes := _duration_minutes(intent, DAY)
	var adv: Dictionary = _advance_time(minutes, {}, "study")
	var lines: Array = adv["narration"]
	var days: float = float(minutes) / float(DAY)
	var r: Dictionary = host.immerse_language(lang, days)
	if not bool(r.get("ok", false)):
		return _fail("无法沉浸学习该语言。")
	lines.append("你沉浸在「%s」的语言环境中 %.1f 天，综合等级升至 %.1f。" % [_language_name(lang), days, float(r.get("overall", 0.0))])
	return _ok(lines, minutes, "")

func _language_exam(intent) -> Dictionary:
	var lang := _object_id(intent, "language")
	if lang.is_empty():
		return _fail("未指定语言；可参加汉语、英语、西班牙语、日语或法语考试。")
	var target := 60.0
	var r: Dictionary = host.take_language_exam(lang, target)
	if not bool(r.get("ok", false)):
		return _fail("无法参加该语言考试。")
	if bool(r.get("passed", false)):
		return _ok(["你通过了「%s」等级 %.0f 考试（成绩 %.1f），获得证书。" % [_language_name(lang), target, float(r.get("score", 0.0))]], 0, "")
	return _fail("你的「%s」水平（%.1f）未达到等级 %.0f 的要求，未能通过考试。" % [_language_name(lang), float(r.get("score", 0.0)), target])

func _adapt_culture(intent) -> Dictionary:
	var culture := _object_id(intent, "culture")
	if culture.is_empty():
		return _fail("未指定文化；可适应中华、美国、日本、法国或阿拉伯文化。")
	var minutes := _duration_minutes(intent, 30 * DAY)
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var days: float = float(minutes) / float(DAY)
	var r: Dictionary = host.adapt_culture(culture, days)
	if not bool(r.get("ok", false)):
		return _fail("无法适应该文化。")
	lines.append("你用了 %.0f 天适应当地文化，适应度升至 %.0f%%，文化冲击降至 %.0f%%。" % [
		days, float(r.get("adaptation", 0.0)) * 100.0, float(r.get("shock", 0.0)) * 100.0])
	return _ok(lines, minutes, "")


# --- 残障与养老（D21） ---

func _fit_device(intent) -> Dictionary:
	var device := _object_id(intent, "device")
	if device.is_empty():
		return _fail("未指定辅具；可装备轮椅、助听器、义肢、导盲犬等。")
	var dev: Dictionary = host.disability.DEVICES.get(device, {})
	var r: Dictionary = host.fit_disability_device(device)
	if not bool(r.get("ok", false)):
		return _fail("无法装配该辅具（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你装配了「%s」，移动能力升至 %.0f%%。" % [String(dev.get("name", device)), float(r.get("mobility", 1.0)) * 100.0]], 0, "")

func _rehab(intent) -> Dictionary:
	var minutes := _duration_minutes(intent, 30 * DAY)
	var adv: Dictionary = _advance_time(minutes, {}, "rest")
	var lines: Array = adv["narration"]
	var r: Dictionary = host.disability_surgery(0.3)
	if not bool(r.get("ok", false)):
		return _fail("无法进行康复训练（%s）。" % _reason_cn(String(r.get("reason", ""))))
	lines.append("你坚持康复训练 %.0f 天，移动能力恢复至 %.0f%%。" % [float(minutes) / float(DAY), float(r.get("mobility", 1.0)) * 100.0])
	return _ok(lines, minutes, "")

func _accessible_retrofit(intent) -> Dictionary:
	var r: Dictionary = host.set_accessible_place(true)
	if not bool(r.get("ok", false)):
		return _fail("无法进行无障碍改造（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你完成了无障碍改造，移动能力升至 %.0f%%。" % (float(r.get("mobility", 1.0)) * 100.0)], 0, "")

func _choose_care_mode(intent) -> Dictionary:
	var mode := _object_id(intent, "care_mode")
	if mode.is_empty():
		return _fail("未指定养老模式；可选居家护理、社区养老或机构养老。")
	var r: Dictionary = host.choose_care_mode(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法选择该养老模式。")
	var def: Dictionary = r.get("def", {})
	return _ok(["你选择了「%s」养老，月成本约 %d，照护质量 %.0f%%。" % [
		String(def.get("name", mode)), int(def.get("cost_per_month", 0)), float(def.get("quality", 0.0)) * 100.0]], 0, "")

func _hospice(intent) -> Dictionary:
	var r: Dictionary = host.hospice_care(0.8)
	if not bool(r.get("ok", false)):
		return _fail("无法安排临终关怀。")
	return _ok(["你安排了临终关怀，舒适度与尊严得到保障（%.0f%%）。" % (float(r.get("comfort", 0.0)) * 100.0)], 0, "")

func _guardianship(intent) -> Dictionary:
	var guardian := _object_id(intent, "person")
	if guardian.is_empty():
		guardian = String(intent.params.get("method", "")).strip_edges()
	if guardian.is_empty():
		return _fail("未指定监护人。")
	var r: Dictionary = host.establish_guardianship(guardian)
	if not bool(r.get("ok", false)):
		return _fail("无法设立监护：当事人仍具备决策能力。")
	return _ok(["已为当事人设立监护人「%s」。" % guardian], 0, "")

func _language_name(lang: String) -> String:
	return String(host.language.language_def(lang).get("name", lang))


# --- 农业与乡土（D22） ---

func _acquire_land(intent) -> Dictionary:
	var area := float(intent.params.get("number", 0))
	if area <= 0.0:
		area = 5.0
	var r: Dictionary = host.acquire_farm_land(area, "grain", "contract", 100000, {})
	if not bool(r.get("ok", false)):
		return _fail("无法取得土地（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你承包了 %.1f 亩农地，累计土地估值 %d。" % [area, int(r.get("asset_value", 0))]], 0, "")

func _sow(intent) -> Dictionary:
	var crop := _object_id(intent, "crop")
	if crop.is_empty():
		return _fail("未指定作物；可选水稻、小麦、棉花、油菜、蔬菜或药材。")
	var r: Dictionary = host.plant_crop(0, crop, {})
	if not bool(r.get("ok", false)):
		return _fail("无法播种（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你在农地播下「%s」。" % _crop_name(crop)], 0, "")

func _harvest_crop(intent) -> Dictionary:
	var farm: Dictionary = host.farm_state()
	var plots: Array = farm.get("plots", [])
	var idx := -1
	for i in range(plots.size()):
		if String((plots[i] as Dictionary).get("stage", "")) == "mature":
			idx = i
			break
	if idx < 0:
		return _fail("没有成熟的作物可以收割。")
	var r: Dictionary = host.harvest_crop(idx, {"skill": 0.5})
	if not bool(r.get("ok", false)):
		return _fail("收割失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你收割了「%s」，入仓 %.1f。" % [_crop_name(String(r.get("crop", ""))), float(r.get("yield", 0.0))]], 0, "")

func _raise_livestock(intent) -> Dictionary:
	var animal := _object_id(intent, "livestock")
	if animal.is_empty():
		return _fail("未指定牲畜；可选生猪、肉牛、肉鸡、鸭或鱼。")
	var count := int(intent.params.get("number", 0))
	if count <= 0:
		count = 5
	var r: Dictionary = host.add_farm_livestock(animal, count)
	if not bool(r.get("ok", false)):
		return _fail("无法增加存栏（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你购入了 %d 头/只「%s」。" % [count, _livestock_name(animal)]], 0, "")

func _sell_produce(intent) -> Dictionary:
	var item := _object_id(intent, "crop")
	if item.is_empty():
		return _fail("未指定农产品；可用卖粮 <作物>。")
	var storage: Dictionary = host.farm_state().get("storage", {})
	var amount := float(storage.get(item, 0.0))
	if amount <= 0.0:
		return _fail("仓中并无该农产品。")
	var r: Dictionary = host.sell_produce(item, amount, "market", {})
	if not bool(r.get("ok", false)):
		return _fail("售卖失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你售出「%s」%.1f，收入 %d。" % [_crop_name(item), amount, int(r.get("revenue", 0))]], 0, "")

func _farm_subsidy(intent) -> Dictionary:
	var r: Dictionary = host.apply_farm_subsidy(50000)
	if not bool(r.get("ok", false)):
		return _fail("申领补贴失败。")
	return _ok(["你申领到农业补贴 %d。" % int(r.get("granted", 0))], 0, "")

func _open_account(intent) -> Dictionary:
	var platform := _object_id(intent, "platform")
	if platform.is_empty():
		platform = String(intent.params.get("method", "")).strip_edges()
	if platform.is_empty():
		return _fail("未指定平台；可选直播或短视频。")
	var r: Dictionary = host.open_digital_account(platform)
	if not bool(r.get("ok", false)):
		return _fail("开通账号失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你开通了「%s」账号。" % _platform_name(platform)], 0, "")

func _verify_identity(intent) -> Dictionary:
	var r: Dictionary = host.verify_digital_identity()
	return _ok(["数字身份已实名认证，隐私级别降至 %.0f%%。" % (float(r.get("privacy", 0.0)) * 100.0)], 0, "")

func _security_work(intent) -> Dictionary:
	var kind := _object_id(intent, "security_job")
	if kind.is_empty():
		return _fail("未指定工作类型；可选渗透测试、安全防护、应急响应或数据泄露处置。")
	var r: Dictionary = host.digital_security_work(kind)
	if not bool(r.get("ok", false)):
		return _fail("无法从事该网络安全工作（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("success", false)):
		return _ok(["本次%s任务未通过，暂无收入。" % _security_job_name(kind)], 0, "")
	return _ok(["你完成了%s任务，收入 %d。" % [_security_job_name(kind), int(r.get("income", 0))]], 0, "")

func _publish_content(intent) -> Dictionary:
	var platform := _object_id(intent, "platform")
	if platform.is_empty():
		platform = "short_video"
	var r: Dictionary = host.publish_digital_content(platform)
	if not bool(r.get("ok", false)):
		return _fail("发布失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你在「%s」发布内容，播放 %d，涨粉 %d，收入 %d。" % [_platform_name(platform), int(r.get("views", 0)), int(r.get("fans_delta", 0)), int(r.get("income", 0))]], 0, "")

func _hack_target(intent) -> Dictionary:
	var target := _object_id(intent, "hack_target")
	if target.is_empty():
		return _fail("未指定目标；可选个人、企业、政府或黑产。")
	var r: Dictionary = host.digital_hack(target)
	if not bool(r.get("ok", false)):
		return _fail("无法实施入侵（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _ok(["你侵入了%s，获取 %d，但行动暴露并留下案底。" % [_hack_target_name(target), int(r.get("gain", 0))]], 0, "")
	if not bool(r.get("success", false)):
		return _ok(["你尝试侵入%s，但未能得手。" % _hack_target_name(target)], 0, "")
	return _ok(["你侵入了%s，获取 %d，未被察觉。" % [_hack_target_name(target), int(r.get("gain", 0))]], 0, "")

func _platform_name(platform: String) -> String:
	return String(host.digital.CONTENT_PLATFORMS.get(platform, {}).get("name", platform))

func _security_job_name(kind: String) -> String:
	return String(host.digital.SECURITY_JOBS.get(kind, {}).get("name", kind))

func _hack_target_name(target: String) -> String:
	return String(host.digital.HACK_TARGETS.get(target, {}).get("name", target))

func _crop_name(crop: String) -> String:
	return String(host.agriculture.crop_def(crop).get("name", crop))
func _livestock_name(animal: String) -> String:
	return String(host.agriculture.livestock_def(animal).get("name", animal))

# --- 后期科技（D24） ---

func _unlock_tech(intent) -> Dictionary:
	var r: Dictionary = host.unlock_late_tech_stage()
	if not bool(r.get("ok", false)):
		if String(r.get("reason", "")) == "max_stage":
			return _ok(["科技已抵达最高阶段：%s。" % host.late_tech_panel_data().get("stage_name", "")], 0, "")
		return _fail("无法推进科技（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var data: Dictionary = host.late_tech_panel_data()
	return _ok(["科技迈入新阶段：%s。" % String(data.get("stage_name", ""))], 0, "")

func _apply_tech_career(intent) -> Dictionary:
	var career := _object_id(intent, "late_tech_career")
	if career.is_empty():
		return _fail("未指定科技职业；可先「看科技」查看可选职业。")
	var r: Dictionary = host.apply_late_tech_career(career)
	if not bool(r.get("ok", false)):
		return _fail("无法应聘该科技职业（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你入职了%s，薪资 %d。" % [_tech_career_name(career), int(r.get("salary", 0))]], 0, "")

func _tech_mission(intent) -> Dictionary:
	var mission := _object_id(intent, "late_tech_mission")
	if mission.is_empty():
		return _fail("未指定任务；可先「看科技」查看高风险任务。")
	var r: Dictionary = host.risk_late_tech_mission(mission)
	if not bool(r.get("ok", false)):
		return _fail("无法执行该任务（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("casualty", false)):
		return _ok(["在执行%s时发生重大事故，任务失败。" % _tech_mission_name(mission)], 0, "")
	if bool(r.get("accident", false)):
		return _ok(["执行%s时遭遇事故，仍获得报酬 %d。" % [_tech_mission_name(mission), int(r.get("reward", 0))]], 0, "")
	return _ok(["完成%s，获得报酬 %d。" % [_tech_mission_name(mission), int(r.get("reward", 0))]], 0, "")

func _biotech(intent) -> Dictionary:
	var amount: float = 1000.0
	var p: Variant = intent.params.get("number", null) if intent.params is Dictionary else null
	if p != null:
		amount = float(p)
	var r: Dictionary = host.invest_biotech_lifespan(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法进行生物延寿投资（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你投入 %d 于生物科技，延寿 %+.1f 年（累计 %+.1f 年）。" % [int(amount), float(r.get("lifespan_gain", 0.0)), float(r.get("total_bonus", 0.0))]], 0, "")

func _late_tech_automation(intent) -> Dictionary:
	var efficiency: float = float(_param_number(intent, "number", 100)) / 100.0
	var r: Dictionary = host.late_tech_automation_impact(efficiency)
	if not bool(r.get("ok", false)):
		return _fail("无法评估自动化冲击（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var msg: String = "效率 %.2f：淘汰 %d 岗、新增 %d 岗，失业率 %.1f%%。" % [efficiency, int(r.get("jobs_lost", 0)), int(r.get("jobs_created", 0)), float(r.get("unemployment_rate", 0.0)) * 100.0]
	if bool(r.get("social_security_issue", false)):
		msg += " 已触发失业危机与社会保障议题。"
	return _ok([msg], 0, "")

func _late_tech_environment(intent) -> Dictionary:
	var env := _object_id(intent, "late_tech_environment")
	if env.is_empty():
		return _fail("未指定环境；可选失重、辐射或深海高压。")
	var exposure: float = float(_param_number(intent, "number", 10)) / 10.0
	var r: Dictionary = host.late_tech_extreme_environment(env, exposure)
	if not bool(r.get("ok", false)):
		return _fail("无法模拟极端环境（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["暴露于%s：骨流失 %.2f，肌肉流失 %.2f，健康损伤 %.2f。" % [String(host.late_tech.ENVIRONMENTS.get(env, {}).get("name", env)), float(r.get("bone_loss", 0.0)), float(r.get("muscle_loss", 0.0)), float(r.get("health_penalty", 0.0))]], 0, "")

func _late_tech_climate(intent) -> Dictionary:
	var warming: float = float(_param_number(intent, "number", 20)) / 10.0
	var r: Dictionary = host.late_tech_climate_refugees(warming)
	if not bool(r.get("ok", false)):
		return _fail("无法评估气候难民（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["升温 %.1f℃：新增气候难民 %d 人。" % [float(r.get("warming", 0.0)), int(r.get("refugees", 0))]], 0, "")

func _late_tech_ai(intent) -> Dictionary:
	var autonomy: float = float(_param_number(intent, "number", 90)) / 100.0
	var r: Dictionary = host.late_tech_ai_ethics_incident(autonomy)
	if not bool(r.get("ok", false)):
		return _fail("无法评估 AI 伦理风险（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("loss_of_control", false)):
		return _ok(["自主性 %.0f%% 下发生 AI 失控，连锁事件 %d 项。" % [autonomy * 100.0, (r.get("chain", []) as Array).size()]], 0, "")
	return _ok(["自主性 %.0f%% 下未发生失控（概率 %.0f%%）。" % [autonomy * 100.0, float(r.get("probability", 0.0)) * 100.0]], 0, "")

func _tech_career_name(career: String) -> String:
	return String(host.late_tech.CAREERS.get(career, {}).get("name", career))

func _tech_mission_name(mission: String) -> String:
	return String(host.late_tech.MISSIONS.get(mission, {}).get("name", mission))

# --- 知识产权与媒体（D25） ---

func _register_ip(intent) -> Dictionary:
	var ip_type := _object_id(intent, "ip_type")
	if ip_type.is_empty():
		return _fail("未指定知识产权类型；可选版权、专利、商标或商业秘密。")
	var r: Dictionary = host.register_ip_asset(ip_type)
	if not bool(r.get("ok", false)):
		return _fail("无法登记知识产权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var ip: Dictionary = r.get("ip", {})
	return _ok(["你登记了%s「%s」，登记费 %d。" % [_ip_type_name(ip_type), String(ip.get("title", "")), int(r.get("fee", 0))]], 0, "")

func _company_file_ip(intent) -> Dictionary:
	var ip_type := _object_id(intent, "ip_type")
	if ip_type.is_empty():
		return _fail("未指定知识产权类型；可选版权、专利、商标或商业秘密。")
	var r: Dictionary = host.company_file_ip(ip_type)
	if not bool(r.get("ok", false)):
		return _fail("无法办理职务发明（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var ip: Dictionary = r.get("ip", {})
	return _ok(["公司登记职务发明%s「%s」，费用 %d。" % [_ip_type_name(ip_type), String(ip.get("title", "")), int(r.get("fee", 0))]], 0, "")

func _license_ip(intent) -> Dictionary:
	var ip_id := _resolve_by_name("ip_asset", String(intent.params.get("method", "")))
	if ip_id.is_empty():
		return _fail("未指定知识产权；可先「看知识产权」查看已登记资产。")
	var deal: float = 1000000.0
	if intent.params.has("amount"):
		deal = float(intent.params.get("amount", 0))
	var r: Dictionary = host.license_ip_asset(ip_id, deal, false)
	if not bool(r.get("ok", false)):
		return _fail("无法授权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你对外授权，收取许可费 %d。" % int(r.get("fee", 0))], 0, "")

func _transfer_ip(intent) -> Dictionary:
	var ip_id := _resolve_by_name("ip_asset", String(intent.params.get("method", "")))
	if ip_id.is_empty():
		return _fail("未指定知识产权；可先「看知识产权」查看已登记资产。")
	var price: int = 500000
	if intent.params.has("amount"):
		price = int(intent.params.get("amount", 0))
	var r: Dictionary = host.transfer_ip_asset(ip_id, price)
	if not bool(r.get("ok", false)):
		return _fail("无法转让（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你以 %d 转让了该知识产权。" % int(r.get("price", 0))], 0, "")

func _pledge_ip(intent) -> Dictionary:
	var ip_id := _resolve_by_name("ip_asset", String(intent.params.get("method", "")))
	if ip_id.is_empty():
		return _fail("未指定知识产权；可先「看知识产权」查看已登记资产。")
	var amount: int = 300000
	if intent.params.has("amount"):
		amount = int(intent.params.get("amount", 0))
	var r: Dictionary = host.pledge_ip_asset(ip_id, amount)
	if not bool(r.get("ok", false)):
		return _fail("无法质押（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你以该知识产权质押融资 %d。" % int(r.get("amount", 0))], 0, "")

func _sue_ip(intent) -> Dictionary:
	var ip_id := _resolve_by_name("ip_asset", String(intent.params.get("method", "")))
	if ip_id.is_empty():
		return _fail("未指定知识产权；可先「看知识产权」查看已登记资产。")
	var r: Dictionary = host.sue_ip_infringer(ip_id)
	if not bool(r.get("ok", false)):
		return _fail("无法发起维权诉讼（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("win", false)):
		return _ok(["维权诉讼败诉，未能获得赔偿。"], 0, "")
	return _ok(["维权诉讼胜诉，获赔 %d。" % int(r.get("compensation", 0))], 0, "")

func _audit_content(intent) -> Dictionary:
	var risk: float = clampf(float(_param_number(intent, "number", 30)) / 100.0, 0.0, 1.0)
	var text: String = String(intent.params.get("method", "")).strip_edges()
	var copyright_infringement: bool = text.contains("侵权") or text.contains("盗版")
	var r: Dictionary = host.audit_media_content(text, risk, copyright_infringement)
	if bool(r.get("approved", false)):
		return _ok(["内容审核通过，允许发布。"], 0, "")
	var action: String = String(r.get("action", "reject"))
	var label: String = "下架" if action == "takedown" else "驳回"
	return _fail("内容审核未通过，已%s（%s）。" % [label, _reason_cn(String(r.get("reason", "")))])

func _open_media(intent) -> Dictionary:
	var media_type := _object_id(intent, "media_type")
	if media_type.is_empty():
		return _fail("未指定媒体类型；可选新闻社、出版社、影视公司、MCN 或平台。")
	var r: Dictionary = host.register_media_outlet(media_type)
	if not bool(r.get("ok", false)):
		return _fail("无法开办媒体（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var outlet: Dictionary = r.get("outlet", {})
	return _ok(["你开办了%s「%s」。" % [_media_type_name(media_type), String(outlet.get("name", ""))]], 0, "")

func _release_work(intent) -> Dictionary:
	var outlets: Array = host.ip_media_state().get("outlets", [])
	if outlets.is_empty():
		return _fail("尚未开办媒体机构；先「开办媒体」再发行作品。")
	var outlet_id: String = String((outlets[0] as Dictionary).get("id", ""))
	var title: String = String(intent.params.get("method", "")).strip_edges()
	if title.is_empty():
		title = "未命名作品"
	var r: Dictionary = host.release_media_work(outlet_id, title)
	if not bool(r.get("ok", false)):
		return _fail("无法发行作品（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["发行《%s》，票房/销量结算 %d。" % [title, int(r.get("revenue", 0))]], 0, "")

func _ip_type_name(ip_type: String) -> String:
	return String(host.ip_media.IP_TYPES.get(ip_type, {}).get("name", ip_type))

func _media_type_name(media_type: String) -> String:
	return String(host.ip_media.MEDIA_TYPES.get(media_type, {}).get("name", media_type))

# --- 制造业与供应链（D26） ---

func _found_factory(intent) -> Dictionary:
	var mode := _object_id(intent, "mfg_mode")
	if mode.is_empty():
		mode = "own_factory"
	var r: Dictionary = host.found_factory(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法开办工厂（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你开办了工厂，经营模式：%s。" % _mfg_mode_name(String(r.get("mode", mode)))], 0, "")

func _mfg_hire(intent) -> Dictionary:
	var role := _object_id(intent, "mfg_role")
	var count: int = _param_number(intent, "number", 1)
	var r: Dictionary = host.mfg_hire(role, count)
	if not bool(r.get("ok", false)):
		return _fail("无法招工（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你招入 %d 名%s。" % [int(r.get("hired", count)), _mfg_role_name(role)]], 0, "")

func _mfg_purchase(intent) -> Dictionary:
	var material := _object_id(intent, "mfg_material")
	var qty: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.mfg_purchase(material, qty)
	if not bool(r.get("ok", false)):
		return _fail("无法采购原料（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["采购%s %.1f 单位，花费 %d。" % [material, float(r.get("delivered", 0.0)), int(r.get("cost", 0))]], 0, "")

func _mfg_produce(intent) -> Dictionary:
	var recipe := _object_id(intent, "mfg_recipe")
	var batches: float = float(_param_number(intent, "number", 1))
	var r: Dictionary = host.mfg_produce(recipe, batches)
	if not bool(r.get("ok", false)):
		return _fail("无法生产（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["生产%s，良品 %.1f（良品率 %.0f%%）。" % [_mfg_recipe_name(recipe), float(r.get("good_output", 0.0)), float(r.get("quality_yield", 0.0)) * 100.0]], 0, "")

func _mfg_export(intent) -> Dictionary:
	var recipe := _object_id(intent, "mfg_recipe")
	var qty: float = float(_param_number(intent, "number", 1))
	var r: Dictionary = host.mfg_export(recipe, qty)
	if not bool(r.get("ok", false)):
		return _fail("无法成品出口（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["成品出口单据 #%d：%s %.1f 件，货值 %d，吨位 %.2f。" % [
		int(r.get("index", 0)), String(r.get("goods", "")), float(r.get("quantity", 0.0)),
		int(r.get("goods_value", 0)), float(r.get("quantity_ton", 0.0))]], 0, "")

func _mfg_order(intent) -> Dictionary:
	var recipe := _object_id(intent, "mfg_recipe")
	var qty: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.mfg_accept_order(recipe, qty)
	if not bool(r.get("ok", false)):
		return _fail("无法接单（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["承接%s订单 %d 件。" % [_mfg_recipe_name(recipe), int(qty)]], 0, "")

func _mfg_deliver(intent) -> Dictionary:
	var index: int = _param_number(intent, "number", 0)
	var r: Dictionary = host.mfg_deliver_order(index)
	if not bool(r.get("ok", false)):
		return _fail("无法交付订单（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["交付 %.1f 件，结算收入 %d。" % [float(r.get("delivered", 0.0)), int(r.get("revenue", 0))]], 0, "")

func _mfg_mode(intent) -> Dictionary:
	var mode := _object_id(intent, "mfg_mode")
	var r: Dictionary = host.mfg_set_mode(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法切换经营模式（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["经营模式改为%s。" % _mfg_mode_name(mode)], 0, "")

func _mfg_role_name(role: String) -> String:
	return String(host.manufacturing.ROLES.get(role, {}).get("name", role))

func _mfg_mode_name(mode: String) -> String:
	return String(host.manufacturing.MODES.get(mode, {}).get("name", mode))

func _mfg_recipe_name(recipe: String) -> String:
	return String(host.manufacturing.recipe_def(recipe).get("name", recipe))

func _param_number(intent, key: String, default: int) -> int:
	if intent.params is Dictionary and (intent.params as Dictionary).has(key):
		return int((intent.params as Dictionary).get(key, default))
	return default

# --- 科研流程与成果转化（D5 / R45.4-5） ---

func _research_start(intent) -> Dictionary:
	var topic: String = String(intent.params.get("method", "")).strip_edges()
	if topic.is_empty():
		return _fail("请给出研究课题。")
	var r: Dictionary = host.research_start(topic)
	if not bool(r.get("ok", false)):
		return _fail("无法立项（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["科研立项：%s，已付启动经费 %d。" % [topic, int(r.get("spent", 0))]], 0, "")

func _research_advance(intent) -> Dictionary:
	var r: Dictionary = host.research_advance()
	if not bool(r.get("ok", false)):
		return _fail("无法推进科研（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["科研推进到 %s，成果质量 %.1f。" % [String(r.get("stage", "")), float(r.get("quality", 0.0))]], 0, "")

func _research_collect(intent) -> Dictionary:
	var r: Dictionary = host.research_collect()
	if not bool(r.get("ok", false)):
		return _fail("无法结算成果（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["成果发表：引用 %d，声望 %.1f，收入 %d。" % [
		int(r.get("citations", 0)), float(r.get("prestige", 0.0)), int(r.get("income", 0))]], 0, "")

func _research_patent(intent) -> Dictionary:
	var r: Dictionary = host.research_file_patent()
	if not bool(r.get("ok", false)):
		return _fail("无法申请专利（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["专利已登记，知识产权 %s，登记费 %d。" % [
		String((r.get("ip", {}) as Dictionary).get("id", "")), int(r.get("fee", 0))]], 0, "")

func _research_fund(intent) -> Dictionary:
	var amount: int = _param_number(intent, "amount", 100000)
	var r: Dictionary = host.research_fund(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法注入科研经费（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["科研经费余额 %d。" % int(r.get("funding", 0))], 0, "")

# --- 国际贸易、海关与物流（D27） ---

func _export_shipment(intent) -> Dictionary:
	var goods: String = String(intent.params.get("method", "")).strip_edges()
	if goods.is_empty():
		goods = "货物"
	var value: int = _param_number(intent, "amount", 50000)
	var r: Dictionary = host.export_shipment(goods, value)
	if not bool(r.get("ok", false)):
		return _fail("无法建立出口单据（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["建立出口单据 #%d：%s，货值 %d。" % [int(r.get("index", 0)), String(r.get("goods", goods)), int(r.get("goods_value", value))]], 0, "")

func _plan_transport(intent) -> Dictionary:
	var mode := _object_id(intent, "trade_mode")
	var r: Dictionary = host.plan_trade_transport(-1, mode)
	if not bool(r.get("ok", false)):
		return _fail("无法规划运输（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["规划%s，运费 %d，预计 %d 天。" % [_trade_mode_name(mode), int(r.get("freight", 0)), int(r.get("days", 0.0))]], 0, "")

func _sign_trade(intent) -> Dictionary:
	var incoterm := _object_id(intent, "trade_incoterm")
	var r: Dictionary = host.sign_trade_contract(-1, incoterm)
	if not bool(r.get("ok", false)):
		return _fail("无法签订外贸合同（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["按 %s 签订外贸合同，结算方式 %s。" % [String(r.get("incoterm", incoterm)), String(r.get("settlement_name", ""))]], 0, "")

func _declare_shipment(intent) -> Dictionary:
	var r: Dictionary = host.declare_shipment(-1)
	if not bool(r.get("ok", false)):
		return _fail("无法报关（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["报关完成：关税 %d，增值税 %d，落地成本 %d。" % [int(r.get("tariff", 0)), int(r.get("vat", 0)), int(r.get("landed_cost", 0))]], 0, "")

func _clear_shipment(intent) -> Dictionary:
	var r: Dictionary = host.clear_shipment(-1)
	if not bool(r.get("ok", false)):
		return _fail("无法清关（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["清关完成。"], 0, "")

func _deliver_shipment(intent) -> Dictionary:
	var r: Dictionary = host.deliver_shipment(-1)
	if not bool(r.get("ok", false)):
		return _fail("无法交付（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["外贸交付完成，出口收入 %d。" % int(r.get("revenue", 0))], 0, "")

func _settle_shipment(intent) -> Dictionary:
	var r: Dictionary = host.settle_shipment(-1)
	if not bool(r.get("ok", false)):
		return _fail("无法结汇（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["按%s结汇，手续费 %d。" % [String(r.get("method_name", "")), int(r.get("fee", 0))]], 0, "")

func _trade_barrier(intent) -> Dictionary:
	var barrier := _object_id(intent, "trade_barrier")
	if barrier.is_empty():
		return _fail("未指定壁垒；可选加征关税、配额、反倾销或原产地。")
	var r: Dictionary = host.apply_trade_barrier(-1, barrier)
	if not bool(r.get("ok", false)):
		return _fail("无法施加贸易壁垒（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已施加%s壁垒。" % _trade_barrier_name(barrier)], 0, "")

func _trade_risk(intent) -> Dictionary:
	var event := _object_id(intent, "trade_risk")
	if event.is_empty():
		return _fail("未指定风险事件；可选贸易战、制裁或战争。")
	var r: Dictionary = host.apply_trade_risk(-1, event)
	if not bool(r.get("ok", false)):
		return _fail("无法触发外贸风险（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["遭遇%s：滞留 %.1f 天，额外费用 %d。" % [_trade_risk_name(event), float(r.get("delay_days", 0.0)), int(r.get("extra_cost", 0))]], 0, "")

func _trade_inspect(_intent) -> Dictionary:
	var r: Dictionary = host.inspect_shipment(-1, true)
	if not bool(r.get("ok", false)):
		return _fail("无法检验检疫（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["检验检疫合格，进入下一环节。" if bool(r.get("passed", true)) else "检验检疫不合格，需退运或整改。"], 0, "")

func _trade_damage(intent) -> Dictionary:
	var rate: float = float(_param_number(intent, "number", 5)) / 100.0
	var r: Dictionary = host.damage_shipment(-1, rate)
	if not bool(r.get("ok", false)):
		return _fail("无法登记货损（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["货损 %.0f%%，损失 %d，剩余货值 %d。" % [rate * 100.0, int(r.get("loss", 0)), int(r.get("remaining_value", 0))]], 0, "")

func _trade_return(_intent) -> Dictionary:
	var r: Dictionary = host.return_shipment(-1)
	if not bool(r.get("ok", false)):
		return _fail("无法退运（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已退运，退运成本 %d。" % int(r.get("return_cost", 0))], 0, "")

func _trade_barrier_name(key: String) -> String:
	const NAMES: Dictionary = {"tariff": "加征关税", "quota": "配额", "anti_dumping": "反倾销", "origin": "原产地"}
	return String(NAMES.get(key, key))

func _trade_risk_name(key: String) -> String:
	const NAMES: Dictionary = {"trade_war": "贸易战", "sanction": "制裁", "war": "战争"}
	return String(NAMES.get(key, key))

func _trade_mode_name(mode: String) -> String:
	return String(host.trade.TRANSPORT_MODES.get(mode, {}).get("name", mode))

# --- 矿业、能源与资源（D28） ---

func _open_mine(intent) -> Dictionary:
	var mineral := _object_id(intent, "mineral")
	var r: Dictionary = host.open_mine(mineral)
	if not bool(r.get("ok", false)):
		return _fail("无法开办矿场（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你开办了%s矿场。" % String(r.get("name", mineral))], 0, "")

func _acquire_mine_concession(intent) -> Dictionary:
	var r: Dictionary = host.acquire_mine_concession()
	if not bool(r.get("ok", false)):
		return _fail("无法取得矿权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你取得了矿权特许经营资格。"], 0, "")

func _explore_mine(intent) -> Dictionary:
	var budget: int = _param_number(intent, "amount", 1000000)
	var r: Dictionary = host.explore_mine(budget)
	if not bool(r.get("ok", false)):
		return _fail("无法勘探（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["勘探完成：储量 %.0f，品位 %.2f。" % [float(r.get("reserve", 0.0)), float(r.get("grade", 0.0))]], 0, "")

func _extract_ore(intent) -> Dictionary:
	var amount: float = float(_param_number(intent, "number", 1000))
	var r: Dictionary = host.extract_ore(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法开采（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["开采矿石 %.1f，剩余储量 %.0f。" % [float(r.get("ore", 0.0)), float(r.get("reserve", 0.0))]], 0, "")

func _smelt_ore(intent) -> Dictionary:
	var amount: float = float(_param_number(intent, "number", 1000))
	var r: Dictionary = host.smelt_ore(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法冶炼（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["冶炼出金属 %.1f（品位 %.2f）。" % [float(r.get("metal", 0.0)), float(r.get("grade", 0.0))]], 0, "")

func _sell_metal(intent) -> Dictionary:
	var amount: float = float(_param_number(intent, "number", 1000))
	var r: Dictionary = host.sell_metal(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法出售金属（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["售出 %.1f，单价 %d，收入 %d。" % [float(r.get("sold", 0.0)), int(r.get("unit_price", 0)), int(r.get("revenue", 0))]], 0, "")

func _mining_city_decline(intent) -> Dictionary:
	var r: Dictionary = host.mining_city_decline()
	if not bool(r.get("ok", false)):
		return _fail("无法评估资源城市衰退（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["资源衰退：人口减少 %d，衰退度 %.2f，失业率 %.2f，PMI %.1f。" % [
		int(r.get("population_loss", 0)), float(r.get("decline", 0.0)),
		float((r.get("macro", {}) as Dictionary).get("unemployment", 0.0)),
		float((r.get("macro", {}) as Dictionary).get("pmi", 0.0))]], 0, "")

func _mining_strategic_control(intent) -> Dictionary:
	var level: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var resource: String = String(intent.get("target", "oil"))
	var r: Dictionary = host.mining_strategic_control(resource, level)
	if not bool(r.get("ok", false)):
		return _fail("无法设定战略管制（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["战略资源 %s 管制比例 %.0f%%，可交易比例 %.0f%%。" % [resource, level * 100.0, float(r.get("tradable_ratio", 0.0)) * 100.0]], 0, "")

func _mining_stockpile(intent) -> Dictionary:
	var amount: float = float(_param_number(intent, "number", 100))
	var resource: String = String(intent.get("target", "oil"))
	var r: Dictionary = host.mining_stockpile(resource, amount)
	if not bool(r.get("ok", false)):
		return _fail("无法增加资源储备（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["战略资源 %s 储备 %.1f，可交易比例 %.0f%%。" % [resource, float(r.get("stockpile", 0.0)), float(r.get("tradable_ratio", 0.0)) * 100.0]], 0, "")

func _build_energy_project(intent) -> Dictionary:
	var kind := _object_id(intent, "energy_kind")
	var capacity: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.build_energy_project(kind, capacity)
	if not bool(r.get("ok", false)):
		return _fail("无法建设能源项目（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["建成%s，装机 %.1f。" % [String(r.get("name", kind)), float(r.get("capacity", 0.0))]], 0, "")

func _mine_safety(intent) -> Dictionary:
	var amount: int = _param_number(intent, "amount", 1000000)
	var r: Dictionary = host.invest_mine_safety(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法追加安全投入（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["安全投入后安全水平 %.2f。" % float(r.get("safety", 0.0))], 0, "")

func _mine_accident(_intent) -> Dictionary:
	var r: Dictionary = host.check_mine_accident()
	if not bool(r.get("ok", false)):
		return _fail("无法进行矿难判定（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("occurred", false)):
		return _ok(["本次巡检未发生矿难，安全水平 %.2f。" % float(r.get("safety", 0.0))], 0, "")
	return _ok(["发生%s：伤 %d 人，罚款 %d，健康受损。" % [String(r.get("kind_name", "")), int(r.get("injured", 0)), int(r.get("fine", 0))]], 0, "")

func _energy_futures(intent) -> Dictionary:
	var energy := _object_id(intent, "energy_type")
	if energy.is_empty():
		return _fail("未指定能源品种。")
	var amount: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.buy_energy_futures(energy, amount, 0)
	if not bool(r.get("ok", false)):
		return _fail("无法建立能源期货（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["建立%s期货 %.1f，锁价 %d。" % [_energy_name(energy), amount, int((r.get("contract", {}) as Dictionary).get("lock_price", 0))]], 0, "")

func _energy_settle(intent) -> Dictionary:
	var energy := _object_id(intent, "energy_type")
	if energy.is_empty():
		return _fail("未指定能源品种。")
	var r: Dictionary = host.settle_energy_futures(energy, -1)
	if not bool(r.get("ok", false)):
		return _fail("无法结算能源期货（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["结算%s期货，盈亏 %+d。" % [_energy_name(energy), int(r.get("pnl", 0))]], 0, "")

func _energy_contract(intent) -> Dictionary:
	var energy := _object_id(intent, "energy_type")
	if energy.is_empty():
		return _fail("未指定能源品种。")
	var amount: float = float(_param_number(intent, "number", 1000))
	var r: Dictionary = host.sign_energy_contract(energy, amount, 0, 1.0)
	if not bool(r.get("ok", false)):
		return _fail("无法签订能源长约（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["签订%s长约 %.1f。" % [_energy_name(energy), amount]], 0, "")

func _energy_name(key: String) -> String:
	return String(host.mining_energy.ENERGY_TYPES.get(key, {}).get("name", key))

# --- 农林牧渔深化（D29） ---

func _new_fishery(intent) -> Dictionary:
	var r: Dictionary = host.new_fishery()
	if not bool(r.get("ok", false)):
		return _fail("无法开办渔场（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你开办了渔场，拥有 %d 艘渔船。" % int(r.get("boats", 0))], 0, "")

func _fish_catch(intent) -> Dictionary:
	var species := _object_id(intent, "fish_species")
	var amount: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.fish_catch(species, amount)
	if not bool(r.get("ok", false)):
		return _fail("无法捕鱼（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["捕捞%s %.1f，资源比例 %.2f。" % [_fish_species_name(species), float(r.get("caught", 0.0)), float(r.get("resource_ratio", 1.0))]], 0, "")

func _start_closed_season(intent) -> Dictionary:
	var r: Dictionary = host.start_closed_season()
	if not bool(r.get("ok", false)):
		return _fail("无法进入休渔（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["进入休渔期，持续 %.0f 天。" % float(r.get("closed_days_left", 0.0))], 0, "")

func _new_forest(intent) -> Dictionary:
	var ftype := _object_id(intent, "forest_type")
	var r: Dictionary = host.new_forest(ftype)
	if not bool(r.get("ok", false)):
		return _fail("无法承包林场（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你承包了%s。" % String(r.get("name", ftype))], 0, "")

func _log_trees(intent) -> Dictionary:
	var amount: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.log_trees(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法采伐（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["采伐林木 %.0f，入库木材 %.1f。" % [float(r.get("logged", 0.0)), float(r.get("timber", 0.0))]], 0, "")

func _reforest(intent) -> Dictionary:
	var amount: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.reforest(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法造林（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["补植林木，现有 %.0f 株。" % float(r.get("trees", 0.0))], 0, "")

func _forest_carbon(intent) -> Dictionary:
	var years: float = maxf(0.0, float(_param_number(intent, "number", 1)))
	var r: Dictionary = host.forest_carbon_sink(years)
	if not bool(r.get("ok", false)):
		return _fail("无法核证林业碳汇（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["核证碳汇 %.1f 吨，售出收入 %d。" % [float(r.get("credits", 0.0)), int(r.get("paid", 0))]], 0, "")

func _apply_hunting_license(intent) -> Dictionary:
	var r: Dictionary = host.apply_hunting_license()
	if not bool(r.get("ok", false)):
		return _fail("无法申请狩猎许可（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你取得了狩猎许可，缴纳 %d。" % int(r.get("fee", 0))], 0, "")

func _hunt(intent) -> Dictionary:
	var species := _object_id(intent, "game_species")
	var amount: float = float(_param_number(intent, "number", 1))
	var r: Dictionary = host.hunt(species, amount)
	if not bool(r.get("ok", false)):
		return _fail("无法狩猎（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("legal", true)):
		return _ok(["无证狩猎，被查获，通缉等级升至 %d。" % int((r.get("violation", {}) as Dictionary).get("wanted_level", 0))], 0, "")
	return _ok(["猎获%s %.1f，收入 %d。" % [_game_species_name(species), float(r.get("harvested", 0.0)), int(r.get("revenue", 0))]], 0, "")

func _fish_species_name(species: String) -> String:
	return String(host.primary_industry.FISH_SPECIES.get(species, {}).get("name", species))

func _game_species_name(species: String) -> String:
	return String(host.primary_industry.GAME_SPECIES.get(species, {}).get("name", species))

# --- 餐饮与食品工业（D30） ---

func _build_restaurant(intent) -> Dictionary:
	var r: Dictionary = host.open_restaurant()
	if not bool(r.get("ok", false)):
		return _fail("无法开办餐厅（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你开了一家%s。" % String(r.get("name", "餐厅"))], 0, "")

func _add_menu(intent) -> Dictionary:
	var recipe := _object_id(intent, "recipe")
	var r: Dictionary = host.restaurant_add_menu(recipe)
	if not bool(r.get("ok", false)):
		return _fail("无法加菜（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已将%s加入菜单。" % _recipe_name(recipe)], 0, "")

func _set_menu_price(intent) -> Dictionary:
	var recipe := _object_id(intent, "recipe")
	var price: int = int(_param_number(intent, "number", 0))
	var r: Dictionary = host.restaurant_set_price(recipe, price)
	if not bool(r.get("ok", false)):
		return _fail("无法定价（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已将%s定价为 %d。" % [_recipe_name(recipe), int(r.get("price", price))]], 0, "")

func _open_business(intent) -> Dictionary:
	var channel := _object_id(intent, "channel")
	if channel == "":
		channel = "dine_in"
	var r: Dictionary = host.restaurant_sell_day(channel)
	if not bool(r.get("ok", false)):
		return _fail("无法营业（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["%s营业：客流 %.0f，营收 %d，利润 %d。" % [String(r.get("channel_name", "")), float(r.get("covers", 0.0)), int(r.get("revenue", 0)), int(r.get("profit", 0))]], 0, "")

func _hire_chef(intent) -> Dictionary:
	var role := _object_id(intent, "staff_role")
	if role == "":
		role = "cook"
	var count: int = int(_param_number(intent, "number", 1))
	var r: Dictionary = host.restaurant_hire(role, count)
	if not bool(r.get("ok", false)):
		return _fail("无法雇佣（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已雇佣%s，现有 %d 人。" % [_staff_role_name(role), int(r.get("count", 0))]], 0, "")

func _expand_dining(intent) -> Dictionary:
	var mode := _object_id(intent, "dining_mode")
	var r: Dictionary = host.restaurant_expand(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法扩张（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["餐饮扩张为%s，门店 %d 家。" % [String(r.get("mode", mode)), int(r.get("stores", 1))]], 0, "")

func _certify_food(intent) -> Dictionary:
	var cert := _object_id(intent, "cert")
	var r: Dictionary = host.restaurant_certify(cert)
	if not bool(r.get("ok", false)):
		return _fail("无法认证（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已取得%s认证。" % String(r.get("certification", cert))], 0, "")

func _promote_food(intent) -> Dictionary:
	var kind := _object_id(intent, "marketing")
	var cost: int = int(_param_number(intent, "number", 200000))
	var r: Dictionary = host.restaurant_marketing(kind, cost)
	if not bool(r.get("ok", false)):
		return _fail("无法营销（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var extra := "（引发差评反噬）" if bool(r.get("backlash", false)) else ""
	return _ok(["营销系数提升至 %.2f%s。" % [float(r.get("marketing", 1.0)), extra]], 0, "")

func _process_food(intent) -> Dictionary:
	var recipe := _object_id(intent, "recipe")
	var qty: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.restaurant_process(recipe, qty)
	if not bool(r.get("ok", false)):
		return _fail("无法加工（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["加工%s，库存 %.1f。" % [_recipe_name(recipe), float(r.get("qty", 0.0))]], 0, "")

func _distribute_food(intent) -> Dictionary:
	var recipe := _object_id(intent, "recipe")
	var qty: float = float(_param_number(intent, "number", 100))
	var channel := _object_id(intent, "channel")
	if channel == "":
		channel = "retail"
	var r: Dictionary = host.restaurant_distribute(recipe, qty, channel)
	if not bool(r.get("ok", false)):
		return _fail("无法分销（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["分销%s %.1f，净收入 %d。" % [_recipe_name(recipe), float(r.get("sold", 0.0)), int(r.get("net", 0))]], 0, "")

func _supply_from_factory(intent) -> Dictionary:
	var recipe := _object_id(intent, "recipe")
	var qty: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.restaurant_industrial_supply(recipe, qty)
	if not bool(r.get("ok", false)):
		return _fail("无法由产线供餐（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["食品产线供餐%s %.1f，餐厅库存 %.1f。" % [_recipe_name(recipe), float(r.get("moved", 0.0)), float(r.get("restaurant_stock", 0.0))]], 0, "")

func _recipe_name(recipe: String) -> String:
	return String((host.dining.RECIPES.get(recipe, {}) as Dictionary).get("name", recipe))

func _staff_role_name(role: String) -> String:
	return String((host.dining.STAFF_ROLES.get(role, {}) as Dictionary).get("name", role))

# --- 时尚、设计与奢侈品（D31） ---

func _new_brand(intent) -> Dictionary:
	var positioning := _object_id(intent, "positioning")
	var r: Dictionary = host.new_brand(positioning)
	if not bool(r.get("ok", false)):
		return _fail("无法创立品牌（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你创立了%s品牌。" % String(r.get("name", ""))], 0, "")

func _fashion_design(intent) -> Dictionary:
	var discipline := _object_id(intent, "fashion_discipline")
	var r: Dictionary = host.fashion_design(discipline)
	if not bool(r.get("ok", false)):
		return _fail("无法创作（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["创作%s，评分 %.0f（%s）。" % [_discipline_name(discipline), float(r.get("score", 0.0)), String(r.get("grade", ""))]], 0, "")

func _fashion_week(intent) -> Dictionary:
	var season := _object_id(intent, "season")
	if season == "":
		season = "ss"
	var r: Dictionary = host.fashion_week(season)
	if not bool(r.get("ok", false)):
		return _fail("无法举办时装周（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["时装周平均分 %.0f，订单额 %d。" % [float(r.get("avg_score", 0.0)), int(r.get("orders", 0))]], 0, "")

func _fashion_collab(intent) -> Dictionary:
	var fame: float = float(_param_number(intent, "number", 60))
	var r: Dictionary = host.fashion_collab(fame)
	if not bool(r.get("ok", false)):
		return _fail("无法联名（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["联名热度 %.2f，收入 %d。" % [float(r.get("hype", 0.0)), int(r.get("revenue", 0))]], 0, "")

func _fashion_limited(intent) -> Dictionary:
	var item := _object_id(intent, "luxury_item")
	var qty: int = int(_param_number(intent, "number", 100))
	var r: Dictionary = host.fashion_limited_edition(item, qty)
	if not bool(r.get("ok", false)):
		return _fail("无法限量发售（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["限量发售%s %d 件，单价 %d。" % [_luxury_name(item), int(r.get("qty", 0)), int(r.get("price", 0))]], 0, "")

func _fashion_marketing(intent) -> Dictionary:
	var kind := _object_id(intent, "fashion_marketing")
	var cost: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.fashion_marketing(kind, cost)
	if not bool(r.get("ok", false)):
		return _fail("无法营销（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["品牌热度 %.1f。" % float(r.get("fame", 0.0))], 0, "")

func _fashion_renew(intent) -> Dictionary:
	var strategy := _object_id(intent, "renew_strategy")
	var cost: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.fashion_renew(strategy, cost)
	if not bool(r.get("ok", false)):
		return _fail("无法复兴品牌（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["品牌相关度 %.1f。" % float(r.get("relevance", 0.0))], 0, "")

func _fashion_inherit(intent) -> Dictionary:
	var heir: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.fashion_inherit(heir)
	if not bool(r.get("ok", false)):
		return _fail("无法传承品牌（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["品牌已传至第 %d 代，继承人 %s。" % [int(r.get("generation", 2)), String(r.get("heir", ""))]], 0, "")

func _fashion_counterfeit(intent) -> Dictionary:
	var loss: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.fashion_counterfeit(loss)
	if not bool(r.get("ok", false)):
		return _fail("无法结算仿品侵权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if r.has("lawsuit"):
		var suit: Dictionary = r.get("lawsuit", {})
		return _ok(["仿品造成损失 %d，已发起 IP 维权（胜诉 %s）。" % [int(r.get("loss", 0)), "是" if bool(suit.get("win", false)) else "否"]], 0, "")
	return _ok(["仿品造成损失 %d，品牌声誉下降。" % int(r.get("loss", 0))], 0, "")

func _fashion_resell(intent) -> Dictionary:
	var item := String(intent.params.get("luxury_item", ""))
	if item.is_empty():
		item = String(intent.params.get("method", ""))
	var cond: float = clampf(float(_param_number(intent, "number", 80)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.fashion_resell(item, cond)
	if not bool(r.get("ok", false)):
		return _fail("无法寄售（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["寄售成交，货款 %d。" % int(r.get("price", 0))], 0, "")

func _fashion_auction(intent) -> Dictionary:
	var item := String(intent.params.get("luxury_item", ""))
	if item.is_empty():
		item = String(intent.params.get("method", ""))
	var reserve: int = int(_param_number(intent, "number", 0))
	var r: Dictionary = host.fashion_auction(item, reserve)
	if not bool(r.get("ok", false)):
		return _fail("无法拍卖（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("sold", false)):
		return _ok(["拍卖流拍，保留价 %d。" % int(r.get("reserve", 0))], 0, "")
	return _ok(["拍卖成交，成交价 %d。" % int(r.get("price", 0))], 0, "")

func _fashion_authenticate(intent) -> Dictionary:
	var item := _object_id(intent, "luxury_item")
	var r: Dictionary = host.fashion_authenticate(item)
	if not bool(r.get("ok", false)):
		return _fail("无法鉴定（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["鉴定结果：%s（置信 %.2f）。" % [String(r.get("result", "")), float(r.get("confidence", 0.0))]], 0, "")

func _discipline_name(discipline: String) -> String:
	return String((host.fashion.DISCIPLINES.get(discipline, {}) as Dictionary).get("name", discipline))

func _luxury_name(item: String) -> String:
	return String((host.fashion.LUXURY_ITEMS.get(item, {}) as Dictionary).get("name", item))

func _start_sports_career(intent) -> Dictionary:
	var r: Dictionary = host.start_sports_career()
	if not bool(r.get("ok", false)):
		return _fail("无法开启运动生涯（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你加入了%s，签订职业合同，月薪 %d。" % [String(r.get("club", "")), int(r.get("wage", 0))]], 0, "")

func _sports_match(intent) -> Dictionary:
	var r: Dictionary = host.sports_play_match()
	if not bool(r.get("ok", false)):
		var reason := String(r.get("reason", ""))
		if reason == "banned":
			return _fail("你正处于禁赛期，无法出战。")
		return _fail("无法出战（%s）。" % _reason_cn(reason))
	return _ok(["比赛结束，%d:%d（%s）。" % [int(r.get("home_score", 0)), int(r.get("away_score", 0)), _sports_winner_text(String(r.get("winner", "")))]], 0, "")

func _sports_winner_text(winner: String) -> String:
	if winner == "draw":
		return "平局"
	return "胜者 %s" % winner

func _sports_transfer(intent) -> Dictionary:
	var fee: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.sports_transfer(fee)
	if not bool(r.get("ok", false)):
		return _fail("无法转会（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["转会完成，转会费 %d，经纪人佣金 %d。" % [int(r.get("fee", 0)), int(r.get("agent_fee", 0))]], 0, "")

func _sports_sponsorship(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 500000))
	var r: Dictionary = host.sports_sponsorship("", amount)
	if not bool(r.get("ok", false)):
		return _fail("无法签约代言（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["签订代言合同，金额 %d。" % amount], 0, "")

func _sports_rehab(intent) -> Dictionary:
	var days: float = float(_param_number(intent, "number", 30))
	var r: Dictionary = host.sports_rehab(days)
	if not bool(r.get("ok", false)):
		return _fail("无法康复（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("recovered", false)):
		return _ok(["伤病痊愈，状态恢复至 %.0f。" % float(r.get("form", 0.0))], 0, "")
	return _ok(["康复中，仍需 %d 天。" % int(ceil(float(r.get("remaining_days", 0.0))))], 0, "")

func _sports_doping_test(intent) -> Dictionary:
	var r: Dictionary = host.sports_doping_test()
	if not bool(r.get("ok", false)):
		return _fail("无法检测（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("positive", false)):
		return _ok(["药检阳性，禁赛 %d 天。" % int(r.get("ban_days", 0.0))], 0, "")
	return _ok(["药检结果阴性。"], 0, "")

func _sports_retire(intent) -> Dictionary:
	var r: Dictionary = host.sports_retire()
	if not bool(r.get("ok", false)):
		return _fail("无法退役（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你宣布退役，退役金 %d。" % int(r.get("pension", 0))], 0, "")

func _sports_national(intent) -> Dictionary:
	var nation: String = String(intent.params.get("method", "")).strip_edges()
	if nation.is_empty():
		nation = "中国"
	var r: Dictionary = host.sports_national_callup(nation)
	if not bool(r.get("ok", false)):
		return _fail("无法入选国家队（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你入选了%s国家队。" % nation], 0, "")

func _sports_national_camp(intent) -> Dictionary:
	var days: float = maxf(0.0, float(_param_number(intent, "number", 10)))
	var r: Dictionary = host.sports_national_camp(days)
	if not bool(r.get("ok", false)):
		return _fail("无法参加国家队集训（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["国家队集训 %.0f 天，状态 %0.1f → %0.1f。" % [days, float(r.get("form_before", 0.0)), float(r.get("form", 0.0))]], 0, "")

func _sports_tournament(intent) -> Dictionary:
	var competition := _object_id(intent, "competition")
	if competition.is_empty():
		competition = "world_cup"
	var r: Dictionary = host.sports_international_tournament(competition)
	if not bool(r.get("ok", false)):
		return _fail("无法参加国际赛事（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["%s冠军：%s，奖金 %d。" % [_competition_name(competition), String(r.get("champion", "")), int(r.get("reward", 0))]], 0, "")

func _sports_fans(_intent) -> Dictionary:
	var r: Dictionary = host.sports_fan_violence()
	if not bool(r.get("ok", false)):
		return _fail("无法处理球迷冲突（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["球迷冲突：罚款 %d，球迷降至 %d，声誉 %.0f。" % [int(r.get("fine", 0)), int(r.get("fans", 0)), float(r.get("reputation", 0.0))]], 0, "")

func _sports_referee(_intent) -> Dictionary:
	var r: Dictionary = host.sports_referee_controversy()
	if not bool(r.get("ok", false)):
		return _fail("无法发起裁判申诉（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["裁判争议已申诉，申诉费 %d。" % int(r.get("protest_fee", 0))], 0, "")

func _sports_academic(_intent) -> Dictionary:
	var r: Dictionary = host.sports_academic_conflict()
	if not bool(r.get("ok", false)):
		return _fail("无法评估学业冲突（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("conflict", false)):
		return _ok(["当前无在读学业，不存在学业冲突。"], 0, "")
	return _ok(["学业冲突：绩点 %.1f，%s。" % [float(r.get("gpa", 0.0)), "仍可继续" if bool(r.get("can_continue", true)) else "已退学"]], 0, "")

func _competition_name(key: String) -> String:
	return String(host.sports_industry.COMPETITIONS.get(key, {}).get("name", key))

func _start_event_career(intent) -> Dictionary:
	var role := _object_id(intent, "event_role")
	var r: Dictionary = host.start_event_career(role)
	if not bool(r.get("ok", false)):
		return _fail("无法开启活动策划生涯（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你成为%s（%d 级）。" % [String(r.get("role", "")), int(r.get("level", 1))]], 0, "")

func _events_new(intent) -> Dictionary:
	var event_type := _object_id(intent, "event_type")
	var r: Dictionary = host.events_new(event_type)
	if not bool(r.get("ok", false)):
		return _fail("无法筹办活动（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["开始筹办%s。" % String(r.get("name", ""))], 0, "")

func _events_rent_venue(intent) -> Dictionary:
	var cost: int = int(_param_number(intent, "number", 2000000))
	var r: Dictionary = host.events_rent_venue(cost)
	if not bool(r.get("ok", false)):
		return _fail("无法租赁场地（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["场地已租，容量 %d，费用 %d。" % [int(r.get("capacity", 0)), int(r.get("cost", 0))]], 0, "")

func _events_approval(intent) -> Dictionary:
	var r: Dictionary = host.events_approval()
	if not bool(r.get("ok", false)):
		return _fail("无法报批（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["报批通过，进入招商。"], 0, "")

func _events_sponsor(intent) -> Dictionary:
	var tier := _object_id(intent, "sponsor_tier")
	var r: Dictionary = host.events_sponsor(tier)
	if not bool(r.get("ok", false)):
		return _fail("无法招商（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["签下%s，入账 %d。" % [String(r.get("tier", "")), int(r.get("amount", 0))]], 0, "")

func _events_sell(intent) -> Dictionary:
	var qty: int = int(_param_number(intent, "number", 1000))
	var r: Dictionary = host.events_sell_tickets(qty)
	if not bool(r.get("ok", false)):
		return _fail("无法售票（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["售出 %d 张，票务收入 %d。" % [int(r.get("sold", 0)), int(r.get("revenue", 0))]], 0, "")

func _events_secondary(intent) -> Dictionary:
	var qty: int = int(_param_number(intent, "number", 500))
	var r: Dictionary = host.events_secondary_market(qty)
	if not bool(r.get("ok", false)):
		return _fail("无法进入二级市场（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var line := "二级市场成交 %d 张，溢价 %.2f，平台佣金 %d。" % [int(r.get("listed", 0)), float(r.get("premium", 1.0)), int(r.get("commission", 0))]
	if bool(r.get("regulatory_risk", false)):
		line += " 溢价过高，存在监管风险。"
	return _ok([line], 0, "")

func _events_security(intent) -> Dictionary:
	var level: float = float(_param_number(intent, "number", 60)) / 100.0
	var r: Dictionary = host.events_set_security(level)
	if not bool(r.get("ok", false)):
		return _fail("无法配置安保（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["安保等级 %.0f%%，费用 %d。" % [float(r.get("security_level", 0.0)) * 100.0, int(r.get("cost", 0))]], 0, "")

func _events_hold(intent) -> Dictionary:
	var r: Dictionary = host.events_hold()
	if not bool(r.get("ok", false)):
		return _fail("无法举办（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["活动举办，到场 %d 人，周边收入 %d，事故 %d 起。" % [int(r.get("attendance", 0)), int(r.get("merchandise", 0)), (r.get("incidents", []) as Array).size()]], 0, "")

func _events_sign_artist(intent) -> Dictionary:
	var name := String(intent.params.get("method", ""))
	var fame: float = clampf(float(_param_number(intent, "number", 50)), 0.0, 100.0)
	var r: Dictionary = host.events_sign_artist(name, fame)
	if not bool(r.get("ok", false)):
		return _fail("无法签约（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已签约艺人 %s，出场费 %d。" % [name, int(r.get("fee", 0))]], 0, "")

func _events_book_artist(intent) -> Dictionary:
	var name := String(intent.params.get("method", ""))
	var day: int = int(_param_number(intent, "number", 0))
	var r: Dictionary = host.events_book_artist(name, day)
	if not bool(r.get("ok", false)):
		return _fail("无法排期（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已排期 %s，出场费 %d。" % [String(r.get("artist", "")), int(r.get("fee", 0))]], 0, "")

func _events_review(intent) -> Dictionary:
	var r: Dictionary = host.events_review()
	if not bool(r.get("ok", false)):
		return _fail("无法复盘（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var line := "复盘：净利润 %d，上座率 %.0f%%，评级 %.0f。" % [int(r.get("profit", 0)), float(r.get("fill_rate", 0.0)) * 100.0, float(r.get("rating", 0.0))]
	if r.get("planner", null) is Dictionary and bool((r["planner"] as Dictionary).get("leveled", false)):
		line += " 策划等级提升至 %d。" % int((r["planner"] as Dictionary).get("level", 1))
	return _ok([line], 0, "")

func _honor_profile(intent) -> Dictionary:
	var achievement: float = float(_param_number(intent, "number", 60))
	var r: Dictionary = host.start_honor_profile(achievement)
	if not bool(r.get("ok", false)):
		return _fail("无法建立荣誉档案（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["建立荣誉档案，成就 %.0f。" % float(r.get("achievement", 0.0))], 0, "")

func _honor_nominate(intent) -> Dictionary:
	var award := _object_id(intent, "award")
	var r: Dictionary = host.honors_nominate(award)
	if not bool(r.get("ok", false)):
		return _fail("无法提名（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("eligible", false)):
		return _ok(["已提名%s。" % award], 0, "")
	return _ok(["成就不足，还差 %.0f。" % float(r.get("gap", 0.0))], 0, "")

func _honor_evaluate(intent) -> Dictionary:
	var award := _object_id(intent, "award")
	var r: Dictionary = host.honors_evaluate(award)
	if not bool(r.get("ok", false)):
		return _fail("无法评审（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["评审得分 %.2f（通过线 %.2f）——%s。" % [float(r.get("score", 0.0)), float(r.get("pass_line", 0.0)), ("通过" if bool(r.get("passed", false)) else "未通过")]], 0, "")

func _honor_panel_vote(intent) -> Dictionary:
	var award := _object_id(intent, "award")
	var r: Dictionary = host.honors_panel_vote(award)
	if not bool(r.get("ok", false)):
		return _fail("无法投票（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var winner: String = "本人" if bool(r.get("won", false)) else "竞争者"
	return _ok(["评委会投票完成，胜出：%s。" % winner], 0, "")

func _honor_pressure(intent) -> Dictionary:
	var intensity: float = clampf(float(_param_number(intent, "number", 30)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.honors_pressure(intensity)
	if not bool(r.get("ok", false)):
		return _fail("无法施压（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["舆论压力升至 %.0f%%。" % (float(r.get("political_pressure", 0.0)) * 100.0)], 0, "")

func _honor_award(intent) -> Dictionary:
	var award := _object_id(intent, "award")
	var r: Dictionary = host.honors_award(award)
	if not bool(r.get("ok", false)):
		return _fail("无法领奖（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("awarded", false)):
		return _ok(["未能获奖（%s）。" % _reason_cn(String(r.get("reason", "")))], 0, "")
	var line := "你获得了%s。" % String((r.get("honor", {}) as Dictionary).get("name", ""))
	if r.get("enshrined", null) is Dictionary:
		line += " 已入选名人堂。"
	return _ok([line], 0, "")

func _honor_buy(intent) -> Dictionary:
	var award := _object_id(intent, "award")
	var r: Dictionary = host.honors_buy(award)
	if not bool(r.get("ok", false)):
		return _fail("无法运作（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("awarded", false)):
		return _ok(["你运作获得了%s（此事暂无人知晓）。" % String((r.get("honor", {}) as Dictionary).get("name", ""))], 0, "")
	return _ok(["运作未果。"], 0, "")

func _honors_family_legacy(intent) -> Dictionary:
	var r: Dictionary = host.honors_family_legacy()
	if not bool(r.get("ok", false)):
		return _fail("无法读取家族荣誉。")
	var lines: Array = ["家族传承：%d 代，名人堂代际 %d，族谱 %d 人，家族事件 %d 条。" % [
		int(r.get("generations", 0)), (r.get("honored_generations", []) as Array).size(),
		int(r.get("lineage", 0)), int(r.get("family_events", 0))]]
	for s in r.get("stories", []):
		lines.append(String(s))
	return _ok(lines, 0, "")

func _honor_expose(intent) -> Dictionary:
	var r: Dictionary = host.honors_expose()
	if not bool(r.get("ok", false)):
		return _fail("无法揭露（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("exposed", false)):
		return _ok(["没有可揭露的黑幕。"], 0, "")
	return _ok(["黑幕曝光：声望 %d，撤销荣誉 %d 项。" % [int(r.get("reputation_delta", 0)), int(r.get("revoked_honors", 0))]], 0, "")

func _police_case(intent) -> Dictionary:
	var crime := _object_id(intent, "crime")
	var r: Dictionary = host.police_start_case(crime)
	if not bool(r.get("ok", false)):
		return _fail("无法立案（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已立案，案件进入勘查阶段。"], 0, "")

func _police_survey(intent) -> Dictionary:
	var r: Dictionary = host.police_survey()
	if not bool(r.get("ok", false)):
		return _fail("无法勘查（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["勘查完成，线索 %.2f。" % float(r.get("leads", 0.0))], 0, "")

func _police_collect(intent) -> Dictionary:
	var kind := _object_id(intent, "evidence_kind")
	var strength: float = float(_param_number(intent, "number", 30)) / 100.0
	var r: Dictionary = host.police_collect(kind, strength)
	if not bool(r.get("ok", false)):
		return _fail("无法取证（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已采集%s，证据强度 %.2f。" % [String(r.get("kind", "")), float(r.get("score", 0.0))]], 0, "")

func _police_warrant(intent) -> Dictionary:
	var r: Dictionary = host.police_warrant()
	if not bool(r.get("ok", false)):
		return _fail("无法申请搜查令（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["搜查令已获批。" if bool(r.get("granted", false)) else "搜查令未获批。"], 0, "")

func _police_interrogate(intent) -> Dictionary:
	var pressure: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.police_interrogate(pressure)
	if not bool(r.get("ok", false)):
		return _fail("无法审讯（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("confession", false)):
		return _ok(["取得供词%s。" % ("（逼供）" if bool(r.get("coercive", false)) else "")], 0, "")
	return _ok(["审讯未取得供词%s。" % ("（逼供）" if bool(r.get("coercive", false)) else "")], 0, "")

func _police_informant(intent) -> Dictionary:
	var r: Dictionary = host.police_informant()
	if not bool(r.get("ok", false)):
		return _fail("无法启用线人（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["线人情报%s，线索 %.2f。" % [("可靠" if bool(r.get("reliable", false)) else "存疑"), float(r.get("leads", 0.0))]], 0, "")

func _police_undercover(intent) -> Dictionary:
	var r: Dictionary = host.police_undercover()
	if not bool(r.get("ok", false)):
		return _fail("无法部署卧底（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _fail("卧底暴露，行动失败。")
	return _ok(["卧底成功取得证据。"], 0, "")

func _police_tech(intent) -> Dictionary:
	var r: Dictionary = host.police_tech()
	if not bool(r.get("ok", false)):
		return _fail("无法技术侦查（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["技术侦查取得电子证据。"], 0, "")

func _police_advance(intent) -> Dictionary:
	var r: Dictionary = host.police_advance()
	if not bool(r.get("ok", false)):
		return _fail("无法推进案件（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("terminal", false)):
		return _ok(["案件已终结（%s）。" % _reason_cn(String(r.get("reason", "")))], 0, "")
	if r.has("solved"):
		if bool(r.get("solved", false)):
			var line := "侦破成功（概率 %.2f）。" % float(r.get("probability", 0.0))
			if bool(r.get("wrongful", false)):
				line += " 但证据薄弱且存在逼供，恐为冤假错案。"
			return _ok([line], 0, "")
		return _ok(["侦破未果，案件转为冷案。"], 0, "")
	return _ok(["案件推进至新阶段。"], 0, "")

func _security_firm(intent) -> Dictionary:
	var name := String(intent.params.get("method", "安保公司"))
	var r: Dictionary = host.start_security_firm(name)
	if not bool(r.get("ok", false)):
		return _fail("无法开办安保公司（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["安保公司已开办。"], 0, "")

func _security_take(intent) -> Dictionary:
	var kind := _object_id(intent, "security_service")
	var r: Dictionary = host.security_take_contract(kind)
	if not bool(r.get("ok", false)):
		return _fail("无法承接业务（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var c: Dictionary = r.get("contract", {})
	return _ok(["承接%s，费用 %d%s。" % [String(c.get("name", "")), int(c.get("fee", 0)), ("（人手不足）" if bool(r.get("understaffed", false)) else "")]], 0, "")

func _security_resolve(intent) -> Dictionary:
	var r: Dictionary = host.security_resolve_contract()
	if not bool(r.get("ok", false)):
		return _fail("无法履约（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("failure", false)):
		return _fail("安保失职，赔偿 %d，声誉 %.2f。" % [int(r.get("liability", 0)), float(r.get("reputation", 0.0))])
	return _ok(["履约成功，收入 %d，声誉 %.2f。" % [int(r.get("payment", 0)), float(r.get("reputation", 0.0))]], 0, "")

func _emergency_new(intent) -> Dictionary:
	var type := _object_id(intent, "emergency_profession")
	var severity: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.emergency_new_incident(type, severity)
	if not bool(r.get("ok", false)):
		return _fail("无法接警（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已接警并建立事件档案。"], 0, "")

func _emergency_weather(intent) -> Dictionary:
	var r: Dictionary = host.emergency_weather_disaster()
	if not bool(r.get("ok", false)):
		return _fail("无法建立天气灾害事件（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var losses: Dictionary = r.get("facility_losses", {})
	return _ok(["%s灾害事件已建立，人身伤害 %.0f，设施受损 %d 类。" % [String(r.get("disaster_name", "")), float(r.get("injury", 0.0)), losses.size()]], 0, "")

func _emergency_dispatch(intent) -> Dictionary:
	var distance: float = float(_param_number(intent, "number", 5))
	var r: Dictionary = host.emergency_dispatch(distance)
	if not bool(r.get("ok", false)):
		return _fail("无法出警（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["出警，响应时间 %.1f 分钟。" % float(r.get("response_minutes", 0.0))], 0, "")

func _emergency_mutual_aid(intent) -> Dictionary:
	var distance: float = float(_param_number(intent, "number", 50))
	var r: Dictionary = host.emergency_mutual_aid(distance)
	if not bool(r.get("ok", false)):
		return _fail("无法调派增援（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["外区增援 %d 队抵达，耗时 %.0f 分钟，费用 %d。" % [int(r.get("teams", 0)), float(r.get("arrival_minutes", 0.0)), int(r.get("cost", 0))]], 0, "")

func _emergency_rescue(intent) -> Dictionary:
	var r: Dictionary = host.emergency_rescue()
	if not bool(r.get("ok", false)):
		return _fail("无法救援（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["救援结算：需救治 %d，死亡 %d，获救 %d。" % [int(r.get("injured", 0)), int(r.get("deaths", 0)), int(r.get("rescued", 0))]], 0, "")

func _emergency_secondary(intent) -> Dictionary:
	var r: Dictionary = host.emergency_secondary()
	if not bool(r.get("ok", false)):
		return _fail("无法处置二次事故（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("occurred", false)):
		return _fail("发生二次事故，救援人员伤亡 %d。" % int(r.get("responder_casualties", 0)))
	return _ok(["现场未发生二次事故。"], 0, "")

func _emergency_aftermath(intent) -> Dictionary:
	var r: Dictionary = host.emergency_aftermath()
	if not bool(r.get("ok", false)):
		return _fail("无法善后（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var line := "善后完成，心理创伤 %.2f。" % float(r.get("psych_trauma", 0.0))
	if String(r.get("fault", "")) != "":
		line += " 认定责任：%s，罚金 %d。" % [_reason_cn(String(r.get("fault", ""))), int(r.get("penalty", 0))]
	return _ok([line], 0, "")

func _volunteer_org(intent) -> Dictionary:
	var name := String(intent.params.get("method", "志愿救援队"))
	var r: Dictionary = host.start_volunteer_org(name)
	if not bool(r.get("ok", false)):
		return _fail("无法组建志愿队（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["志愿救援队已组建。"], 0, "")

func _volunteer_purchase(intent) -> Dictionary:
	var item := String(intent.params.get("method", "救援装备"))
	var cost: int = int(_param_number(intent, "number", 50000))
	var r: Dictionary = host.volunteer_purchase(item, cost)
	if not bool(r.get("ok", false)):
		return _fail("无法采购装备（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已采购装备，当前装备 %d。" % int(r.get("equipment", 0))], 0, "")

func _volunteer_recruit(intent) -> Dictionary:
	var count: int = int(_param_number(intent, "number", 5))
	var r: Dictionary = host.volunteer_recruit(count)
	if not bool(r.get("ok", false)):
		return _fail("无法招募志愿者（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已招募志愿者，当前 %d 人。" % int(r.get("volunteers", 0))], 0, "")

func _volunteer_maintain(intent) -> Dictionary:
	var cost: int = int(_param_number(intent, "number", 50000))
	var r: Dictionary = host.volunteer_maintain(cost)
	if not bool(r.get("ok", false)):
		return _fail("无法维护装备（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["装备维护完成，损耗降至 %.0f%%。" % (float(r.get("wear", 0.0)) * 100.0)], 0, "")

func _volunteer_dispatch(intent) -> Dictionary:
	var r: Dictionary = host.volunteer_dispatch_incident()
	if not bool(r.get("ok", false)):
		return _fail("无法志愿出警（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["志愿支援出警，响应时间 %.1f 分钟。" % float(r.get("response_minutes", 0.0))], 0, "")

func _env_garbage(intent) -> Dictionary:
	var rate: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.env_set_garbage_sorting(rate)
	if not bool(r.get("ok", false)):
		return _fail("无法设置垃圾分类（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["垃圾分类率设为 %.2f。" % float(r.get("garbage_sorting", 0.0))], 0, "")

func _env_recycle(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 1000))
	var r: Dictionary = host.env_recycle(float(amount))
	if not bool(r.get("ok", false)):
		return _fail("无法回收（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["回收 %.0f，填埋 %.0f。" % [float(r.get("recovered", 0.0)), float(r.get("landfill", 0.0))]], 0, "")

func _env_sewage(intent) -> Dictionary:
	var rate: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.env_treat_sewage(rate)
	if not bool(r.get("ok", false)):
		return _fail("无法治理污水（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["污水处理率设为 %.2f。" % float(r.get("sewage_treatment", 0.0))], 0, "")

func _env_air(intent) -> Dictionary:
	var investment: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.env_air_control(investment)
	if not bool(r.get("ok", false)):
		return _fail("无法空气治理（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["空气治理完成，空气质量 %.2f，污染 %.2f。" % [float(r.get("air_quality", 0.0)), float(r.get("pollution", 0.0))]], 0, "")

func _env_permit(intent) -> Dictionary:
	var source := String(intent.params.get("method", "factory"))
	var allowance: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.env_issue_permit(source, allowance)
	if not bool(r.get("ok", false)):
		return _fail("无法发放排污许可（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已发放排污许可，额度 %.0f。" % float(r.get("allowance", 0.0))], 0, "")

func _env_carbon_account(intent) -> Dictionary:
	var r: Dictionary = host.env_carbon_account()
	if not bool(r.get("ok", false)):
		return _fail("无法碳核算（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var esg: Dictionary = r.get("esg", {})
	return _ok(["碳平衡 %.1f，ESG %.1f（%s 级）。" % [float(r.get("balance", 0.0)), float(esg.get("score", 0.0)), String(esg.get("grade", ""))]], 0, "")

func _env_carbon_auction(intent) -> Dictionary:
	var credits: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.env_carbon_auction(credits, 160)
	if not bool(r.get("ok", false)):
		return _fail("无法参与碳拍卖（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if float(r.get("filled", 0.0)) <= 0.0:
		return _ok(["碳拍卖未成交，出清价 %d 高于申报价。" % int(r.get("clearing_price", 0))], 0, "")
	return _ok(["碳拍卖成交 %.1f 吨，出清价 %d，支付 %d。" % [float(r.get("filled", 0.0)), int(r.get("clearing_price", 0)), int(r.get("cost", 0))]], 0, "")

func _env_carbon_market(intent) -> Dictionary:
	var r: Dictionary = host.env_carbon_market()
	host.state.dirty = true
	if not bool(r.get("ok", false)):
		return _fail("碳市场撮合失败。")
	var trade: Dictionary = r.get("player_trade", {})
	if trade.is_empty():
		return _ok(["碳市场撮合完成，成交 %.1f 吨，均价 %.1f；本企业无成交。" % [float(r.get("volume", 0.0)), float(r.get("average_price", 0.0))]], 0, "")
	return _ok(["碳市场成交 %.1f 吨，价格 %.1f，现金流 %d。" % [float(trade.get("credits", 0.0)), float(trade.get("price", 0.0)), int(r.get("player_cash", 0))]], 0, "")

func _env_carbon_trade(intent) -> Dictionary:
	var credits: float = float(_param_number(intent, "number", 10))
	var r: Dictionary = host.env_carbon_trade(credits)
	if not bool(r.get("ok", false)):
		return _fail("无法碳交易（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["碳交易完成，信用 %.1f，现金 %d。" % [float(r.get("credits", 0.0)), int(r.get("cash", 0))]], 0, "")

func _env_carbon_compliance(intent) -> Dictionary:
	var mode := String(intent.params.get("method", "buy"))
	if mode not in ["buy", "fine"]:
		mode = "buy"
	var r: Dictionary = host.env_carbon_compliance(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法碳履约（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("compliant", false)):
		return _ok(["碳排合规，无需履约。"], 0, "")
	return _ok(["碳履约（%s），成本 %d。" % [String(r.get("action", "")), int(r.get("cost", 0))]], 0, "")

func _env_carbon_report(intent) -> Dictionary:
	var reported: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.env_report_carbon(reported)
	if not bool(r.get("ok", false)):
		return _fail("无法碳申报（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("detected", false)):
		return _fail("碳数据造假被查获。")
	return _ok(["碳申报完成%s。" % ("（低报，暂未查获）" if bool(r.get("understated", false)) else "")], 0, "")

func _env_org(intent) -> Dictionary:
	var kind := _object_id(intent, "env_career")
	var r: Dictionary = host.start_env_org(kind)
	if not bool(r.get("ok", false)):
		return _fail("无法开办环保组织（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["环保组织已开办。"], 0, "")

func _env_project(intent) -> Dictionary:
	var name := String(intent.params.get("method", "环保项目"))
	var budget: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.env_run_project(name, budget)
	if not bool(r.get("ok", false)):
		return _fail("无法承接环保项目（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["承接%s，利润 %d。" % [name, int(r.get("profit", 0))]], 0, "")

func _env_expose(intent) -> Dictionary:
	var r: Dictionary = host.env_expose_pollution()
	if not bool(r.get("ok", false)):
		return _fail("无法举报污染（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var line := "污染指数 %.2f，声誉变化 %d。" % [float(r.get("pollution_index", 0.0)), int(r.get("reputation_delta", 0))]
	if bool(r.get("lawsuit_open", false)):
		line += " 已触发环境诉讼。"
	return _ok([line], 0, "")

func _env_lawsuit(intent) -> Dictionary:
	var r: Dictionary = host.env_lawsuit()
	if not bool(r.get("ok", false)):
		return _fail("无法提起环境诉讼（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("liable", false)):
		return _ok(["环境诉讼胜诉，赔偿 %d。" % int(r.get("compensation", 0))], 0, "")
	return _ok(["环境诉讼未认定责任。"], 0, "")

func _env_subsidy(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 100000))
	var r: Dictionary = host.env_green_subsidy(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法申请绿色补贴（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("detected", false)):
		return _fail("绿色补贴骗补被查获。")
	return _ok(["绿色补贴到账 %d。" % int(r.get("granted", 0))], 0, "")

func _env_transition(intent) -> Dictionary:
	var investment: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.env_low_carbon_transition(investment)
	if not bool(r.get("ok", false)):
		return _fail("无法低碳转型（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["低碳转型，减排 %.1f，排放降至 %.1f。" % [float(r.get("emission_cut", 0.0)), float(r.get("emissions", 0.0))]], 0, "")

func _env_discharge(intent) -> Dictionary:
	var amount: float = float(_param_number(intent, "number", 50))
	var r: Dictionary = host.env_illegal_discharge(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法偷排（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("detected", false)):
		return _fail("偷排被查获，罚款 %d。" % int(r.get("fines", 0)))
	return _ok(["偷排完成（暂未查获）。"], 0, "")

func _env_nimby(intent) -> Dictionary:
	var scale: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.env_nimby(scale)
	if not bool(r.get("ok", false)):
		return _fail("无法邻避评估（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var line := "邻避反对度 %.2f，延期 %d 天。" % [float(r.get("opposition", 0.0)), int(r.get("delay_days", 0))]
	if bool(r.get("cancelled", false)):
		line += " 项目取消。"
	return _ok([line], 0, "")

func _municipal_maintain(intent) -> Dictionary:
	var facility := _object_id(intent, "municipal_facility")
	var amount: int = int(_param_number(intent, "number", 500000))
	var r: Dictionary = host.municipal_maintain(facility, amount)
	if not bool(r.get("ok", false)):
		return _fail("无法养护（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["养护完成，健康度 %.2f。" % float(r.get("condition", 0.0))], 0, "")

func _municipal_inspect(intent) -> Dictionary:
	var r: Dictionary = host.municipal_inspect()
	if not bool(r.get("ok", false)):
		return _fail("无法巡检（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["巡检完成，维护缺位公园 %d 处，未处理投诉 %d 件。" % [(r.get("neglected_parks", []) as Array).size(), int(r.get("unresolved_complaints", 0))]], 0, "")

func _municipal_construct(intent) -> Dictionary:
	var facility := _object_id(intent, "municipal_facility")
	var days: float = float(_param_number(intent, "number", 30))
	var r: Dictionary = host.municipal_construct(facility, days)
	if not bool(r.get("ok", false)):
		return _fail("无法施工（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["施工开始，工期 %.0f 天，通行系数 %.2f。" % [float(r.get("days_left", 0.0)), float(r.get("commute_factor", 1.0))]], 0, "")

func _municipal_advance(intent) -> Dictionary:
	var days: float = float(_param_number(intent, "number", 10))
	var r: Dictionary = host.municipal_advance_construction(days)
	if not bool(r.get("ok", false)):
		return _fail("无法推进施工（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["施工推进，完成 %d 处，通行系数 %.2f。" % [(r.get("completed", []) as Array).size(), float(r.get("commute_factor", 1.0))]], 0, "")

func _municipal_excavate(intent) -> Dictionary:
	var facility := _object_id(intent, "municipal_facility")
	var r: Dictionary = host.municipal_excavate(facility)
	if not bool(r.get("ok", false)):
		return _fail("无法开挖（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("repeated", false)):
		return _ok(["反复开挖（拉链路），额外成本 %d。" % int(r.get("extra_cost", 0))], 0, "")
	return _ok(["开挖登记完成。"], 0, "")

func _municipal_complain(intent) -> Dictionary:
	var source := String(intent.params.get("method", "扰民"))
	var r: Dictionary = host.municipal_complain(source)
	if not bool(r.get("ok", false)):
		return _fail("无法投诉（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["市政投诉已登记。"], 0, "")

func _municipal_resolve(intent) -> Dictionary:
	var index: int = int(_param_number(intent, "number", 0))
	var r: Dictionary = host.municipal_resolve_complaint(index)
	if not bool(r.get("ok", false)):
		return _fail("无法处理投诉（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["投诉已处理，扰民度 %.2f。" % float(r.get("nuisance", 0.0))], 0, "")

func _postal_accept(intent) -> Dictionary:
	var id := String(intent.params.get("method", "parcel"))
	var r: Dictionary = host.postal_accept(id, 1.0, 100.0)
	if not bool(r.get("ok", false)):
		return _fail("无法寄件（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已收寄，待处理 %d 件。" % int(r.get("pending", 0))], 0, "")

func _postal_ship(intent) -> Dictionary:
	var r: Dictionary = host.postal_ship()
	if not bool(r.get("ok", false)):
		return _fail("无法发运（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("lost", false)):
		return _fail("包裹丢失。")
	if bool(r.get("damaged", false)):
		return _ok(["包裹破损，预计 %d 天送达。" % int(r.get("expected_days", 0))], 0, "")
	return _ok(["包裹已发运，预计 %d 天送达。" % int(r.get("expected_days", 0))], 0, "")

func _postal_claim(intent) -> Dictionary:
	var r: Dictionary = host.postal_claim()
	if not bool(r.get("ok", false)):
		return _fail("无法理赔（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if int(r.get("paid", 0)) <= 0:
		return _ok(["无可理赔事项。"], 0, "")
	return _ok(["理赔到账 %d。" % int(r.get("paid", 0))], 0, "")

func _courier_career(intent) -> Dictionary:
	var r: Dictionary = host.start_courier_career()
	if not bool(r.get("ok", false)):
		return _fail("无法成为快递员（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你成为实习快递员。"], 0, "")

func _courier_deliver(intent) -> Dictionary:
	var r: Dictionary = host.courier_deliver()
	if not bool(r.get("ok", false)):
		return _fail("无法揽投（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["揽投完成，累计 %d 件%s。" % [int(r.get("deliveries", 0)), ("，晋升" if bool(r.get("promoted", false)) else "")]], 0, "")

func _municipal_franchise(intent) -> Dictionary:
	var service := _object_id(intent, "franchise_service")
	var r: Dictionary = host.municipal_grant_franchise(service)
	if not bool(r.get("ok", false)):
		return _fail("无法授予特许（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["特许经营合同已登记。"], 0, "")

func _municipal_quality(intent) -> Dictionary:
	var score: float = clampf(float(_param_number(intent, "number", 70)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.municipal_assess_quality(score)
	if not bool(r.get("ok", false)):
		return _fail("无法考核（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["服务考核 %s 级%s。" % [String(r.get("grade", "")), ("，扣减服务费 %d" % int(r.get("penalty", 0))) if int(r.get("penalty", 0)) > 0 else ""]], 0, "")

func _municipal_utility(intent) -> Dictionary:
	var days: float = float(_param_number(intent, "number", 30))
	var r: Dictionary = host.municipal_utility_report(days)
	if not bool(r.get("ok", false)):
		return _fail("无法生成公用事业报表（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["公用事业 %.0f 天：营收 %d，成本 %d，净利 %d。" % [float(r.get("days", 0.0)), int(r.get("revenue", 0)), int(r.get("cost", 0)), int(r.get("net", 0))]], 0, "")

func _municipal_purchase(intent) -> Dictionary:
	var service := _object_id(intent, "franchise_service")
	var budget: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.municipal_government_purchase(service, budget)
	if not bool(r.get("ok", false)):
		return _fail("无法政府购买（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["政府购买服务完成，预算 %d。" % int(r.get("budget", 0))], 0, "")

func _municipal_tender(intent) -> Dictionary:
	var project := String(intent.params.get("method", "市政工程"))
	var budget: int = int(_param_number(intent, "number", 10000000))
	var r: Dictionary = host.municipal_tender(project, budget)
	if not bool(r.get("ok", false)):
		return _fail("无法招标（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var c: Dictionary = r.get("contract", {})
	return _ok(["「%s」定标，成交 %d，得分 %.2f。" % [project, int(c.get("price", 0)), float(c.get("score", 0.0))]], 0, "")

func _municipal_hearing(intent) -> Dictionary:
	var project := String(intent.params.get("method", "市政工程"))
	var support: float = clampf(float(_param_number(intent, "number", 60)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.municipal_hearing(project, support)
	if not bool(r.get("ok", false)):
		return _fail("无法召开听证（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["「%s」听证%s，风险 %.2f。" % [project, ("通过" if bool(r.get("approved", false)) else "未通过"), float(r.get("risk", 0.0))]], 0, "")

func _debt_pawn(intent) -> Dictionary:
	var item := String(intent.params.get("method", ""))
	var amount: int = int(_param_number(intent, "number", 500000))
	var r: Dictionary = host.debt_pawn(item, amount, 0.12)
	if not bool(r.get("ok", false)):
		return _fail("无法典当（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["典当「%s」得 %d。" % [item, amount]], 0, "")

func _debt_redeem(intent) -> Dictionary:
	var r: Dictionary = host.debt_redeem()
	if not bool(r.get("ok", false)):
		return _fail("无法赎回（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["赎回「%s」完成。" % String(r.get("item", ""))], 0, "")

func _debt_borrow(intent) -> Dictionary:
	var business := _object_id(intent, "debt_business")
	var amount: int = int(_param_number(intent, "number", 500000))
	var r: Dictionary = host.debt_borrow(business, amount, 0.12)
	if not bool(r.get("ok", false)):
		return _fail("无法借贷（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("approved", false)):
		return _fail("借贷被拒（%s）。" % _reason_cn("credit_below_line"))
	var disb: Dictionary = r.get("disbursement", {})
	return _ok(["借贷获批，放款 %d。" % int(disb.get("amount", 0))], 0, "")

func _debt_lend(intent) -> Dictionary:
	var business := _object_id(intent, "debt_business")
	var amount: int = int(_param_number(intent, "number", 500000))
	var r: Dictionary = host.debt_lend(business, amount, 0.12)
	if not bool(r.get("ok", false)):
		return _fail("无法放贷（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var reg: Dictionary = r.get("regulation", {})
	if bool(reg.get("illegal", false)):
		return _ok(["放贷登记，但存在合规问题：%s。" % "、".join(PackedStringArray(reg.get("violations", [])))], 0, "")
	return _ok(["放贷登记完成。"], 0, "")

func _debt_ledger(intent) -> Dictionary:
	var r: Dictionary = host.debt_ledger()
	var lines: Array = ["借款 %d 笔，余额 %d；放贷 %d 笔，余额 %d。" % [
		int(r.get("borrow_count", 0)), int(r.get("borrow_outstanding", 0)),
		int(r.get("lend_count", 0)), int(r.get("lend_outstanding", 0))]]
	for row in r.get("loans", []):
		lines.append("借款 %s：%s，余额 %d，状态 %s。" % [String(row.get("business", "")), String(row.get("lender", "")), int(row.get("outstanding", 0)), String(row.get("status", ""))])
	return _ok(lines, 0, "")

func _debt_credit_report(intent) -> Dictionary:
	var r: Dictionary = host.debt_credit_report()
	if not bool(r.get("ok", false)):
		return _fail("无法生成征信报告。")
	return _ok(["征信评分 %.1f（%s），机构 %d 家，在贷 %d 笔，逾期 %d 笔，违约 %d 笔，负债余额 %d。" % [
		float(r.get("score", 0.0)), String(r.get("grade", "")), int(r.get("institutions", 0)),
		int(r.get("active_loans", 0)), int(r.get("overdue_loans", 0)),
		int(r.get("defaulted_loans", 0)), int(r.get("total_outstanding", 0))]], 0, "")

func _debt_repay(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 0))
	if amount <= 0:
		amount = 1 << 30
	var r: Dictionary = host.debt_repay(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法还款（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["还款 %d，剩余余额 %d，状态 %s。" % [int(r.get("paid", 0)), int(r.get("outstanding", 0)), String(r.get("status", ""))]], 0, "")

func _debt_credit(intent) -> Dictionary:
	var r: Dictionary = host.debt_assess_credit()
	if not bool(r.get("ok", false)):
		return _fail("无法评估信用（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["信用评估得分 %.0f，%s。" % [float(r.get("score", 0.0)), ("通过" if bool(r.get("approved", false)) else "不通过")]], 0, "")

func _debt_collect_legal(intent) -> Dictionary:
	return _debt_collect(intent, "reminder")

func _debt_collect_violence(intent) -> Dictionary:
	return _debt_collect(intent, "violence")

func _debt_collect(intent, mode: String) -> Dictionary:
	var r: Dictionary = host.debt_collect(mode)
	if not bool(r.get("ok", false)):
		return _fail("无法催收（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("illegal", false)):
		return _ok(["合法催收完成，可追偿 %d。" % int(r.get("recoverable", 0))], 0, "")
	var harm := String(r.get("victim_harm", "none"))
	return _fail("灰色催收违法（%s），法律后果：%s。" % [harm, String(r.get("legal_consequence", ""))])

func _debt_restructure(intent) -> Dictionary:
	var r: Dictionary = host.debt_restructure()
	if not bool(r.get("ok", false)):
		return _fail("无法重组（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["债务重组完成，剩余本金 %d。" % int(r.get("outstanding", 0))], 0, "")

func _debt_bankruptcy(intent) -> Dictionary:
	var r: Dictionary = host.debt_bankruptcy()
	if not bool(r.get("ok", false)):
		return _fail("无法破产（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["个人破产生效，核销 %d。" % int(r.get("discharged", 0))], 0, "")

func _debt_predatory(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 500000))
	var r: Dictionary = host.debt_predatory(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法办理套路贷（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("predatory", false)):
		return _ok(["不构成套路贷。"], 0, "")
	return _fail("套路贷成立，虚增后债务 %d。" % int(r.get("outstanding", 0)))

func _debt_fundraise(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 1000000))
	var r: Dictionary = host.debt_illegal_fundraising(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法集资（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("illegal", false)):
		return _fail("非法集资成立，构成刑事违法。")
	return _ok(["集资合规。"], 0, "")

func _debt_abscond(intent) -> Dictionary:
	var r: Dictionary = host.debt_abscond()
	if not bool(r.get("ok", false)):
		return _fail("无法跑路（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你跑路了，%s。" % ("仍被追回" if bool(r.get("recovered", false)) else "暂未被追回")], 0, "")

func _consumer_order(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 100000))
	var category := String(intent.params.get("method", "general"))
	var r: Dictionary = host.consumer_new_order(amount, category, false, false)
	if not bool(r.get("ok", false)):
		return _fail("无法下单（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["消费订单已登记，金额 %d。" % amount], 0, "")

func _consumer_return(intent) -> Dictionary:
	var days: int = int(_param_number(intent, "number", 1))
	var r: Dictionary = host.consumer_return(days, "no_reason")
	if not bool(r.get("ok", false)):
		return _fail("无法退货（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("accepted", false)):
		return _fail("退货被拒（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["退货受理，退款 %d。" % int(r.get("refund", 0))], 0, "")

func _consumer_three(intent) -> Dictionary:
	var repairs: int = int(_param_number(intent, "number", 2))
	var r: Dictionary = host.consumer_three_guarantee(repairs)
	if not bool(r.get("ok", false)):
		return _fail("无法三包（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("eligible", false)):
		return _fail("三包不成立（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["三包退换成立，退款 %d。" % int(r.get("refund", 0))], 0, "")

func _consumer_warranty(intent) -> Dictionary:
	var days: int = int(_param_number(intent, "number", 30))
	var r: Dictionary = host.consumer_warranty(days)
	if not bool(r.get("ok", false)):
		return _fail("无法保修（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("covered", false)):
		return _ok(["质保期内免费维修。"], 0, "")
	return _ok(["超出质保，维修费 %d。" % int(r.get("fee", 0))], 0, "")

func _consumer_burden(intent) -> Dictionary:
	var days: int = int(_param_number(intent, "number", 30))
	var r: Dictionary = host.consumer_burden(days)
	if not bool(r.get("ok", false)):
		return _fail("无法举证（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["举证责任在%s。" % ("商家" if String(r.get("bearer", "")) == "merchant" else "消费者")], 0, "")

func _consumer_dispute_negotiate(intent) -> Dictionary:
	return _consumer_dispute(intent, "negotiate", 0.3)

func _consumer_platform(intent) -> Dictionary:
	return _consumer_dispute(intent, "platform", 0.4)

func _consumer_association(intent) -> Dictionary:
	return _consumer_dispute(intent, "consumer_association", 0.5)

func _consumer_dispute(intent, channel: String, evidence: float) -> Dictionary:
	var r: Dictionary = host.consumer_dispute(channel, evidence)
	if not bool(r.get("ok", false)):
		return _fail("无法维权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("success", false)):
		return _ok(["维权成功，获赔 %d。" % int(r.get("compensation", 0))], 0, "")
	return _fail("维权未获支持。")

func _consumer_sue(intent) -> Dictionary:
	var r: Dictionary = host.consumer_sue(0.5)
	if not bool(r.get("ok", false)):
		return _fail("无法起诉（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var claim: Dictionary = r.get("claim", {})
	return _ok(["消费纠纷已立案，标的 %d，案号 %s。" % [
		int(claim.get("amount", 0)), String(r.get("case_id", ""))]], 0, "")

func _civil_litigate(intent) -> Dictionary:
	var r: Dictionary = host.civil_litigate()
	if not bool(r.get("ok", false)):
		return _fail("无法开庭（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var j: Dictionary = r.get("judgment", {})
	if bool(j.get("won", false)):
		return _ok(["胜诉，判赔 %d。" % int(j.get("award", 0))], 0, "")
	return _fail("败诉，未获判赔。")

func _civil_appeal(intent) -> Dictionary:
	var r: Dictionary = host.civil_appeal()
	if not bool(r.get("ok", false)):
		return _fail("无法上诉（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("overturned", false)):
		return _ok(["二审改判，追加判赔 %d。" % int(r.get("delta", 0))], 0, "")
	return _fail("二审维持原判。")

func _civil_enforce(intent) -> Dictionary:
	var r: Dictionary = host.civil_enforce()
	if not bool(r.get("ok", false)):
		return _fail("无法执行（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("execution_failure", false)):
		return _ok(["执行不能，已回收 %d，未清偿 %d。" % [int(r.get("recovered", 0)), int(r.get("outstanding", 0))]], 0, "")
	return _ok(["执行到位 %d。" % int(r.get("recovered", 0))], 0, "")

func _crime_attempt(intent) -> Dictionary:
	var crime: String = _object_id(intent, "crime")
	if crime.is_empty():
		crime = String(intent.params.get("method", "")).strip_edges()
	if crime.is_empty():
		return _fail("请指明罪名。")
	var r: Dictionary = host.crime_attempt(crime)
	if not bool(r.get("ok", false)):
		return _fail("无法实施犯罪（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var name: String = String(r.get("name", crime))
	if bool(r.get("success", false)):
		if bool(r.get("detected", false)):
			return _ok(["%s得手，但被察觉，通缉等级 %d。" % [name, int(r.get("wanted_level", 0))]], 0, "")
		return _ok(["%s得手，未被察觉。" % name], 0, "")
	if bool(r.get("detected", false)):
		return _ok(["%s未遂并被察觉，通缉等级 %d。" % [name, int(r.get("wanted_level", 0))]], 0, "")
	return _ok(["%s未遂，且未被察觉。" % name], 0, "")


func _crime_trial(intent) -> Dictionary:
	var r: Dictionary = host.crime_trial()
	if not bool(r.get("ok", false)):
		return _fail("无法受审（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("convicted", false)):
		return _ok(["证据不足，宣告无罪，通缉解除。"], 0, "")
	var fine: int = int(r.get("fine", 0))
	var days: int = int(r.get("days", 0))
	if days > 0:
		return _ok(["定罪：%s，判处 %d 日，罚金 %d，已入监。" % [String(r.get("name", "")), days, fine]], 0, "")
	return _ok(["定罪：%s，罚金 %d，免予监禁。" % [String(r.get("name", "")), fine]], 0, "")


func _crime_appeal(intent) -> Dictionary:
	var r: Dictionary = host.crime_appeal()
	if not bool(r.get("ok", false)):
		return _fail("无法上诉（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("acquitted", false)):
		return _ok(["二审改判无罪，罚金退还 %d。" % int(r.get("refund", 0))], 0, "")
	return _ok(["二审维持原判。"], 0, "")

func _crime_surrender(intent) -> Dictionary:
	var r: Dictionary = host.crime_self_surrender()
	if not bool(r.get("ok", false)):
		return _fail("无法自首（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已自首，通缉解除，量刑折扣 %.0f%%。" % (float(r.get("discount", 0.0)) * 100.0)], 0, "")


func _crime_flee(intent) -> Dictionary:
	var target: String = String(intent.params.get("method", "")).strip_edges()
	if target.is_empty():
		return _fail("请指明潜逃目的地。")
	var region: String = _find_region_id(target)
	var r: Dictionary = host.crime_flee(region)
	if not bool(r.get("ok", false)):
		return _fail("无法潜逃（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已潜逃至 %s，通缉随行转移。" % region], 0, "")


func _crime_alias(intent) -> Dictionary:
	var r: Dictionary = host.crime_change_identity()
	if not bool(r.get("ok", false)):
		return _fail("无法化名（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已使用化名，追缉强度下降（累计 %d 次）。" % int(r.get("aliases", 0))], 0, "")


func _crime_bribe(intent) -> Dictionary:
	var amount: int = maxi(1, _param_number(intent, "number", 1000000))
	var r: Dictionary = host.crime_bribe(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法行贿（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var tail: String = "，但被查处并加罪" if bool(r.get("exposed", false)) else ""
	if bool(r.get("success", false)):
		return _ok(["行贿 %d 奏效，通缉解除%s。" % [int(r.get("paid", 0)), tail]], 0, "")
	return _ok(["行贿 %d 未奏效%s。" % [int(r.get("paid", 0)), tail]], 0, "")


func _prison_labor(intent) -> Dictionary:
	var hours: int = maxi(1, _param_number(intent, "number", 8))
	var r: Dictionary = host.prison_labor(float(hours))
	if not bool(r.get("ok", false)):
		return _fail("无法劳动（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["劳动 %d 小时，收入 %d，表现 %.0f。" % [hours, int(r.get("income", 0)), float(r.get("behavior", 0.0))]], 0, "")


func _prison_visit(intent) -> Dictionary:
	var visitor: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.prison_visit(visitor)
	if not bool(r.get("ok", false)):
		return _fail("无法探视（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["%s 前来探视，表现 %.0f。" % [String(r.get("visitor", "家人")), float(r.get("behavior", 0.0))]], 0, "")


func _prison_interact(intent) -> Dictionary:
	var r: Dictionary = host.prison_interact()
	if not bool(r.get("ok", false)):
		return _fail("无法交流（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if String(r.get("event", "")) == "conflict":
		return _ok(["与狱友发生冲突，表现降至 %.0f。" % float(r.get("behavior", 0.0))], 0, "")
	return _ok(["与狱友结交，关系 %.0f。" % float(r.get("gang_relation", 0.0))], 0, "")


func _prison_gang(intent) -> Dictionary:
	var raw: String = String(intent.params.get("method", "")).strip_edges()
	var gang: String = raw
	match raw:
		"秩序帮", "秩序": gang = "order"
		"兄弟会", "兄弟": gang = "brotherhood"
		"独行": gang = "lone"
		"中立": gang = "none"
		_: pass
	if gang.is_empty():
		return _fail("请指明要加入的狱帮。")
	var r: Dictionary = host.prison_join_gang(gang)
	if not bool(r.get("ok", false)):
		return _fail("无法加入狱帮（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已加入%s。" % String(r.get("name", gang))], 0, "")


func _prison_violation(intent) -> Dictionary:
	var r: Dictionary = host.prison_violation()
	if not bool(r.get("ok", false)):
		return _fail("无法违纪（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["违纪 1 次，表现降至 %.0f。" % float(r.get("behavior", 0.0))], 0, "")


func _prison_reduce(intent) -> Dictionary:
	var days: int = maxi(1, _param_number(intent, "number", 30))
	var r: Dictionary = host.prison_reduce_sentence(days)
	if not bool(r.get("ok", false)):
		return _fail("无法减刑（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["减刑 %d 日，剩余 %d 日。" % [days, int(r.get("days_remaining", 0))]], 0, "")


func _prison_parole(intent) -> Dictionary:
	var r: Dictionary = host.prison_parole()
	if not bool(r.get("ok", false)):
		return _fail("无法申请假释（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("granted", false)):
		return _ok(["假释获批，已出狱。"], 0, "")
	return _ok(["假释未获批，继续服刑。"], 0, "")


func _prison_escape(intent) -> Dictionary:
	var r: Dictionary = host.prison_escape()
	if not bool(r.get("ok", false)):
		return _fail("无法越狱（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("escaped", false)):
		return _ok(["越狱成功，重新被通缉。"], 0, "")
	return _ok(["越狱失败，表现降至 %.0f。" % float(r.get("behavior", 0.0))], 0, "")


func _prison_reintegrate(intent) -> Dictionary:
	var support: int = clampi(_param_number(intent, "number", 30), 0, 100)
	var r: Dictionary = host.prison_reintegrate(float(support))
	if not bool(r.get("ok", false)):
		return _fail("无法融入社会（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["出狱融入：就业歧视 %.0f%%，再犯风险 %.0f%%%s。" % [
		float(r.get("employment_discrimination", 0.0)) * 100.0,
		float(r.get("recidivism_risk", 0.0)) * 100.0,
		"，存在再犯倾向" if bool(r.get("reoffends", false)) else "",
	]], 0, "")


func _find_region_id(text: String) -> String:
	for r in host.regions_view():
		if r is Dictionary:
			var rid: String = String(r.get("region_key", ""))
			if rid == text or rid.to_lower() == text.to_lower():
				return rid
	return text

func _consumer_hotline(intent) -> Dictionary:
	var evidence: float = float(_param_number(intent, "number", 60)) / 100.0
	var r: Dictionary = host.consumer_12315(evidence)
	if not bool(r.get("ok", false)):
		return _fail("无法提交热线投诉（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var line := "12315 受理案号 %s，办理时限 %d 天。" % [String(r.get("case_no", "")), int(r.get("process_days", 0))]
	if bool(r.get("counterclaim_risk", false)):
		line += " 证据不足，商家可能反诉敲诈。"
	return _ok([line], 0, "")

func _consumer_class_action(intent) -> Dictionary:
	var r: Dictionary = host.consumer_class_action(0.5)
	if not bool(r.get("ok", false)):
		return _fail("无法集体维权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("success", false)):
		return _ok(["集体维权成功，合并赔偿 %d。" % int(r.get("compensation", 0))], 0, "")
	return _fail("集体维权未获支持。")

func _consumer_incident_quality(intent) -> Dictionary:
	return _consumer_incident(intent, "quality")

func _consumer_incident_food(intent) -> Dictionary:
	return _consumer_incident(intent, "food_safety")

func _consumer_incident(intent, kind: String) -> Dictionary:
	var severity: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.consumer_incident(kind, severity, 3)
	if not bool(r.get("ok", false)):
		return _fail("无法处理事故（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["监管处罚 %d，赔偿 %d%s。" % [int(r.get("fine", 0)), int(r.get("compensation", 0)), "，产品下架" if bool(r.get("delisted", false)) else ""]], 0, "")

func _consumer_recall(intent) -> Dictionary:
	var affected: int = int(_param_number(intent, "number", 100))
	var r: Dictionary = host.consumer_recall(affected)
	if not bool(r.get("ok", false)):
		return _fail("无法召回（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["召回 %d 件，成本 %d。" % [int(r.get("affected", 0)), int(r.get("cost", 0))]], 0, "")

func _consumer_fraud(intent) -> Dictionary:
	var r: Dictionary = host.consumer_professional_fraud()
	if not bool(r.get("ok", false)):
		return _fail("无法打假（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("success", false)):
		return _fail("打假未获支持（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["打假成功，获赔 %d。" % int(r.get("compensation", 0))], 0, "")

func _consumer_malicious(intent) -> Dictionary:
	var r: Dictionary = host.consumer_malicious_claim()
	if not bool(r.get("ok", false)):
		return _fail("无法索赔（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("malicious", false)):
		return _fail("恶意索赔%s。" % ("被识别驳回" if bool(r.get("detected", false)) else "成立"))
	return _ok(["索赔属正当维权。"], 0, "")

func _welfare_apply(intent, kind: String) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 0))
	var r: Dictionary = host.welfare_apply(kind, amount)
	if not bool(r.get("ok", false)):
		return _fail("无法申请（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var label: String = {"adoption": "收养", "foster": "寄养", "dibao": "低保", "medical_aid": "医疗救助", "temporary_aid": "临时救助", "homeless_relief": "流浪救助"}.get(kind, kind)
	if bool(r.get("approved", false)):
		return _ok(["%s申请通过。" % label], 0, "")
	var reasons: Array = r.get("reasons", [])
	var cn: Array = []
	for reason in reasons:
		cn.append(_reason_cn(String(reason)))
	return _fail("%s申请被拒（%s）。" % [label, "、".join(cn)])

func _welfare_finalize(intent) -> Dictionary:
	var r: Dictionary = host.welfare_finalize_placement()
	if not bool(r.get("ok", false)):
		if String(r.get("reason", "")) == "waiting":
			return _fail("安置等待期未满，还需 %d 天。" % int(r.get("days_left", 0)))
		return _fail("无法生效（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["收养/寄养安置已生效。"], 0, "")

func _welfare_revoke_adoption(intent) -> Dictionary:
	var r: Dictionary = host.welfare_revoke_placement()
	if not bool(r.get("ok", false)):
		return _fail("无法撤销收养（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["收养关系已撤销。"], 0, "")

func _welfare_disburse(intent) -> Dictionary:
	var days: int = int(_param_number(intent, "number", 30))
	var r: Dictionary = host.welfare_disburse(days)
	if not bool(r.get("ok", false)):
		if String(r.get("reason", "")) == "not_approved":
			return _fail("救助申请尚未获批。")
		return _fail("无法发放（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["救助金发放 %d（%d 天）。" % [int(r.get("paid", 0)), int(r.get("days", 0))]], 0, "")

func _welfare_crisis(intent) -> Dictionary:
	var situation := String(intent.params.get("method", "orphan"))
	var r: Dictionary = host.welfare_crisis(situation, false)
	if not bool(r.get("ok", false)):
		return _fail("无法安置（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["儿童进入%s。" % _route_cn(String(r.get("route", "")))], 0, "")

func _route_cn(route: String) -> String:
	match route:
		"kinship_care":
			return "亲属抚养"
		"institution":
			return "福利机构"
		"relief":
			return "救助体系"
		_:
			return "寄养家庭"

func _welfare_recognize(intent) -> Dictionary:
	var origin := String(intent.params.get("method", "")).strip_edges()
	if origin == "":
		return _fail("请给出原资格所在区域。")
	var r: Dictionary = host.welfare_recognize(origin)
	if not bool(r.get("ok", false)):
		return _fail("无法办理资格互认（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var cert: Dictionary = r.get("certificate", {})
	return _ok(["资格互认成功：%s → %s，有效期 %d 天。" % [String(cert.get("origin", "")), String(cert.get("target", "")), int(cert.get("valid_days", 0))]], 0, "")

func _welfare_fund_new(intent) -> Dictionary:
	var name := String(intent.params.get("method", "公益基金"))
	var r: Dictionary = host.welfare_fund_new(name)
	if not bool(r.get("ok", false)):
		return _fail("无法设立基金。")
	return _ok(["已设立慈善基金「%s」。" % name], 0, "")

func _welfare_donate(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 10000))
	var r: Dictionary = host.welfare_fund_donate(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法捐款（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["捐款 %d，累计募得 %d。" % [amount, int(r.get("raised", 0))]], 0, "")

func _welfare_spend(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 10000))
	var purpose := String(intent.params.get("method", "公益救助"))
	var r: Dictionary = host.welfare_fund_spend(purpose, amount)
	if not bool(r.get("ok", false)):
		return _fail("无法支出（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["公益支出 %d（%s），结余 %d。" % [amount, purpose, int(r.get("balance", 0))]], 0, "")

func _welfare_publish(intent) -> Dictionary:
	var r: Dictionary = host.welfare_fund_publish("年度")
	if not bool(r.get("ok", false)):
		return _fail("无法公示（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var rep: Dictionary = r.get("report", {})
	return _ok(["慈善公示已发布：募得 %d，支出 %d，结余 %d。" % [int(rep.get("raised", 0)), int(rep.get("spent", 0)), int(rep.get("balance", 0))]], 0, "")

func _welfare_audit(intent) -> Dictionary:
	var r: Dictionary = host.welfare_fund_audit()
	if not bool(r.get("ok", false)):
		return _fail("无法审计（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["透明度 %d，评级 %s。" % [int(r.get("transparency", 0)), String(r.get("grade", ""))]], 0, "")

func _welfare_misappropriate(intent) -> Dictionary:
	var amount: int = int(_param_number(intent, "number", 10000))
	var r: Dictionary = host.welfare_fund_misappropriate(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法挪用（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("detected", false)):
		return _fail("善款挪用被查获，声誉受损。")
	return _ok(["善款挪用 %d，暂未被查获。" % amount], 0, "")

func _welfare_worker(intent) -> Dictionary:
	var r: Dictionary = host.welfare_worker_start()
	if not bool(r.get("ok", false)):
		return _fail("无法入职。")
	return _ok(["已入职社工。"], 0, "")

func _welfare_follow_up(intent) -> Dictionary:
	var note := String(intent.params.get("method", "家访"))
	var r: Dictionary = host.welfare_follow_up(note)
	if not bool(r.get("ok", false)):
		return _fail("无法跟进（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["个案跟进，第 %d 次探访，进展 %d%%。" % [int(r.get("visits", 0)), int(round(float(r.get("progress", 0.0)) * 100.0))]], 0, "")

func _welfare_close_case(intent) -> Dictionary:
	var r: Dictionary = host.welfare_close_case()
	if not bool(r.get("ok", false)):
		return _fail("无法结案（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["个案结案，累计结案 %d%s。" % [int(r.get("cases_closed", 0)), "，获晋升" if bool(r.get("promoted", false)) else ""]], 0, "")

func _welfare_abuse(intent) -> Dictionary:
	var r: Dictionary = host.welfare_report_abuse()
	if not bool(r.get("ok", false)):
		return _fail("无法举报（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("substantiated", false)):
		return _ok(["虐待举报属实，撤销监护并转介寄养。"], 0, "")
	return _fail("虐待举报未获证实。")

func _welfare_dependency(intent) -> Dictionary:
	var r: Dictionary = host.welfare_dependency()
	if not bool(r.get("ok", false)):
		return _fail("无法评估。")
	if bool(r.get("escaped", false)):
		return _ok(["经就业脱困，摆脱救助依赖。"], 0, "")
	return _ok(["救助依赖度 %d%%。" % int(round(float(r.get("dependency", 0.0)) * 100.0))], 0, "")

func _funeral_arrange(intent) -> Dictionary:
	var method: String = _object_id(intent, "funeral_method")
	if method.is_empty():
		method = "cremation"
	var grave: String = _object_id(intent, "funeral_grave")
	var estate: int = int(_param_number(intent, "number", -1))
	var r: Dictionary = host.funeral_arrange(method, grave, estate)
	if not bool(r.get("ok", false)):
		return _fail("无法安排殡葬（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已安排%s%s，费用 %d%s。" % [String(r.get("name", "")), "与" + String((host.funeral.grave_def(String(r.get("grave", ""))) as Dictionary).get("name", "")) if String(r.get("grave", "")) != "" else "", int(r.get("cost", 0)), "" if bool(r.get("affordable", true)) else "（遗产不足）"]], 0, "")

func _funeral_execute(intent) -> Dictionary:
	var r: Dictionary = host.funeral_execute(false)
	if not bool(r.get("ok", false)):
		return _fail("无法执行殡葬（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["殡葬已执行，支出 %d。" % int(r.get("paid", 0))], 0, "")

func _funeral_donation(intent) -> Dictionary:
	var r: Dictionary = host.funeral_register_donation()
	if not bool(r.get("ok", false)):
		return _fail("无法登记捐献（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已登记器官捐献，共 %d 项。" % int((r.get("organs", []) as Array).size())], 0, "")

func _funeral_ethics(intent) -> Dictionary:
	var r: Dictionary = host.funeral_review_ethics()
	if not bool(r.get("ok", false)):
		return _fail("无法审查（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("approved", false)):
		return _ok(["伦理与法律审查通过。"], 0, "")
	return _fail("伦理审查未通过。")

func _funeral_revoke(intent) -> Dictionary:
	var r: Dictionary = host.funeral_revoke_donation(true)
	if not bool(r.get("ok", false)):
		return _fail("无法撤销捐献（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["家属已撤销捐献。"], 0, "")

func _funeral_allocate(intent) -> Dictionary:
	var r: Dictionary = host.funeral_allocate_organs()
	if not bool(r.get("ok", false)):
		return _fail("无法分配器官（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["器官分配完成，共 %d 例。" % int(r.get("count", 0))], 0, "")

func _funeral_transplant(intent) -> Dictionary:
	var organ := String(intent.params.get("method", "heart"))
	var r: Dictionary = host.funeral_transplant(organ)
	if bool(r.get("success", false)):
		return _ok(["%s移植成功。" % String(r.get("organ_name", organ))], 0, "")
	return _fail("%s移植出现排异。" % String(r.get("organ_name", organ)))

func _funeral_memorial(intent) -> Dictionary:
	var r: Dictionary = host.funeral_build_memorial("monument")
	if not bool(r.get("ok", false)):
		return _fail("无法立碑（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已立纪念碑，意义感提升。"], 0, "")

func _funeral_sweep(intent) -> Dictionary:
	var kind := String(intent.params.get("method", "family_grave"))
	var r: Dictionary = host.funeral_tomb_sweeping(kind)
	if not bool(r.get("ok", false)):
		return _fail("无法祭扫（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["祭扫完成，累计 %d 次。" % int(r.get("visits", 0))], 0, "")

func _funeral_digital(intent) -> Dictionary:
	var r: Dictionary = host.funeral_digital_memorial()
	if not bool(r.get("ok", false)):
		return _fail("无法创建数字纪念。")
	return _ok(["数字纪念已创建，访问 %d 次。" % int(r.get("visits", 0))], 0, "")

func _funeral_digital_platform(intent) -> Dictionary:
	var members: int = int(_param_number(intent, "number", 50))
	var r: Dictionary = host.funeral_digital_platform(members)
	if not bool(r.get("ok", false)):
		return _fail("无法运营数字纪念平台（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["数字纪念平台会员 %d，净收入 %d，公益基金 %d。" % [int(r.get("members", 0)), int(r.get("net", 0)), int(r.get("fund", 0))]], 0, "")

func _funeral_will(intent) -> Dictionary:
	var r: Dictionary = host.funeral_execute_will()
	if not bool(r.get("ok", false)):
		return _fail("无法执行遗嘱（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("valid", false)):
		return _ok(["遗嘱已按生前意愿执行。"], 0, "")
	return _fail("遗嘱无效，仅能给出建议。")

func _funeral_home(intent) -> Dictionary:
	var name := String(intent.params.get("method", "殡仪馆"))
	var r: Dictionary = host.funeral_new_home(name)
	if not bool(r.get("ok", false)):
		return _fail("无法开办殡仪馆。")
	return _ok(["已开办「%s」。" % name], 0, "")

func _funeral_quote(intent) -> Dictionary:
	var method: String = _object_id(intent, "funeral_method")
	if method.is_empty():
		method = "cremation"
	var r: Dictionary = host.funeral_quote(method)
	if not bool(r.get("ok", false)):
		return _fail("无法报价（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["报价 %d。" % int(r.get("price", 0))], 0, "")

func _funeral_sale(intent) -> Dictionary:
	var method: String = _object_id(intent, "funeral_method")
	if method.is_empty():
		method = "cremation"
	var r: Dictionary = host.funeral_sale(method)
	if not bool(r.get("ok", false)):
		return _fail("无法成交（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["成交价 %d，利润 %d%s。" % [int(r.get("price", 0)), int(r.get("profit", 0)), "（涉嫌暴利）" if bool(r.get("excessive", false)) else ""]], 0, "")

func _funeral_regulate(intent) -> Dictionary:
	var r: Dictionary = host.funeral_regulate()
	if not bool(r.get("ok", false)):
		return _fail("无法监管（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("detected", false)):
		return _ok(["查处暴利，罚款 %d。" % int(r.get("fine", 0))], 0, "")
	return _ok(["本次未查获违规。"], 0, "")

func _funeral_reform(intent) -> Dictionary:
	var r: Dictionary = host.funeral_reform()
	if not bool(r.get("ok", false)):
		return _fail("无法改革（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["殡葬陋习改革，降价后倍数 %s。" % str(r.get("price_mult", 1.0))], 0, "")

func _funeral_unclaimed(intent) -> Dictionary:
	var r: Dictionary = host.funeral_unclaimed()
	if not bool(r.get("ok", false)):
		return _fail("无法处置（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["无人认领遗体已公益火化。"], 0, "")

func _funeral_dispute(intent) -> Dictionary:
	var r: Dictionary = host.funeral_dispute()
	if not bool(r.get("ok", false)):
		return _fail("无法处理争议（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["捐献争议已%s。" % ("调解撤销捐献" if bool(r.get("revoked", false)) else "受理待调")], 0, "")

func _meta_consult(intent) -> Dictionary:
	var service: String = _object_id(intent, "meta_service")
	if service.is_empty():
		service = "fortune"
	var mode: String = _object_id(intent, "meta_mode")
	if mode.is_empty():
		mode = "offline"
	var r: Dictionary = host.metaphysics_consult(service, mode)
	if not bool(r.get("ok", false)):
		return _fail("无法咨询（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var line: String = "%s（%s）——%s" % [String(r.get("service_name", "")), String(r.get("mode", "")), String(r.get("claimed", ""))]
	if bool(r.get("scam", false)):
		line += "（疑似诈骗话术）"
	return _ok([line], 0, "")

func _meta_folk(intent) -> Dictionary:
	var practice: String = _object_id(intent, "folk_practice")
	if practice.is_empty():
		practice = "festival_ritual"
	var r: Dictionary = host.metaphysics_folk(practice)
	if not bool(r.get("ok", false)):
		return _fail("无法进行民俗活动（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["进行%s，心情 +%d。" % [String(r.get("name", "")), int(r.get("mood_delta", 0))]], 0, "")

func _meta_business(intent) -> Dictionary:
	var name := String(intent.params.get("method", "玄学馆"))
	var r: Dictionary = host.metaphysics_new_business(name)
	if not bool(r.get("ok", false)):
		return _fail("无法开办。")
	return _ok(["已开办「%s」。" % name], 0, "")

func _meta_operate(intent) -> Dictionary:
	var r: Dictionary = host.metaphysics_operate()
	if not bool(r.get("ok", false)):
		return _fail("无法营业（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["营业入账 %d%s。" % [int(r.get("earned", 0)), "，遭投诉" if bool(r.get("complained", false)) else ""]], 0, "")

func _meta_complaint(intent) -> Dictionary:
	var r: Dictionary = host.metaphysics_complaint(true)
	if not bool(r.get("ok", false)):
		return _fail("无法投诉（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已投诉举报，举报数 %d。" % int(r.get("reports", 0))], 0, "")

func _meta_investigate(intent) -> Dictionary:
	var r: Dictionary = host.metaphysics_investigate()
	if not bool(r.get("ok", false)):
		return _fail("无法查处（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("convicted", false)):
		return _ok(["诈骗查处成立，罚款 %d。" % int(r.get("fine", 0))], 0, "")
	return _ok(["举报量不足或未定罪。"], 0, "")

func _meta_fall(intent) -> Dictionary:
	var r: Dictionary = host.metaphysics_master_fall()
	if not bool(r.get("ok", false)):
		return _fail("无法翻车（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["大师人设翻车，声誉跌至 %d%%。" % int(round(float(r.get("reputation", 0.0)) * 100.0))], 0, "")

func _meta_superstition(intent) -> Dictionary:
	var members: int = int(_param_number(intent, "number", 100))
	var r: Dictionary = host.metaphysics_superstition(members)
	if not bool(r.get("ok", false)):
		return _fail("无法组织。")
	return _ok(["组织化迷信，成员 %d，影响力 %d%%。" % [int(r.get("members", 0)), int(round(float(r.get("influence", 0.0)) * 100.0))]], 0, "")

func _meta_collude(intent) -> Dictionary:
	var r: Dictionary = host.metaphysics_collude()
	if not bool(r.get("ok", false)):
		return _fail("无法勾结（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _fail("与灰产勾结被曝光，牵连追责。")
	return _ok(["与灰产勾结，暂未曝光。"], 0, "")

func _meta_blur(intent) -> Dictionary:
	var r: Dictionary = host.metaphysics_blur()
	if not bool(r.get("ok", false)):
		return _fail("无法判断。")
	return _ok(["外观%s，%s。" % ["不可区分", String(r.get("label", "普通从业者"))]], 0, "")

func _anomaly_open_gate(intent) -> Dictionary:
	var path: String = _object_id(intent, "anomaly_gate")
	if path.is_empty():
		return _fail("请指明门闩途径。")
	var r: Dictionary = host.anomaly_open_gate(path)
	if not bool(r.get("ok", false)):
		return _fail("无法开启（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已开启「%s」，异常世界向你敞开。" % String(r.get("gate", ""))], 0, "")

func _anomaly_rare_talent(intent) -> Dictionary:
	var r: Dictionary = host.anomaly_rare_talent()
	if bool(r.get("born_with_talent", false)):
		return _ok(["天赋觉醒：你生来便感知常人不可见之物。"], 0, "")
	return _ok(["并未觉醒异常天赋。"], 0, "")

func _anomaly_encounter(intent) -> Dictionary:
	var eid: String = _object_id(intent, "anomaly_entry")
	if eid.is_empty():
		return _fail("请指明异常条目。")
	var r: Dictionary = host.anomaly_encounter(eid)
	if not bool(r.get("ok", false)):
		return _fail("无法查阅（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var e: Dictionary = r.get("entry", {})
	return _ok(["已收录「%s」，威胁 %s，暴露值 %d。" % [String(e.get("name", eid)), String(e.get("threat", "")), int(round(float(r.get("exposure", 0.0))))]], 0, "")

func _anomaly_use_ability(intent) -> Dictionary:
	var line: String = _object_id(intent, "anomaly_ability")
	if line.is_empty():
		return _fail("请指明能力线。")
	var r: Dictionary = host.anomaly_use_ability(line)
	if not bool(r.get("ok", false)):
		return _fail("无法施展（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["施展%s，等级 %d，效果强度 %d%%。" % [String(r.get("name", line)), int(r.get("level", 0)), int(round(float(r.get("effect_strength", 0.0)) * 100.0))]], 0, "")

func _anomaly_clearance(intent) -> Dictionary:
	var level: int = int(_param_number(intent, "number", 1))
	var r: Dictionary = host.anomaly_set_clearance(level)
	return _ok(["权限提升至 Level %d。" % int(r.get("clearance", 0))], 0, "")

func _anomaly_join_faction(intent) -> Dictionary:
	var fid: String = _object_id(intent, "anomaly_faction")
	if fid.is_empty():
		return _fail("请指明阵营。")
	var r: Dictionary = host.anomaly_join_faction(fid)
	if not bool(r.get("ok", false)):
		return _fail("无法加入（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已加入%s。" % String(r.get("name", fid))], 0, "")

func _anomaly_accept_mission(intent) -> Dictionary:
	var fid: String = _object_id(intent, "anomaly_faction")
	if fid.is_empty():
		return _fail("请指明阵营。")
	var mid: String = String(intent.params.get("method", "mission_1"))
	var r: Dictionary = host.anomaly_accept_mission(mid, fid)
	if not bool(r.get("ok", false)):
		return _fail("无法接受任务（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已接下任务「%s」。" % mid], 0, "")

func _anomaly_complete_mission(intent) -> Dictionary:
	var mid: String = String(intent.params.get("method", "mission_1"))
	var r: Dictionary = host.anomaly_complete_mission(mid, true)
	if not bool(r.get("ok", false)):
		return _fail("无法完成任务（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["任务完成，阵营声望 %d。" % int(round(float(r.get("reputation", 0.0))))], 0, "")

func _anomaly_amnestics(intent) -> Dictionary:
	var dose: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.anomaly_amnestics(dose)
	if not bool(r.get("ok", false)):
		return _fail("无法施用记忆删除剂（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["记忆删除剂（剂量%d%%）：清除污染 %d，记忆缺口 %d，使用 %d/%d。" % [int(round(dose * 100.0)), int(round(float(r.get("cleared", 0.0)))), int(r.get("memory_gaps", 0)), int(r.get("uses", 0)), int(r.get("max", 0))]], 0, "")

func _anomaly_combat(intent) -> Dictionary:
	var r: Dictionary = host.anomaly_combat()
	if bool(r.get("attacker_wins", false)):
		return _ok(["认知对抗胜出（胜率%d%%）。" % int(round(float(r.get("win_probability", 0.0)) * 100.0))], 0, "")
	return _ok(["认知对抗落败（胜率%d%%）。" % int(round(float(r.get("win_probability", 0.0)) * 100.0))], 0, "")

func _anomaly_breach(intent) -> Dictionary:
	var r: Dictionary = host.anomaly_breach()
	return _ok(["收容失效，暴露 +%d，当前暴露 %d。" % [int(round(float(r.get("exposure_gain", 0.0)))), int(round(float(r.get("exposure", 0.0))))]], 0, "")

func _anomaly_identity(intent) -> Dictionary:
	var ident: String = _object_id(intent, "anomaly_identity")
	if ident.is_empty():
		return _fail("请指明身份。")
	var r: Dictionary = host.anomaly_set_identity(ident)
	if not bool(r.get("ok", false)):
		return _fail("无法设定身份（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["身份设定为%s。" % String(r.get("name", ident))], 0, "")

const MILITARY_BRANCH_NAMES: Dictionary = {
	"陆军": "army", "海军": "navy", "空军": "air", "火箭军": "rocket",
	"后勤": "logistics", "通信": "signal", "特种": "special",
}
const WORK_EVENT_NAMES: Dictionary = {
	"抢功": "credit_grab", "甩锅": "blame", "站队": "take_sides", "举报": "report",
}
const FINANCE_STAGE_NAMES: Dictionary = {
	"种子": "seed", "天使": "angel", "A轮": "series_a", "B轮": "series_b", "C轮": "series_c",
}


func _military_enlist(intent) -> Dictionary:
	var raw: String = _object_id(intent, "military_branch")
	if raw.is_empty():
		raw = String(intent.params.get("method", "")).strip_edges()
	var branch: String = String(MILITARY_BRANCH_NAMES.get(raw, raw))
	var r: Dictionary = host.military_enlist(branch)
	if not bool(r.get("ok", false)):
		var missing: Array = r.get("missing", [])
		var labels: Dictionary = {
			"already_serving": "已在役", "age": "年龄不符", "health": "健康不达标",
			"education": "学历不足", "political_review": "政审未过", "branch_not_found": "兵种不存在",
		}
		var lines: Array = []
		for m in missing:
			var key: String = String(m)
			lines.append(String(labels.get(key, "技能不足：" + key.trim_prefix("skill:"))))
		return _fail("入伍条件不符（%s）。" % "、".join(lines))
	return _ok(["你已加入%s，授予列兵军衔。" % String((host.military_sys.BRANCHES[branch] as Dictionary).get("name", branch))], 0, "")


func _military_train(intent) -> Dictionary:
	var days: float = clampf(float(_param_number(intent, "number", 7)), 1.0, 365.0)
	var r: Dictionary = host.military_train(days)
	if not bool(r.get("ok", false)):
		return _fail("训练失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["完成 %.0f 天训练，累计军功 %.1f。" % [days, float(r.get("merits", 0.0))]], int(days * DAY), "")


func _military_mission(intent) -> Dictionary:
	var difficulty: float = clampf(float(_param_number(intent, "number", 100)) / 100.0, 0.5, 3.0)
	var r: Dictionary = host.military_mission(difficulty)
	if not bool(r.get("ok", false)):
		return _fail("任务失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var lines: Array = ["军功 +%.1f，累计 %.1f。" % [float(r.get("merits_gained", 0.0)), float(r.get("merits", 0.0))]]
	if bool(r.get("kia", false)):
		lines.append("你在任务中阵亡。")
	elif bool(r.get("casualty", false)):
		lines.append("你负伤退役治疗，健康受损。")
	return _ok(lines, DAY, "")


func _military_promote(intent) -> Dictionary:
	var r: Dictionary = host.military_promote()
	if not bool(r.get("ok", false)):
		return _fail("晋升考核未通过（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["晋升为%s。" % String(r.get("rank_name", ""))], 0, "")


func _military_discharge(intent) -> Dictionary:
	var r: Dictionary = host.military_discharge()
	if not bool(r.get("ok", false)):
		return _fail("退伍失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你已退伍，领取退役金 %d，服务 %.1f 年。" % [int(r.get("severance", 0)), float(r.get("years", 0.0))]], 0, "")


func _military_desert(intent) -> Dictionary:
	var r: Dictionary = host.military_desert()
	if not bool(r.get("ok", false)):
		return _fail("无法离队（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你成了逃兵，通缉等级升至 %d。" % int(r.get("wanted_level", 0))], 0, "")


func _workplace_politics(intent) -> Dictionary:
	var raw: String = String(intent.params.get("method", "")).strip_edges()
	var event: String = String(WORK_EVENT_NAMES.get(raw, ""))
	var r: Dictionary = host.workplace_politics(event)
	if not bool(r.get("ok", false)):
		return _fail("职场事件未发生（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var names: Dictionary = {"credit_grab": "抢功", "blame": "甩锅", "take_sides": "站队", "report": "举报"}
	return _ok(["办公室政治：%s，%s。" % [String(names.get(String(r.get("event", "")), "事件")), "你占了上风" if bool(r.get("success", false)) else "你吃了亏"]], 0, "")


func _workplace_join(intent) -> Dictionary:
	var raw: String = String(intent.params.get("method", "")).strip_edges()
	var fid: String = raw
	if raw == "改革派":
		fid = "reform"
	elif raw == "保守派":
		fid = "status_quo"
	var r: Dictionary = host.workplace_join(fid)
	if not bool(r.get("ok", false)):
		return _fail("站队失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你加入了%s派系。" % raw], 0, "")


func _workplace_neutral(intent) -> Dictionary:
	var r: Dictionary = host.workplace_stay_neutral()
	if not bool(r.get("ok", false)):
		return _fail("无法保持中立（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你选择骑墙，暂不站队。"], 0, "")


func _workplace_found(intent) -> Dictionary:
	var name: String = String(intent.params.get("method", "")).strip_edges()
	if name.is_empty():
		name = "自立派"
	var r: Dictionary = host.workplace_found_faction(name)
	if not bool(r.get("ok", false)):
		return _fail("自组派系失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你组建了「%s」。" % name], 0, "")


func _workplace_promote(intent) -> Dictionary:
	var r: Dictionary = host.workplace_promote()
	if not bool(r.get("ok", false)):
		return _fail("晋升未通过（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["你晋升为%s。" % String(r.get("title", r.get("content_key", "")))], 0, "")


func _company_register(intent) -> Dictionary:
	var raw: String = String(intent.params.get("method", "")).strip_edges()
	var kind: String = "sole_proprietor"
	if raw.contains("公司"):
		kind = "company"
	var name: String = raw
	if name.is_empty() or name == "个体户" or name == "公司":
		name = "我的公司"
	var capital: int = int(_param_number(intent, "number", 100000)) * 100
	var r: Dictionary = host.company_register(kind, name, capital)
	if not bool(r.get("ok", false)):
		return _fail("注册失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已注册「%s」，实缴资本 %d。" % [name, capital]], 0, "")


func _company_site(intent) -> Dictionary:
	var area: float = clampf(float(_param_number(intent, "number", 80)), 10.0, 10000.0)
	var rent: int = int(area * 2000.0)
	var r: Dictionary = host.company_choose_site(area, rent)
	if not bool(r.get("ok", false)):
		return _fail("选址失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已选定 %.0f 平方米店面，月租 %d。" % [area, rent]], 0, "")


func _company_open(intent) -> Dictionary:
	var r: Dictionary = host.company_set_status(true)
	if not bool(r.get("ok", false)):
		return _fail("开业失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["门店已开始营业。"], 0, "")


func _company_close(intent) -> Dictionary:
	var r: Dictionary = host.company_set_status(false)
	if not bool(r.get("ok", false)):
		return _fail("打烊失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["门店已打烊。"], 0, "")


func _company_stock(intent) -> Dictionary:
	var good: String = _object_id(intent, "item")
	if good.is_empty():
		good = String(intent.params.get("method", "")).strip_edges()
	if good.is_empty():
		return _fail("未指定进货商品。")
	var qty: int = maxi(1, int(_param_number(intent, "number", 10)))
	var def: Dictionary = host.items.get_def(good)
	var unit_cost: int = int(round(float(def.get("base_price", 10.0)) * 100.0)) if not def.is_empty() else 1000
	var r: Dictionary = host.company_stock(good, qty, unit_cost)
	if not bool(r.get("ok", false)):
		return _fail("进货失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["进货 %s × %d，花费 %d。" % [String(def.get("name", good)), qty, int(r.get("cost", 0))]], 0, "")


func _company_price(intent) -> Dictionary:
	var good: String = _object_id(intent, "item")
	if good.is_empty():
		good = String(intent.params.get("method", "")).strip_edges()
	if good.is_empty():
		return _fail("未指定定价商品。")
	var price: int = maxi(0, int(_param_number(intent, "number", 20)) * 100)
	var r: Dictionary = host.company_set_price(good, price)
	if not bool(r.get("ok", false)):
		return _fail("定价失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已将 %s 定价为 %d。" % [good, price]], 0, "")


func _company_hire(intent) -> Dictionary:
	var wage: int = maxi(1, int(_param_number(intent, "number", 3000))) * 100
	var r: Dictionary = host.company_hire(wage)
	if not bool(r.get("ok", false)):
		return _fail("雇人失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已雇佣一名员工，月薪 %d。" % wage], 0, "")


func _company_expand(intent) -> Dictionary:
	var cost: int = maxi(1, int(_param_number(intent, "number", 100000))) * 100
	var r: Dictionary = host.company_expand(cost)
	if not bool(r.get("ok", false)):
		return _fail("扩张失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["门店已扩张，分支 %d 家。" % int(r.get("branches", 0))], 0, "")


func _company_tax(intent) -> Dictionary:
	var r: Dictionary = host.company_tax()
	if not bool(r.get("ok", false)):
		return _fail("纳税失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["缴纳税款 %d。" % int(r.get("tax", 0))], 0, "")


func _company_finance(intent) -> Dictionary:
	var raw: String = String(intent.params.get("method", "")).strip_edges()
	var stage: String = String(FINANCE_STAGE_NAMES.get(raw, ""))
	var r: Dictionary = host.company_finance_raise(stage)
	if not bool(r.get("ok", false)):
		return _fail("融资失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["完成%s轮融资，估值 %d，融资 %d，创始人持股 %.1f%%。" % [
		String(r.get("stage", "")), int(r.get("valuation", 0)), int(r.get("investment", 0)),
		float(r.get("founder_equity", 0.0)) * 100.0]], 0, "")


func _company_vam(intent) -> Dictionary:
	var target: int = maxi(1, int(_param_number(intent, "number", 1000000))) * 100
	var r: Dictionary = host.company_settle_vam(target)
	if not bool(r.get("ok", false)):
		return _fail("对赌结算失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["对赌结算：%s。" % ("达标" if not bool(r.get("triggered", false)) else "未达标触发补偿")], 0, "")


func _company_exit(intent) -> Dictionary:
	var raw: String = String(intent.params.get("method", "")).strip_edges()
	var kind: String = "ipo" if raw.contains("上市") or raw.contains("IPO") else "merger"
	var r: Dictionary = host.company_exit(kind)
	if not bool(r.get("ok", false)):
		return _fail("退出失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["公司以%s方式退出，你获得 %d。" % ["上市" if kind == "ipo" else "并购", int(r.get("proceeds", 0))]], 0, "")


const CARE_NAME_MAP: Dictionary = {
	"理发": "haircut", "发型": "haircut", "化妆": "makeup", "妆容": "makeup",
	"穿搭": "outfit", "着装": "outfit", "服装": "outfit", "健身": "fitness", "塑形": "fitness",
}


func _appearance_care(intent) -> Dictionary:
	var raw: String = _object_id(intent, "care_kind")
	if raw.is_empty():
		raw = String(intent.params.get("method", "")).strip_edges()
	var kind: String = String(CARE_NAME_MAP.get(raw, raw))
	if kind.is_empty() or not CARE_NAME_MAP.values().has(kind):
		return _fail("未指定护理方式；可选理发、化妆、穿搭或健身。")
	var value: float = clampf(float(_param_number(intent, "number", 70)), 0.0, 100.0)
	var r: Dictionary = host.appearance_care(kind, {"value": value})
	if not bool(r.get("ok", false)):
		return _fail("护理失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已完成%s，花费 %d，当前魅力 %.1f。" % [raw if not raw.is_empty() else kind, int(r.get("cost", 0)), float(r.get("charm", 0.0))]], 0, "")


func _aesthetic_perform(intent) -> Dictionary:
	var raw: String = _object_id(intent, "aesthetic_project")
	if raw.is_empty():
		raw = String(intent.params.get("method", "")).strip_edges()
	var legal: bool = true
	if raw.contains("非法") or raw.contains("黑诊所"):
		legal = false
		raw = raw.replace("非法", "").replace("黑诊所", "").strip_edges()
	var project: String = raw
	if not (host.aesthetic_sys.PROJECTS as Dictionary).has(project):
		for key in (host.aesthetic_sys.PROJECTS as Dictionary).keys():
			var def: Dictionary = host.aesthetic_sys.PROJECTS[key]
			if String(def.get("name", "")) == raw:
				project = String(key)
				break
	if not (host.aesthetic_sys.PROJECTS as Dictionary).has(project):
		return _fail("未指定医美项目；可先用「看形象」查看项目表。")
	var r: Dictionary = host.aesthetic_perform(project, legal)
	if not bool(r.get("ok", false)):
		return _fail("医美未完成（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var labels: Dictionary = {"success": "成功", "failure": "失败", "complication": "出现并发症"}
	var name: String = String(((host.aesthetic_sys.PROJECTS[project]) as Dictionary).get("name", project))
	var lines: Array = ["%s%s，花费 %d，%s。" % [
		name, "（非法诊所）" if not legal else "", int(r.get("cost", 0)),
		String(labels.get(String(r.get("outcome", "")), String(r.get("outcome", "")))),
	]]
	if int(r.get("health_loss", 0)) > 0:
		lines.append("并发症造成健康损失 %.0f。" % float(r.get("health_loss", 0.0)))
	lines.append("当前魅力 %.1f，恢复期 %d 分钟。" % [float(r.get("charm", 0.0)), int(r.get("remaining_minutes", 0))])
	return _ok(lines, 0, "")


func _aesthetic_claim(intent) -> Dictionary:
	var r: Dictionary = host.aesthetic_claim()
	if not bool(r.get("ok", false)):
		return _fail("无法维权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已就医美失败提起侵权诉讼，标的 %d，可用「民事开庭」推进。" % int(r.get("amount", 0))], 0, "")


func _appearance_verify(intent) -> Dictionary:
	var r: Dictionary = host.appearance_verify_id()
	if bool(r.get("matched", false)):
		return _ok(["人像比对通过（偏离 %.1f，容差 %.1f）。" % [float(r.get("diff", 0.0)), float(r.get("tolerance", 0.0))]], 0, "")
	return _ok(["人像比对未通过（偏离 %.1f > 容差 %.1f），需重办证件。" % [float(r.get("diff", 0.0)), float(r.get("tolerance", 0.0))]], 0, "")


func _appearance_reissue(intent) -> Dictionary:
	var r: Dictionary = host.appearance_reissue_id()
	if not bool(r.get("ok", false)):
		return _fail("重办证件失败（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["证件照已更新，花费 %d。" % int(r.get("cost", 0))], 0, "")


func _medical_register(intent) -> Dictionary:
	var care: String = _object_id(intent, "care_level")
	if care.is_empty():
		care = "secondary"
	var dept: String = _object_id(intent, "department")
	if dept.is_empty():
		dept = "internal"
	var r: Dictionary = host.medtech_register(care, dept)
	if not bool(r.get("ok", false)):
		return _fail("无法挂号（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var extra: String = "，需转诊上级" if bool(r.get("referral_needed", false)) else ""
	return _ok(["挂号完成，费用 %d，自付 %d%s。" % [int(r.get("cost", 0)), int(r.get("self_pay", 0)), extra]], 0, "")

func _medical_examine(intent) -> Dictionary:
	var exam: String = _object_id(intent, "medical_exam")
	if exam.is_empty():
		return _fail("请指明检查项目。")
	var r: Dictionary = host.medtech_examine("secondary", exam)
	if not bool(r.get("ok", false)):
		return _fail("无法检查（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["完成检查，证据值 %d%%，费用 %d。" % [int(round(float(r.get("evidence", 0.0)) * 100.0)), int(r.get("cost", 0))]], 0, "")

func _medical_treat(intent) -> Dictionary:
	var disease: String = _object_id(intent, "disease")
	if disease.is_empty():
		return _fail("请指明病种。")
	var method: String = String(intent.params.get("method", "medicine"))
	var r: Dictionary = host.medical_treat(disease, method)
	if not bool(r.get("ok", false)):
		return _fail("无法治疗（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["治疗完成，剩余病程 %d 日。" % int(round(float(r.get("remaining_days", 0.0))))], 0, "")

func _medical_surgery(intent) -> Dictionary:
	var disease: String = _object_id(intent, "disease")
	var r: Dictionary = host.medical_visit("hospital", "surgery", disease)
	if not bool(r.get("ok", false)):
		return _fail("无法安排手术（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已安排手术，费用 %d，自付 %d。" % [int(r.get("cost", 0)), int(r.get("self_pay", 0))]], 0, "")

func _medical_high_end(intent) -> Dictionary:
	var kind: String = _object_id(intent, "high_end_procedure")
	if kind.is_empty():
		return _fail("请指明高阶医疗类目。")
	var source: String = _object_id(intent, "organ_source")
	var r: Dictionary = host.medtech_high_end(kind, source)
	if not bool(r.get("ok", false)):
		return _fail("无法实施（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var outcome: String = "成功" if bool(r.get("success", false)) else "失败"
	return _ok(["实施%s：%s，费用 %d，风险 %d%%。" % [String(r.get("name", kind)), outcome, int(r.get("cost", 0)), int(round(float(r.get("risk", 0.0)) * 100.0))]], 0, "")

func _medical_ethics(intent) -> Dictionary:
	var kind: String = _object_id(intent, "high_end_procedure")
	if kind.is_empty():
		return _fail("请指明审查类目。")
	var score: float = clampf(float(_param_number(intent, "number", 70)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.medtech_review_ethics(kind, score)
	if not bool(r.get("ok", false)):
		return _fail("无法审查（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["伦理审查%s。" % ("通过" if bool(r.get("approved", false)) else "未通过")], 0, "")

func _pharma_start(intent) -> Dictionary:
	if host._pharma_company.is_empty():
		host.medtech_pharma_new("医药公司")
	var drug: String = String(intent.params.get("method", "新药A"))
	var r: Dictionary = host.medtech_pharma_start(drug)
	if not bool(r.get("ok", false)):
		return _fail("无法立项（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["新药「%s」立项，进入研发，启动经费 %d。" % [drug, int(r.get("cost", 0))]], 0, "")

func _pharma_advance(intent) -> Dictionary:
	var drug: String = String(intent.params.get("method", "新药A"))
	var r: Dictionary = host.medtech_pharma_advance(drug)
	if not bool(r.get("ok", false)):
		return _fail("无法推进（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("advanced", false)):
		return _ok(["管线推进至 %s。" % String(r.get("stage", ""))], 0, "")
	return _ok(["本阶段未通过，停留于 %s。" % String(r.get("stage", ""))], 0, "")

func _pharma_produce(intent) -> Dictionary:
	var drug: String = String(intent.params.get("method", "新药A"))
	var batches: float = float(_param_number(intent, "number", 1))
	var r: Dictionary = host.medtech_pharma_produce(drug, batches)
	if not bool(r.get("ok", false)):
		return _fail("无法生产（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["生产 %d 单位，库存 %d。" % [int(round(float(r.get("produced", 0.0)))), int(round(float(r.get("stock", 0.0))))]], 0, "")

func _pharma_sell(intent) -> Dictionary:
	var drug: String = String(intent.params.get("method", "新药A"))
	var units: float = float(_param_number(intent, "number", 100))
	var r: Dictionary = host.medtech_pharma_sell(drug, units, 1000)
	if not bool(r.get("ok", false)):
		return _fail("无法销售（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["售出 %d 单位，营收 %d（专利溢价 ×%.1f）。" % [int(round(float(r.get("sold", 0.0)))), int(r.get("revenue", 0)), float(r.get("patent_premium", 1.0))]], 0, "")

func _pharma_rep(intent) -> Dictionary:
	var drug: String = String(intent.params.get("method", "新药A"))
	var effort: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.medtech_medical_rep(drug, effort)
	if not bool(r.get("ok", false)):
		return _fail("无法推广（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["医药代表推广，销量提振 %d%s。" % [int(round(float(r.get("sales_boost", 0.0)))), "，涉嫌贿赂被曝光" if bool(r.get("bribery_exposed", false)) else ""]], 0, "")

func _medical_counterfeit(intent) -> Dictionary:
	var scale: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.medtech_counterfeit(scale)
	if bool(r.get("seized", false)):
		return _ok(["假药被查获，没收 %d，罚款 %d。" % [int(r.get("confiscated", 0)), int(r.get("fine", 0))]], 0, "")
	return _ok(["假药暂未被查获。"], 0, "")

func _medical_dispute(intent) -> Dictionary:
	var severity: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.medtech_dispute(severity)
	var line := "医患纠纷等级 %d%%。" % int(round(float(r.get("conflict_level", 0.0)) * 100.0))
	if bool(r.get("civil_filed", false)):
		line += " 已立案，标的 %d。" % int(r.get("amount", 0))
	elif bool(r.get("litigation", false)):
		line += " 已进入诉讼，但当前已有在审民事案件。"
	else:
		line += " 协商处理。"
	return _ok([line], 0, "")

func _medical_over(intent) -> Dictionary:
	var cost: int = int(_param_number(intent, "number", 100000))
	var r: Dictionary = host.medtech_over_treatment(cost)
	return _ok(["过度医疗虚增费用 %d，审计风险 %d%%。" % [int(r.get("excess_cost", 0)), int(round(float(r.get("audit_risk", 0.0)) * 100.0))]], 0, "")

func _medical_drug_course(intent) -> Dictionary:
	var days: int = int(_param_number(intent, "number", 30))
	var r: Dictionary = host.medical_drug_course(days, 0.7)
	if not bool(r.get("ok", false)):
		return _fail("无法执行用药疗程。")
	return _ok(["用药 %d 天，累计耐药 %.2f，副作用风险 %.0f%%，本次健康损失 %.1f。" % [
		int(r.get("days", 0)), float(r.get("resistance", 0.0)),
		float(r.get("side_effect_risk", 0.0)) * 100.0, float(r.get("side_effect_loss", 0.0))]], 0, "")

func _medical_fraud(intent) -> Dictionary:
	var claim: int = int(_param_number(intent, "number", 100000))
	var r: Dictionary = host.medtech_insurance_fraud(claim)
	if bool(r.get("detected", false)):
		return _fail("保险欺诈被审计发现，追缴并处罚 %d。" % int(r.get("penalty", 0)))
	return _ok(["虚假理赔 %d，暂未被发现。" % int(r.get("fraudulent", 0))], 0, "")

func _medical_scandal(intent) -> Dictionary:
	var drug: String = String(intent.params.get("method", "新药A"))
	var r: Dictionary = host.medtech_trial_scandal(drug)
	if bool(r.get("exposed", false)):
		return _fail("试验丑闻曝光，罚款 %d，合规下降。" % int(r.get("fine", 0)))
	return _ok(["试验争议未被曝光。"], 0, "")

func _catalog_name(items: Array, id: String) -> String:
	for it in items:
		if it is Dictionary and String((it as Dictionary).get("id", "")) == id:
			return String((it as Dictionary).get("name", id))
	return id

func _content_new_studio(intent) -> Dictionary:
	var nm: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.content_new_studio(nm)
	if not bool(r.get("ok", false)):
		return _fail("无法开办工作室（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["开办文娱工作室「%s」，可开始招募团队。" % String(r.get("name", "工作室"))], 0, "")

func _content_hire(intent) -> Dictionary:
	var role: String = _object_id(intent, "content_role")
	if role.is_empty():
		return _fail("请指明团队角色。")
	var count: int = maxi(1, _param_number(intent, "number", 1))
	var r: Dictionary = host.content_hire(role, count)
	if not bool(r.get("ok", false)):
		return _fail("无法招募（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["招募 %d 名%s，耗费 %d，团队技能 %.0f%%。" % [count, _catalog_name(host.content_roles_catalog(), role), int(r.get("cost", 0)), float(r.get("skill", 0.0)) * 100.0]], 0, "")

func _content_fire(intent) -> Dictionary:
	var role: String = _object_id(intent, "content_role")
	if role.is_empty():
		return _fail("请指明团队角色。")
	var count: int = maxi(1, _param_number(intent, "number", 1))
	var r: Dictionary = host.content_fire(role, count)
	if not bool(r.get("ok", false)):
		return _fail("无法裁撤（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["裁撤%s，现有 %d 人。" % [_catalog_name(host.content_roles_catalog(), role), int(r.get("count", 0))]], 0, "")

func _content_new_work(intent) -> Dictionary:
	var ctype: String = _object_id(intent, "content_type")
	if ctype.is_empty():
		return _fail("请指明作品类型。")
	var title: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.content_new_work(ctype, title)
	if not bool(r.get("ok", false)):
		return _fail("无法立项（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["立项《%s》。" % String(r.get("name", title))], 0, "")

func _content_manage(intent) -> Dictionary:
	var mgmt: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.content_manage(mgmt)
	if not bool(r.get("ok", false)):
		return _fail("无法调整项目管理（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["项目管理效率调整，进度倍率 %.2f。" % float(r.get("speed_mult", 1.0))], 0, "")

func _content_advance(intent) -> Dictionary:
	var days: float = float(maxi(1, _param_number(intent, "number", 30)))
	var r: Dictionary = host.content_advance(days)
	if not bool(r.get("ok", false)):
		return _fail("无法推进创作（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var extra: String = "，已完成可发行" if bool(r.get("ready", false)) else ""
	return _ok(["推进创作 %d 日，进度 %.0f/%.0f，质量 %.0f%%%s。" % [int(days), float(r.get("progress", 0.0)), float(r.get("required", 1.0)), float(r.get("quality", 0.0)) * 100.0, extra]], 0, "")

func _content_release(intent) -> Dictionary:
	var r: Dictionary = host.content_release()
	if not bool(r.get("ok", false)):
		return _fail("无法发行（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var label: String = "爆款" if bool(r.get("hit", false)) else ("扑街" if bool(r.get("flop", false)) else "平平")
	return _ok(["作品发行完毕，判定为%s，表现 %.0f%%。" % [label, float(r.get("performance", 0.0)) * 100.0]], 0, "")

func _content_monetize(intent) -> Dictionary:
	var channel: String = _object_id(intent, "content_channel")
	if channel.is_empty():
		return _fail("请指明变现渠道。")
	var r: Dictionary = host.content_monetize(channel)
	if not bool(r.get("ok", false)):
		return _fail("无法变现（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["渠道变现收入 %d。" % int(r.get("revenue", 0))], 0, "")

func _content_register_ip(intent) -> Dictionary:
	var r: Dictionary = host.content_register_ip()
	if not bool(r.get("ok", false)):
		return _fail("无法登记版权（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["登记作品版权，IP 势能 %.0f%%。" % (float((r.get("ip", {}) as Dictionary).get("power", 0.0)) * 100.0)], 0, "")

func _content_adapt(intent) -> Dictionary:
	var ttype: String = _object_id(intent, "content_type")
	if ttype.is_empty():
		return _fail("请指明改编类型。")
	var r: Dictionary = host.content_adapt(ttype)
	if not bool(r.get("ok", false)):
		return _fail("无法改编（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["改编为%s，质量 %.0f%%。" % [_catalog_name(host.content_types_catalog(), ttype), float(r.get("quality", 0.0)) * 100.0]], 0, "")

func _content_operate(intent) -> Dictionary:
	var op: String = _object_id(intent, "ip_operation")
	if op.is_empty():
		return _fail("请指明 IP 运营方式。")
	var scale: float = float(maxi(1, _param_number(intent, "number", 1000000)))
	var r: Dictionary = host.content_operate_ip(op, scale)
	if not bool(r.get("ok", false)):
		return _fail("无法运营 IP（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["IP %s 收入 %d。" % [_catalog_name(host.content_ip_operations_catalog(), op), int(r.get("revenue", 0))]], 0, "")

func _content_ip_universe(intent) -> Dictionary:
	var r: Dictionary = host.content_ip_universe()
	if not bool(r.get("ok", false)):
		return _fail("无法构建 IP 宇宙（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("universe", false)):
		return _ok(["IP 不足两部，暂无法构建宇宙。"], 0, "")
	return _ok(["构建 IP 宇宙，加成 %.0f%%。" % (float(r.get("bonus", 0.0)) * 100.0)], 0, "")

func _content_plagiarism(intent) -> Dictionary:
	var similarity: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.content_plagiarism(similarity, 0.6)
	if not bool(r.get("ok", false)):
		return _fail("无法查重（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _ok(["查重发现抄袭，争议上升。"], 0, "")
	return _ok(["查重未发现明显抄袭。"], 0, "")

func _content_compliance(intent) -> Dictionary:
	var risk: float = clampf(float(_param_number(intent, "number", 30)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.content_compliance(risk)
	if not bool(r.get("ok", false)):
		return _fail("无法审查（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["内容审查%s。" % ("通过" if bool(r.get("approved", false)) else "未通过，记录违规")], 0, "")

func _content_takedown(intent) -> Dictionary:
	var reason: String = String(intent.params.get("method", "content_violation"))
	var r: Dictionary = host.content_takedown(reason, 0.7)
	if not bool(r.get("ok", false)):
		return _fail("无法下架（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["作品已下架，罚款 %d，声誉受损。" % int(r.get("penalty", 0))], 0, "")

func _content_scandal(intent) -> Dictionary:
	var severity: float = clampf(float(_param_number(intent, "number", 60)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.content_scandal(severity, 0.7)
	if not bool(r.get("ok", false)):
		return _fail("无法结算翻车（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("occurred", false)):
		return _ok(["本次未发生翻车事件。"], 0, "")
	return _ok(["艺人翻车曝光，声誉下降。"], 0, "")

func _content_funding(intent) -> Dictionary:
	var stage: String = _object_id(intent, "funding_stage")
	if stage.is_empty():
		stage = String(intent.params.get("method", "seed")).strip_edges()
	if not host.content_industry.FUNDING_STAGES.has(stage):
		return _fail("未知融资轮次。")
	var r: Dictionary = host.content_funding(stage)
	if not bool(r.get("ok", false)):
		return _fail("无法融资（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["完成%s融资，估值 %d，到账 %d。" % [_catalog_name(host.content_funding_stages_catalog(), stage), int(r.get("valuation", 0)), int(r.get("investment", 0))]], 0, "")

func _content_poach(intent) -> Dictionary:
	var role: String = _object_id(intent, "content_role")
	if role.is_empty():
		return _fail("请指明挖角角色。")
	var r: Dictionary = host.content_poach(role, 2.0)
	if not bool(r.get("ok", false)):
		return _fail("无法挖角（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("success", false)):
		return _ok(["挖角失败。"], 0, "")
	return _ok(["挖角成功，耗费 %d。" % int(r.get("cost", 0))], 0, "")

func _content_approval(intent) -> Dictionary:
	var ctype: String = _object_id(intent, "content_type")
	if ctype.is_empty():
		return _fail("请指明内容类型。")
	var r: Dictionary = host.content_approval(ctype, 0.5)
	if not bool(r.get("ok", false)):
		return _fail("无法送审（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var extra: String = "获批" if bool(r.get("approved", false)) else "未获批"
	return _ok(["版号审批%s，延误 %d 日。" % [extra, int(round(float(r.get("delay_days", 0.0))))]], 0, "")

func _content_fandom(intent) -> Dictionary:
	var growth: float = clampf(float(_param_number(intent, "number", 10)) / 100.0, -1.0, 3.0)
	var r: Dictionary = host.content_fandom(growth)
	if not bool(r.get("ok", false)):
		return _fail("无法运营粉丝（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var extra: String = "，出现粉丝反噬" if bool(r.get("backlash", false)) else ""
	return _ok(["粉丝规模 %d，毒性 %.0f%%%s。" % [int(r.get("fandom_size", 0)), float(r.get("toxicity", 0.0)) * 100.0, extra]], 0, "")

func _eng_new_contractor(intent) -> Dictionary:
	var q: String = _object_id(intent, "engineering_qualification")
	if q.is_empty():
		q = "second"
	var nm: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.eng_new_contractor(nm, q)
	if not bool(r.get("ok", false)):
		return _fail("无法成立工程公司（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["成立「%s」，资质 %s。" % [String(r.get("name", "")), _catalog_name(host.engineering_qualifications_catalog(), q)]], 0, "")

func _eng_take_project(intent) -> Dictionary:
	var nm: String = String(intent.params.get("method", "")).strip_edges()
	var scale: int = maxi(1, _param_number(intent, "number", 50000000))
	var r: Dictionary = host.eng_take_project(nm, scale)
	if not bool(r.get("ok", false)):
		return _fail("无法承接工程（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["承接「%s」，规模 %d，需 %s 资质。" % [String(r.get("name", "")), scale, _catalog_name(host.engineering_qualifications_catalog(), String(r.get("required_qualification", "")))]], 0, "")

func _eng_advance(intent) -> Dictionary:
	var r: Dictionary = host.eng_advance()
	if not bool(r.get("ok", false)):
		return _fail("无法推进工程（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var stage_name: String = _catalog_name(host.engineering_stages_catalog(), String(r.get("stage", "")))
	var next_id: String = String(r.get("next", ""))
	var tail: String = "，工程完成" if next_id == "completed" else "，进入%s" % _catalog_name(host.engineering_stages_catalog(), next_id)
	return _ok(["完成%s%s，质量 %.0f%%。" % [stage_name, tail, float(r.get("quality", 0.0)) * 100.0]], 0, "")

func _eng_supervise(intent) -> Dictionary:
	var strength: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.eng_supervise(strength)
	if not bool(r.get("ok", false)):
		return _fail("无法监理（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["监理力度 %.0f%%，%s。" % [strength * 100.0, "发现质量缺陷" if bool(r.get("found_defect", false)) else "未发现缺陷"]], 0, "")

func _eng_tender(intent) -> Dictionary:
	var r: Dictionary = host.eng_tender()
	if not bool(r.get("ok", false)):
		return _fail("无法招标（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if String(r.get("winner", "")) == "contractor.player":
		return _ok(["招标中标，赢得工程。"], 0, "")
	return _ok(["招标未中标，工程由 %s 获得。" % _eng_rival_name(String(r.get("winner", "")))], 0, "")

func _eng_rig(intent) -> Dictionary:
	var r: Dictionary = host.eng_rig()
	if not bool(r.get("ok", false)):
		return _fail("无法围标（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["已串通陪标，抬高本家中标率。"], 0, "")

func _eng_bribe(intent) -> Dictionary:
	var amount: int = maxi(0, _param_number(intent, "number", 5000000))
	var r: Dictionary = host.eng_bribe(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法行贿（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		var extra: String = "，并追究刑责" if bool(r.get("criminal", false)) else ""
		return _ok(["行贿被查处，罚款 %d%s。" % [int(r.get("fine", 0)), extra]], 0, "")
	return _ok(["行贿未被查处，中标加成 %.0f%%。" % (float(r.get("collusion_bonus", 0.0)) * 100.0)], 0, "")

func _eng_cut_corners(intent) -> Dictionary:
	var degree: float = clampf(float(_param_number(intent, "number", 30)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.eng_cut_corners(degree)
	if not bool(r.get("ok", false)):
		return _fail("无法减料（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["偷工减料 %.0f%%，省 %d，质量降至 %.0f%%。" % [degree * 100.0, int(r.get("saved", 0)), float(r.get("quality", 0.0)) * 100.0]], 0, "")

func _eng_accident(intent) -> Dictionary:
	var r: Dictionary = host.eng_accident()
	if not bool(r.get("ok", false)):
		return _fail("无法结算事故（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("occurred", false)):
		return _ok(["本次未发生工程事故。"], 0, "")
	var acct: Dictionary = r.get("accountability", {})
	return _ok(["发生工程事故，损失 %d，死亡 %d 人，罚款 %d%s。" % [int(r.get("loss", 0)), int(r.get("deaths", 0)), int(acct.get("fine", 0)), "，追究刑责" if bool(acct.get("criminal", false)) else ""]], 0, "")

func _eng_arrears(intent) -> Dictionary:
	var amount: int = maxi(0, _param_number(intent, "number", 10000000))
	var r: Dictionary = host.eng_arrears(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法结算欠款（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["拖欠 %d，%s，利息 %d。" % [amount, "资金不足停工" if bool(r.get("stop_work", false)) else "尚可垫付", int(r.get("interest", 0))]], 0, "")

func _eng_debt_chain(intent) -> Dictionary:
	var amount: int = maxi(0, _param_number(intent, "number", 10000000))
	var r: Dictionary = host.eng_debt_chain(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法结算三角债（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["三角债违约 %d 家，累积欠款 %d。" % [int(r.get("default_count", 0)), int(r.get("total_arrears", 0))]], 0, "")

func _eng_new_city(intent) -> Dictionary:
	var nm: String = String(intent.params.get("method", "")).strip_edges()
	var pop: int = maxi(0, _param_number(intent, "number", 1000000))
	var r: Dictionary = host.eng_new_city(nm, pop)
	if not bool(r.get("ok", false)):
		return _fail("无法规划新城（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["设立城市「%s」，人口 %d。" % [String(r.get("name", "")), pop]], 0, "")

func _eng_rezone(intent) -> Dictionary:
	var ztype: String = _object_id(intent, "engineering_zone")
	if ztype.is_empty():
		return _fail("请指明功能区类型。")
	var zone_id: String = _catalog_name(host.engineering_zone_types_catalog(), ztype)
	var r: Dictionary = host.eng_rezone(zone_id, ztype)
	if not bool(r.get("ok", false)):
		return _fail("无法变更用地（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["划为%s，地价 %.0f，人口变动 %d。" % [zone_id, float(r.get("new_land_price", 0.0)), int(r.get("population_delta", 0))]], 0, "")

func _eng_transport(intent) -> Dictionary:
	var ztype: String = _object_id(intent, "engineering_zone")
	if ztype.is_empty():
		return _fail("请指明功能区。")
	var zone_id: String = _catalog_name(host.engineering_zone_types_catalog(), ztype)
	var r: Dictionary = host.eng_transport(zone_id)
	if not bool(r.get("ok", false)):
		return _fail("无法建设交通（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["交通改善，沿线地价 +%.0f。" % float(r.get("land_delta", 0.0))], 0, "")

func _eng_planning_corruption(intent) -> Dictionary:
	var bribe: int = maxi(0, _param_number(intent, "number", 10000000))
	var r: Dictionary = host.eng_planning_corruption(bribe)
	if not bool(r.get("ok", false)):
		return _fail("无法调规（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _ok(["违规调规被查处，罚款 %d。" % int(r.get("fine", 0))], 0, "")
	return _ok(["违规调规，地价虚高 %.0f%%。" % (float(r.get("land_bubble", 0.0)) * 100.0)], 0, "")

func _eng_demolition(intent) -> Dictionary:
	var ztype: String = _object_id(intent, "engineering_zone")
	if ztype.is_empty():
		return _fail("请指明功能区。")
	var zone_id: String = _catalog_name(host.engineering_zone_types_catalog(), ztype)
	var comp: int = maxi(0, _param_number(intent, "number", 300000))
	var r: Dictionary = host.eng_demolition(zone_id, 1000, comp)
	if not bool(r.get("ok", false)):
		return _fail("无法拆迁（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var extra: String = "" if bool(r.get("fair", false)) else "，%d 户产生纠纷" % int(r.get("disputes", 0))
	return _ok(["拆迁 %d 人，补偿 %d%s。" % [int(r.get("residents", 0)), int(r.get("compensation", 0)), extra]], 0, "")

func _eng_new_developer(intent) -> Dictionary:
	var nm: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.eng_new_developer(nm, 50000000)
	if not bool(r.get("ok", false)):
		return _fail("无法成立地产公司（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["成立地产公司「%s」。" % String(r.get("name", ""))], 0, "")

func _eng_pre_sale(intent) -> Dictionary:
	var units: int = maxi(1, _param_number(intent, "number", 10))
	var r: Dictionary = host.eng_pre_sale(units, 1000000)
	if not bool(r.get("ok", false)):
		return _fail("无法预售（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["预售 %d 套，回笼资金 %d，现金 %d。" % [units, int(r.get("income", 0)), int(r.get("cash", 0))]], 0, "")

func _eng_develop(intent) -> Dictionary:
	var cost: int = maxi(0, _param_number(intent, "number", 5000000))
	var r: Dictionary = host.eng_develop(cost)
	if not bool(r.get("ok", false)):
		return _fail("无法推进楼盘（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["投入 %d，楼盘进度 %.0f%%。" % [cost, float(r.get("progress", 0.0)) * 100.0]], 0, "")

func _eng_unfinished(intent) -> Dictionary:
	var r: Dictionary = host.eng_unfinished()
	if not bool(r.get("ok", false)):
		return _fail("无法结算楼盘（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("stalled", false)):
		return _ok(["资金充足，楼盘未烂尾。"], 0, "")
	return _ok(["资金断裂，楼盘烂尾，缺 %d，买家受损 %d。" % [int(r.get("deficit", 0)), int(r.get("buyers_lost", 0))]], 0, "")

func _eng_rival_name(id: String) -> String:
	for rv in host._eng_rivals:
		if String((rv as Dictionary).get("id", "")) == id:
			return String((rv as Dictionary).get("name", id))
	return id if id != "" else "其他单位"

func _prof_new_firm(intent) -> Dictionary:
	var nm: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.prof_new_firm(nm)
	if not bool(r.get("ok", false)):
		return _fail("无法开办事务所（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["开办事务所「%s」。" % String(r.get("name", ""))], 0, "")

func _prof_acquire(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var cert: String = _object_id(intent, "prof_cert")
	if cert.is_empty():
		return _fail("请指明执业资质。")
	var r: Dictionary = host.prof_acquire(cert)
	if not bool(r.get("ok", false)):
		return _fail("无法考取资质（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["%s%s，报考费 %d。" % [("考取" if bool(r.get("passed", false)) else "未通过"), _catalog_name(host.prof_qualifications_catalog(), cert), int(r.get("fee", 0))]], 0, "")

func _prof_client(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var r: Dictionary = host.prof_client()
	if not bool(r.get("ok", false)):
		return _fail("无法开发客户（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("success", false)):
		return _ok(["客户开发未果。"], 0, "")
	return _ok(["开发客户成功，规模 %d。" % int(r.get("size", 0))], 0, "")

func _prof_new_project(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var practice: String = _object_id(intent, "prof_practice")
	if practice.is_empty():
		return _fail("请指明执业类型。")
	var client: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.prof_new_project(practice, client)
	if not bool(r.get("ok", false)):
		return _fail("无法立项（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var p: Dictionary = r.get("project", {})
	return _ok(["立项%s项目，费用 %d。" % [_catalog_name(host.prof_practice_types_catalog(), practice), int(p.get("fee", 0))]], 0, "")

func _prof_due_diligence(intent) -> Dictionary:
	if host._prof_project.is_empty():
		return _fail("尚无立项项目。")
	var depth: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.prof_due_diligence(depth)
	if not bool(r.get("ok", false)):
		return _fail("无法尽调（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["尽职调查完成，发现 %d 项问题。" % (r.get("findings", []) as Array).size()], 0, "")

func _prof_ma(intent) -> Dictionary:
	if host._prof_project.is_empty():
		return _fail("尚无立项项目。")
	var deal: int = maxi(0, _param_number(intent, "number", 10000000))
	var r: Dictionary = host.prof_ma_advisory(deal)
	if not bool(r.get("ok", false)):
		return _fail("无法顾问（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("success", false)):
		return _ok(["并购顾问未成交。"], 0, "")
	return _ok(["并购成交，抽佣 %d。" % int(r.get("fee", 0))], 0, "")

func _prof_independence(intent) -> Dictionary:
	var raw: String = String(intent.params.get("method", "")).strip_edges()
	var roles: Array = []
	if not raw.is_empty():
		for part in raw.split("+"):
			var s: String = String(part).strip_edges()
			if not s.is_empty():
				roles.append(s)
	var r: Dictionary = host.prof_independence(roles)
	return _ok(["独立性审查：%s。" % ("存在角色冲突" if bool(r.get("conflict", false)) else "无冲突")], 0, "")

func _prof_false_report(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var sev: float = clampf(float(_param_number(intent, "number", 60)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.prof_false_report(sev)
	if not bool(r.get("ok", false)):
		return _fail("无法出具报告（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _ok(["虚假报告被查处，罚款 %d。" % int(r.get("fine", 0))], 0, "")
	return _ok(["出具虚假报告，未被查处但声誉受损。"], 0, "")

func _prof_insider(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var profit: int = maxi(0, _param_number(intent, "number", 1000000))
	var r: Dictionary = host.prof_insider(profit)
	if not bool(r.get("ok", false)):
		return _fail("无法交易（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _ok(["内幕交易被查处，罚款 %d%s。" % [int(r.get("fine", 0)), "，触刑" if bool(r.get("legal", false)) else ""]], 0, "")
	return _ok(["内幕交易获利 %d，未被查处。" % profit], 0, "")

func _prof_bribery(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var amount: int = maxi(0, _param_number(intent, "number", 500000))
	var r: Dictionary = host.prof_bribery(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法处理（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("exposed", false)):
		return _ok(["商业贿赂被查处，罚款 %d%s。" % [int(r.get("fine", 0)), "，触刑" if bool(r.get("legal", false)) else ""]], 0, "")
	return _ok(["商业贿赂未被查处。"], 0, "")

func _prof_add_partner(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var pid: String = String(intent.params.get("method", "")).strip_edges()
	if pid.is_empty():
		return _fail("请指明合伙人姓名。")
	var share: float = clampf(float(_param_number(intent, "number", 20)) / 100.0, 0.0, 0.9)
	var r: Dictionary = host.prof_add_partner(pid, share, 0)
	if not bool(r.get("ok", false)):
		return _fail("无法吸收合伙人（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["吸收合伙人「%s」，份额 %.0f%%。" % [pid, share * 100.0]], 0, "")

func _prof_split(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var pid: String = String(intent.params.get("method", "")).strip_edges()
	if pid.is_empty():
		return _fail("请指明合伙人姓名。")
	var r: Dictionary = host.prof_partner_split(pid)
	if not bool(r.get("ok", false)):
		return _fail("无法拆伙（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["合伙人「%s」分裂，带走 %d 名客户。" % [pid, int(r.get("clients_carried", 0))]], 0, "")

func _prof_non_compete(intent) -> Dictionary:
	var r: Dictionary = host.prof_non_compete()
	if bool(r.get("violation", false)):
		return _ok(["违反竞业限制，赔偿 %d。" % int(r.get("damages", 0))], 0, "")
	return _ok(["无竞业违约。"], 0, "")

func _prof_churn(intent) -> Dictionary:
	if host.professional_firm().is_empty():
		return _fail("尚未开办事务所。")
	var r: Dictionary = host.prof_churn()
	if not bool(r.get("ok", false)):
		return _fail("无法结算流失（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["客户流失 %d 名。" % int(r.get("lost", 0))], 0, "")

func _life_new_provider(intent) -> Dictionary:
	var category: String = _object_id(intent, "life_service_category")
	if category.is_empty():
		category = "housekeeping"
	var nm: String = String(intent.params.get("method", "")).strip_edges()
	var r: Dictionary = host.life_new_provider(nm, category)
	if not bool(r.get("ok", false)):
		return _fail("无法登记服务者（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["登记服务者「%s」，类别 %s。" % [String(r.get("name", "")), _catalog_name(host.life_service_categories_catalog(), category)]], 0, "")

func _life_background(intent) -> Dictionary:
	if host.life_provider().is_empty():
		return _fail("尚未登记服务者。")
	var r: Dictionary = host.life_background_check()
	if not bool(r.get("ok", false)):
		return _fail("无法核查（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("flagged", false)):
		return _ok(["背景核查发现不良记录，信任下降。"], 0, "")
	return _ok(["背景核查清白，信任提升。"], 0, "")

func _life_new_order(intent) -> Dictionary:
	if host.life_provider().is_empty():
		return _fail("尚未登记服务者。")
	var service: String = String(intent.params.get("method", "")).strip_edges()
	var price: int = maxi(0, _param_number(intent, "number", 1000))
	var r: Dictionary = host.life_new_order(service, price)
	if not bool(r.get("ok", false)):
		return _fail("无法下单（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var o: Dictionary = r.get("order", {})
	return _ok(["预约服务单「%s」，价格 %d。" % [String(o.get("service", "")), int(o.get("price", 0))]], 0, "")

func _life_matchmaking(intent) -> Dictionary:
	if host.life_provider().is_empty():
		return _fail("尚未登记服务者。")
	var r: Dictionary = host.life_matchmaking()
	if not bool(r.get("ok", false)):
		return _fail("无法相亲（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if not bool(r.get("matched", false)):
		return _ok(["相亲未配对。"], 0, "")
	var m: Dictionary = r.get("match", {})
	return _ok(["相亲配对成功：%s。" % String(m.get("name", ""))], 0, "")

func _life_wedding(intent) -> Dictionary:
	if host._life_order.is_empty():
		return _fail("尚无服务单。")
	var budget: int = maxi(0, _param_number(intent, "number", 50000))
	var r: Dictionary = host.life_wedding(budget, 0.6)
	if not bool(r.get("ok", false)):
		return _fail("无法策划（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("accident", false)):
		return _ok(["婚礼策划出现事故，成本 %d。" % int(r.get("cost", 0))], 0, "")
	return _ok(["婚礼策划完成，成本 %d。" % int(r.get("cost", 0))], 0, "")

func _life_housekeeping(intent) -> Dictionary:
	if host._life_order.is_empty():
		return _fail("尚无服务单。")
	var r: Dictionary = host.life_housekeeping()
	if not bool(r.get("ok", false)):
		return _fail("无法服务（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var incident: String = String(r.get("incident", ""))
	if incident == "theft":
		return _ok(["家政服务发生盗窃。"], 0, "")
	if incident == "negligence":
		return _ok(["家政服务出现失职。"], 0, "")
	return _ok(["家政服务完成。"], 0, "")

func _life_maternity(intent) -> Dictionary:
	if host._life_order.is_empty():
		return _fail("尚无服务单。")
	host._life_order["service"] = "maternity"
	var r: Dictionary = host.life_housekeeping()
	if not bool(r.get("ok", false)):
		return _fail("无法照料（%s）。" % _reason_cn(String(r.get("reason", ""))))
	var incident: String = String(r.get("incident", ""))
	var tail: String = "（发生盗窃）" if incident == "theft" else ("（出现失职）" if incident == "negligence" else "")
	return _ok(["月嫂照料完成%s。" % tail], 0, "")

func _life_pet(intent) -> Dictionary:
	if host._life_order.is_empty():
		return _fail("尚无服务单。")
	var stage: String = _object_id(intent, "life_pet_stage")
	if stage.is_empty():
		return _fail("请指明宠物服务环节。")
	var r: Dictionary = host.life_pet_service(stage)
	if not bool(r.get("ok", false)):
		return _fail("无法服务（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["宠物%s%s。" % [_catalog_name(host.life_pet_service_catalog(), stage), "完成" if bool(r.get("completed", false)) else "出现事故"]], 0, "")

func _life_incident(intent) -> Dictionary:
	if host.life_provider().is_empty():
		return _fail("尚未登记服务者。")
	var sev: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.life_incident(sev)
	if not bool(r.get("ok", false)):
		return _fail("无法结算（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("occurred", false)):
		return _ok(["发生服务事故，严重度 %.0f%%。" % (float(r.get("severity", 0.0)) * 100.0)], 0, "")
	return _ok(["未发生服务事故。"], 0, "")

func _life_dispute(intent) -> Dictionary:
	if host._life_order.is_empty():
		return _fail("尚无服务单。")
	var claim: int = maxi(0, _param_number(intent, "number", 0))
	var r: Dictionary = host.life_resolve_dispute(claim, 0.5)
	if not bool(r.get("ok", false)):
		return _fail("无法处理（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("legal", false)):
		return _ok(["纠纷上升为法律后果，赔偿 %d。" % int(r.get("compensation", 0))], 0, "")
	return _ok(["纠纷投诉处理，赔偿 %d。" % int(r.get("compensation", 0))], 0, "")

func _life_commission(intent) -> Dictionary:
	if host.life_provider().is_empty():
		return _fail("尚未登记服务者。")
	var price: int = maxi(0, _param_number(intent, "number", 1000))
	var r: Dictionary = host.life_commission(price)
	if not bool(r.get("ok", false)):
		return _fail("无法结算（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["平台抽成 %d，服务者实收 %d。" % [int(r.get("commission", 0)), int(r.get("provider_received", 0))]], 0, "")

func _life_standardize(intent) -> Dictionary:
	if host.life_provider().is_empty():
		return _fail("尚未登记服务者。")
	var invest: int = maxi(0, _param_number(intent, "number", 100000))
	var r: Dictionary = host.life_standardize(invest, 0.5)
	if not bool(r.get("ok", false)):
		return _fail("无法标准化（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["服务标准化投入 %d。" % int(r.get("invest", 0))], 0, "")

func _tin_new_project(intent) -> Dictionary:
	var type: String = _object_id(intent, "tin_infra_type")
	if type.is_empty():
		type = "highway"
	var scale: float = maxf(0.1, float(_param_number(intent, "number", 100)) / 100.0)
	var r: Dictionary = host.tin_new_project(type, scale)
	var p: Dictionary = r.get("project", {})
	return _ok(["立项%s，预算 %d。" % [_catalog_name(host.tin_infra_types_catalog(), type), int(p.get("cost_estimate", 0))]], 0, "")

func _tin_tender(intent) -> Dictionary:
	if host._tin_project.is_empty():
		return _fail("尚无基建项目。")
	var r: Dictionary = host.tin_tender()
	if not bool(r.get("ok", false)):
		return _fail("无法招标（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["基建招标定标：%s。" % String(r.get("winner", ""))], 0, "")

func _tin_build(intent) -> Dictionary:
	if host._tin_project.is_empty():
		return _fail("尚无基建项目。")
	var pace: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.tin_build(pace)
	if not bool(r.get("ok", false)):
		return _fail("无法推进（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["基建推进，进度 %.0f%%，超支 %d。" % [float(r.get("progress", 0.0)) * 100.0, int(r.get("overrun", 0))]], 0, "")

func _tin_operate(intent) -> Dictionary:
	if host._tin_project.is_empty():
		return _fail("尚无基建项目。")
	var mode: String = _object_id(intent, "tin_mode")
	if mode.is_empty():
		mode = "logistics"
	var fare: float = float(_param_number(intent, "number", 50))
	var r: Dictionary = host.tin_operate(mode, fare)
	if not bool(r.get("ok", false)):
		return _fail("无法运营（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["线路运营一期，盈亏 %d，准点率 %.0f%%。" % [int(r.get("profit", 0)), float(r.get("on_time_rate", 0.0)) * 100.0]], 0, "")

func _tin_regional(intent) -> Dictionary:
	if host._tin_project.is_empty():
		return _fail("尚无基建项目。")
	var r: Dictionary = host.tin_regional_impact()
	if not bool(r.get("ok", false)):
		return _fail("无法评估（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["区域影响：可达性 %.0f%%，地价 +%.0f%%。" % [float(r.get("accessibility", 0.0)) * 100.0, float(r.get("land_delta", 0.0)) * 100.0]], 0, "")

func _tin_network(intent) -> Dictionary:
	var r: Dictionary = host.tin_network()
	return _ok(["路网效应：连通度 %.0f%%，换乘效率 %.0f%%。" % [float(r.get("connectivity", 0.0)) * 100.0, float(r.get("transfer_efficiency", 0.0)) * 100.0]], 0, "")

func _tin_subsidy(intent) -> Dictionary:
	if host._tin_project.is_empty():
		return _fail("尚无基建项目。")
	var amount: int = _param_number(intent, "number", -1)
	var r: Dictionary = host.tin_subsidy(amount)
	if not bool(r.get("ok", false)):
		return _fail("无法补贴（%s）。" % _reason_cn(String(r.get("reason", ""))))
	return _ok(["补贴 %d。" % int(r.get("granted", 0))], 0, "")

func _tin_settle(intent) -> Dictionary:
	if host._tin_project.is_empty():
		return _fail("尚无基建项目。")
	var r: Dictionary = host.tin_settle()
	return _ok(["基建结算：工期 %.0f 天，成本 %d，安全 %.0f%%。" % [float(r.get("construction_days", 0.0)), int(r.get("cost", 0)), float(r.get("safety", 0.0)) * 100.0]], 0, "")

func _tin_accident(intent) -> Dictionary:
	if host._tin_project.is_empty():
		return _fail("尚无基建项目。")
	var cut: float = clampf(float(_param_number(intent, "number", 0)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.tin_accident(cut)
	if not bool(r.get("ok", false)):
		return _fail("无法结算（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("occurred", false)):
		return _ok(["基建重大事故，损失 %d，死亡 %d。" % [int(r.get("loss", 0)), int(r.get("deaths", 0))]], 0, "")
	return _ok(["基建安全无事故。"], 0, "")

func _tin_monopoly(intent) -> Dictionary:
	var share: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.tin_monopoly(share, 100.0)
	if String(r.get("action", "none")) == "price_cap":
		return _ok(["触发限价监管，罚款 %d。" % int(r.get("fine", 0))], 0, "")
	return _ok(["未触发定价监管。"], 0, "")

func _tin_disruption(intent) -> Dictionary:
	if host._tin_route.is_empty():
		return _fail("尚无运营线路。")
	var sens: float = clampf(float(_param_number(intent, "number", 50)) / 100.0, 0.0, 1.0)
	var r: Dictionary = host.tin_disruption(sens)
	if not bool(r.get("ok", false)):
		return _fail("无法结算（%s）。" % _reason_cn(String(r.get("reason", ""))))
	if bool(r.get("disrupted", false)):
		return _ok(["国际扰动致航线中断，损失 %d。" % int(r.get("loss", 0))], 0, "")
	return _ok(["国际局势平稳，航线正常。"], 0, "")

func _reason_cn(reason: String) -> String:
	match reason:
		"dead":
			return "角色已死亡"
		"in_prison":
			return "你正在服刑"
		"not_inside":
			return "当前不在押"
		"still_inside":
			return "仍在服刑中"
		"not_wanted":
			return "当前未被通缉"
		"unknown_crime":
			return "未知罪名"
		"unknown_region":
			return "未知区域"
		"behavior_too_low":
			return "服刑表现不足"
		"unknown_gang":
			return "未知狱帮"
		"insufficient_cash":
			return "现金不足"
		"insufficient_holding":
			return "持仓不足"
		"unknown_security":
			return "未知证券"
		"bad_order":
			return "交易参数无效"
		"not_listed", "unavailable":
			return "此房源不可交易"
		"not_owned":
			return "你并不拥有这套房产"
		"purchase_restricted":
			return "受限购政策限制"
		"insufficient_funds":
			return "资金不足"
		"no_economy":
			return "经济系统未就绪"
		"not_applicable":
			return "该辅具不适用于现有残障类型"
		"has_capacity":
			return "当事人仍具备决策能力，无需监护"
		"unknown_device":
			return "未知辅具"
		"unknown_mode":
			return "未知养老模式"
		"unknown_mfg_mode":
			return "未知经营模式"
		"not_qualified":
			return "资质或资本不足"
		"no_upgrade_path":
			return "不存在该升级路径"
		"unknown_crop":
			return "未知作物"
		"unknown_animal":
			return "未知牲畜"
		"unknown_use":
			return "未知土地用途"
		"unknown_channel":
			return "未知销售渠道"
		"no_land":
			return "尚未取得土地"
		"no_plot":
			return "指定地块不存在"
		"no_stock":
			return "库存不足"
		"no_order":
			return "订单不存在"
		"unknown_platform":
			return "未知平台"
		"unknown_job":
			return "未知网络安全工作"
		"unknown_target":
			return "未知目标"
		"banned":
			return "账号已被封禁"
		"unknown_career":
			return "未知科技职业"
		"unknown_mission":
			return "未知科技任务"
		"unknown_stage":
			return "未知科技阶段"
		"stage_locked":
			return "该内容尚未解锁"
		"skill_too_low":
			return "技能等级不足"
		"already_unlocked":
			return "该阶段已解锁"
		"locked":
			return "需先解锁前置阶段"
		"max_stage":
			return "已达最高科技阶段"
		"era_before_late_tech":
			return "时代尚未进入后期科技"
		"unknown_ip_type":
			return "未知知识产权类型"
		"unknown_ip":
			return "未找到该知识产权"
		"unknown_media_type":
			return "未知媒体类型"
		"unknown_outlet":
			return "未找到该媒体机构"
		"public_domain":
			return "该知识产权已进入公有领域"
		"perpetual_or_expired":
			return "该知识产权为无限期或已到期"
		"article_not_found":
			return "未找到该稿件"
		"unknown_mfg_mode":
			return "未知经营模式"
		"not_qualified":
			return "资质或资本不足"
		"no_upgrade_path":
			return "不存在该升级路径"
		"no_factory":
			return "尚未开办工厂"
		"unknown_recipe":
			return "未知生产配方"
		"no_supplier":
			return "该原料暂无供应商"
		"bad_quantity":
			return "数量不合法"
		"bad_batches":
			return "批次不合法"
		"disrupted":
			return "产线中断，无法生产"
		"already_fulfilled":
			return "该订单已交付完毕"
		"funding_chain_broken":
			return "资金链断裂"
		"no_shipment":
			return "尚未建立外贸单据"
		"over_capacity":
			return "超出该运输方式运力"
		"unknown_incoterm":
			return "未知贸易术语"
		"unknown_settlement":
			return "未知结算方式"
		"at_end":
			return "流程已到末段"
		"no_mine":
			return "尚未开办矿场"
		"unknown_mineral":
			return "未知矿种"
		"no_qualification":
			return "缺少所需资质"
		"insufficient_capital":
			return "资本不足"
		"not_explored":
			return "尚未勘探，无法开采"
		"no_concession":
			return "尚未取得矿权"
		"depleted":
			return "矿藏已枯竭"
		"unknown_energy_kind":
			return "未知新能源类型"
		"unknown_environment":
			return "未知极端环境"
		"unknown_barrier":
			return "未知贸易壁垒"
		"unknown_event":
			return "未知风险事件"
		"no_contract":
			return "无待结算合约"
		"no_club":
			return "尚未加入球会"
		"form_too_low":
			return "竞技状态未达征召门槛"
		"already_owns":
			return "你已拥有该项产业"
		"no_fishery":
			return "尚未开办渔场"
		"no_forest":
			return "尚未承包林场"
		"no_rights":
			return "尚未取得林权"
		"gun_policy_forbids":
			return "枪支政策不允许"
		"unknown_species":
			return "未知物种"
		"closed_season":
			return "正处于休渔期"
		"protected_area":
			return "在保护区内违法"
		"no_restaurant":
			return "尚未开办餐厅"
		"unknown_role":
			return "未知岗位"
		"hygiene_too_low":
			return "卫生条件不达标"
		"unknown_certification":
			return "未知认证"
		"not_packageable":
			return "该菜品不可预包装"
		"no_food_facility":
			return "需中央厨房或食品工业模式"
		"unknown_marketing":
			return "未知营销方式"
		"channel_disabled":
			return "该渠道未开通"
		"no_brand":
			return "尚未创立品牌"
		"bad_discipline":
			return "未知设计学科"
		"no_design":
			return "尚无作品，无法举办时装周"
		"unknown_item":
			return "未知奢侈品类目"
		"no_endorser":
			return "尚无代言人"
		"no_career":
			return "尚未开启运动生涯"
		"already_career":
			return "你已是一名职业运动员"
		"injured":
			return "伤病未愈，无法出战"
		"disabled":
			return "已因伤致残，无法出战"
		"unknown_severity":
			return "未知伤病等级"
		"unknown_scandal":
			return "未知违规类型"
		"unknown_competition":
			return "未知赛事"
		"already_planner":
			return "你已是活动策划从业者"
		"unknown_type":
			return "未知活动类型"
		"no_event":
			return "尚未筹办活动"
		"in_progress":
			return "上一场活动尚未复盘"
		"already_held":
			return "该活动已举办并复盘"
		"not_approved":
			return "活动尚未报批通过"
		"unknown_tier":
			return "未知赞助层级"
		"no_profile":
			return "尚未建立荣誉档案"
		"already_profile":
			return "你已建立荣誉档案"
		"unknown_award":
			return "未知奖项"
		"below_threshold":
			return "成就不达标"
		"jury_rejected":
			return "评审未通过"
		"no_case":
			return "尚未立案"
		"no_firm":
			return "尚未开办安保公司"
		"already_firm":
			return "你已开办安保公司"
		"no_contract":
			return "尚无待履约的安保业务"
		"unknown_kind":
			return "未知证据种类"
		"unknown_service":
			return "未知安保业务"
		"illegal_collection":
			return "非法取证，证据无效"
		"no_warrant":
			return "缺少搜查令"
		"terminal":
			return "案件已终结"
		"no_incident":
			return "当前无处置中的应急事件"
		"no_disaster":
			return "当前区域今日无天气灾害"
		"already_reported":
			return "今日灾害已接警"
		"no_org":
			return "尚未组建志愿救援队"
		"already_org":
			return "你已组建志愿救援队"
		"command_fault":
			return "指挥失当"
		"secondary_negligence":
			return "二次事故处置不力"
		"unknown_facility":
			return "未知市政设施"
		"already_under_construction":
			return "该设施已在施工中"
		"no_such_complaint":
			return "投诉编号不存在"
		"no_parcel":
			return "没有待处理的包裹"
		"no_career":
			return "尚未成为快递员"
		"already_career":
			return "你已是快递员"
		"unknown_franchise":
			return "未知特许服务"
		"no_license":
			return "缺少公用事业特许资质"
		"no_franchise":
			return "尚无特许经营合同"
		"no_item":
			return "缺少典当物品"
		"no_loan":
			return "尚无有效借款"
		"no_lend":
			return "尚无放出的贷款"
		"business_unavailable":
			return "该业务在当前时代不可用"
		"era_not_allowed":
			return "当前时代不允许个人破产"
		"already_repaid":
			return "该贷款已还清"
		"bad_status":
			return "贷款状态不允许此操作"
		"credit_below_line":
			return "信用不达标"
		"no_order":
			return "尚无消费订单"
		"no_product":
			return "尚无商品"
		"no_application":
			return "尚无申请记录"
		"no_fund":
			return "尚未设立慈善基金"
		"no_worker":
			return "尚未从事社工"
		"no_welfare_case":
			return "尚无在办个案"
		"unknown_situation":
			return "未知变故情形"
		"unknown_organ":
			return "未知器官"
		"ethics_rejected":
			return "伦理审查未通过"
		"donor_alive":
			return "生前不可撤销捐献"
		"donation_unavailable":
			return "捐献不可用（未登记或已撤销）"
		"not_arranged":
			return "尚未安排殡葬"
		"insufficient_estate":
			return "遗产不足以支付殡葬费用"
		"unknown_method":
			return "未知殡葬方式"
		"no_memorial":
			return "尚无相关纪念物"
		"no_industry":
			return "尚未开办殡葬经营体"
		"not_registered":
			return "尚未登记捐献"
		"not_unclaimed":
			return "并非无人认领情形"
		"unknown_cert":
			return "未知执业资质"
		"already_qualified":
			return "已持有该资质"
		"already_partner":
			return "该合伙人已在册"
		"not_partner":
			return "查无此合伙人"
		"bad_partner":
			return "合伙人姓名无效"
		"no_provider":
			return "尚未登记服务者"
		"unknown_category":
			return "未知服务类别"
		"unknown_pet_stage":
			return "未知宠物服务环节"
		"no_candidates":
			return "暂无相亲候选"
		"no_infra":
			return "尚无基建项目"
		"unknown_tin_mode":
			return "未知运营模式"
		"no_route":
			return "尚无运营线路"
		"no_bids":
			return "无有效投标"
		"unknown_practice":
			return "未知民俗活动"
		"no_business":
			return "尚未开办玄学业务"
		"unknown_gate":
			return "未知门闩途径"
		"unknown_identity":
			return "未知身份"
		"unknown_faction":
			return "未知阵营"
		"unknown_ability":
			return "未知能力线"
		"unknown_entry":
			return "未知异常条目"
		"unknown_hazard":
			return "未知危害类型"
		"unknown_anomaly_mission":
			return "未知异常任务"
		"insufficient_clearance":
			return "权限不足"
		"insufficient_mana":
			return "灵力不足"
		"insufficient_spirit":
			return "精神不足"
		"insufficient_sanity":
			return "理智不足"
		"limit_reached":
			return "已达记忆删除剂使用上限"
		"unknown_care_level":
			return "未知诊疗层级"
		"unknown_department":
			return "未知科室"
		"unknown_exam":
			return "未知检查项目"
		"unknown_procedure":
			return "未知医疗类目"
		"unknown_disease":
			return "未知病种"
		"unknown_medical_facility":
			return "未知医疗机构"
		"service_unavailable":
			return "该机构不提供此项服务"
		"ethics_denied":
			return "未通过伦理审查"
		"legal_denied":
			return "未通过法律审查"
		"no_organ_source":
			return "缺少器官来源"
		"illegal_organ_source":
			return "器官来源不合法"
		"no_medical_case":
			return "无对应在案病情"
		"unsupported":
			return "该病种不支持此疗法"
		"unknown_drug":
			return "未知在研药物"
		"no_company":
			return "尚未成立医药公司"
		"not_upward_referral":
			return "非向上转诊"
		"not_in_production":
			return "尚未进入生产阶段"
		"not_on_market":
			return "尚未上市销售"
		"already_exists":
			return "已存在同名项目"
		"no_studio":
			return "尚未开办文娱工作室"
		"no_work":
			return "尚无在研作品"
		"no_ip":
			return "尚无可用 IP"
		"unknown_role":
			return "未知团队角色"
		"bad_count":
			return "人数无效"
		"unknown_content_type":
			return "未知内容类型"
		"channel_inapplicable":
			return "该渠道不适用此内容类型"
		"not_ready":
			return "作品尚未开发完成"
		"already_released":
			return "作品已发行"
		"unknown_operation":
			return "未知运营方式"
		"no_target":
			return "对手无此角色可挖"
		"no_contractor":
			return "尚未成立工程公司"
		"no_project":
			return "尚无在建工程"
		"no_city":
			return "尚未规划城市"
		"no_developer":
			return "尚未成立地产公司"
		"unknown_qualification":
			return "未知资质等级"
		_:
			return reason if reason != "" else "未知原因"

# --- 通用推进与叙事 ---

## 推进 time_minutes 并生成生理概况叙事。
func _advance_time(minutes: int, opts: Dictionary, flavor_key: String = "") -> Dictionary:
	var r: Dictionary = host.advance(minutes, opts)
	var p: Dictionary = host.player()["attrs"]["physiological"]
	var events: Array = r.get("events", [])
	var lines: Array = []
	if flavor_key != "":
		lines.append(FlavorScript.time_line(flavor_key, host.now_minutes()))
	lines.append("时间推进 %s。" % _duration_text(minutes))
	if _has_event(events, "death"):
		lines.append("你走到了生命的尽头。")
	elif _has_event(events, "dying"):
		lines.append("你已油尽灯枯，随时可能离世。")
	else:
		lines.append("饱食 %.0f / 口渴 %.0f / 体力 %.0f / 健康 %.0f。" % [
			float(p.get("hunger", 0.0)), float(p.get("thirst", 0.0)),
			float(p.get("stamina", 0.0)), float(p.get("health", 0.0)),
		])
	return _ok(lines, minutes, "")

func _practice(sid: String, hours: float) -> Dictionary:
	var p: Dictionary = host.player()
	var ctx := {
		"intelligence": _attr(p, "ability", "intelligence", 50.0),
		"willpower": _attr(p, "ability", "willpower", 50.0),
		"talents": p.get("talents", []),
		"now_minute": host.now_minutes(),
	}
	return host.skills.practice(p["skills"], sid, hours, ctx)

# --- 参数与命名辅助 ---

func _duration_minutes(intent, default_minutes: int) -> int:
	if not intent.params.has("duration"):
		return default_minutes
	var value := int(intent.params.get("duration", 0))
	var unit := String(intent.params.get("duration_unit", ""))
	return maxi(1, _unit_minutes(value, unit, default_minutes))

func _unit_minutes(value: int, unit: String, default_minutes: int) -> int:
	match unit:
		"秒":
			return maxi(1, value / 60)
		"分钟":
			return value * MINUTE
		"小时":
			return value * HOUR
		"天":
			return value * DAY
		"周":
			return value * WEEK
		"月":
			return value * MONTH
		"年":
			return value * YEAR
		_:
			return default_minutes if value <= 0 else value * MINUTE

## 金额参数（元/块/万元）换算为最小货币单位整数的绝对值。
func _amount_minor(intent) -> int:
	if intent.params.has("amount"):
		var v := int(intent.params.get("amount", 0))
		var unit := String(intent.params.get("amount_unit", "元"))
		var major := float(v) * (10000.0 if unit == "万元" else 1.0)
		return int(round(major * 100.0))
	if intent.params.has("number"):
		return int(intent.params.get("number", 0)) * 100
	return 0

## 数量参数：优先 quantity，其次解析器产出的 number，缺省 1。
func _quantity(intent) -> int:
	if intent.params.has("quantity"):
		return maxi(1, int(intent.params.get("quantity", 1)))
	if intent.params.has("number"):
		return maxi(1, int(intent.params.get("number", 1)))
	return 1

func _object_id(intent, type: String) -> String:
	var o: Dictionary = intent.object_of(type)
	var id := String(o.get("id", ""))
	if not id.is_empty():
		return id
	# 解析器未能链接目录时，用方法名/名词做一次名称回退匹配。
	return _resolve_by_name(type, String(intent.params.get("method", "")))

func _resolve_by_name(type: String, text: String) -> String:
	if text.is_empty():
		return ""
	match type:
		"skill":
			return _find_by_name(host.skills, text)
		"item":
			return _find_by_name(host.items, text)
		"location":
			# 岗位/机构名回退（求职等动词不声明对象类型，名称落在 method）。
			return _find_by_name(host.jobs, text)
		"organization":
			return _find_org_by_name(text)
		"language":
			return _find_language_by_name(text)
		"culture":
			return _find_culture_by_name(text)
		"device":
			return _find_device_by_name(text)
		"care_mode":
			return _find_care_mode_by_name(text)
		"crop":
			return _find_crop_by_name(text)
		"livestock":
			return _find_livestock_by_name(text)
		"platform":
			return _find_platform_by_name(text)
		"hack_target":
			return _find_hack_target_by_name(text)
		"security_job":
			return _find_security_job_by_name(text)
		"crime":
			return _find_catalog_by_name(host.police_crimes_catalog(), text)
		"late_tech_career":
			return _find_late_tech_career_by_name(text)
		"late_tech_mission":
			return _find_late_tech_mission_by_name(text)
		"late_tech_environment":
			return _find_catalog_by_name(host.late_tech_environments_catalog(), text)
		"ip_asset":
			return _find_ip_asset_by_name(text)
		"mfg_role":
			return _find_catalog_by_name(host.mfg_roles_catalog(), text)
		"mfg_mode":
			return _find_catalog_by_name(host.mfg_modes_catalog(), text)
		"mfg_recipe":
			return _find_catalog_by_name(host.mfg_recipes_catalog(), text)
		"mfg_material":
			return _find_catalog_by_name(host.mfg_materials_catalog(), text)
		"trade_mode":
			return _find_catalog_by_name(host.trade_transport_modes_catalog(), text)
		"trade_incoterm":
			return _find_catalog_by_name(host.trade_incoterms_catalog(), text)
		"trade_settlement":
			return _find_catalog_by_name(host.trade_settlements_catalog(), text)
		"trade_barrier":
			return _find_catalog_by_name(host.trade_barriers_catalog(), text)
		"trade_risk":
			return _find_catalog_by_name(host.trade_risk_events_catalog(), text)
		"mineral":
			return _find_catalog_by_name(host.mining_minerals_catalog(), text)
		"energy_kind":
			return _find_catalog_by_name(host.mining_energy_kinds_catalog(), text)
		"energy_type":
			return _find_catalog_by_name(host.mining_energy_types_catalog(), text)
		"fish_species":
			return _find_catalog_by_name(host.fish_species_catalog(), text)
		"game_species":
			return _find_catalog_by_name(host.game_species_catalog(), text)
		"forest_type":
			return _find_catalog_by_name(host.forest_types_catalog(), text)
		"recipe":
			return _find_catalog_by_name(host.dining_recipes_catalog(), text)
		"channel":
			return _find_catalog_by_name(host.dining_channels_catalog(), text)
		"staff_role":
			return _find_catalog_by_name(host.dining_staff_roles_catalog(), text)
		"dining_mode":
			return _find_catalog_by_name(host.dining_modes_catalog(), text)
		"cert":
			return _find_catalog_by_name(host.dining_certs_catalog(), text)
		"marketing":
			return _find_catalog_by_name(host.dining_marketing_catalog(), text)
		"fashion_discipline":
			return _find_catalog_by_name(host.fashion_disciplines_catalog(), text)
		"positioning":
			return _find_catalog_by_name(host.fashion_positionings_catalog(), text)
		"luxury_item":
			return _find_catalog_by_name(host.fashion_luxury_catalog(), text)
		"fashion_marketing":
			return _find_catalog_by_name(host.fashion_marketing_catalog(), text)
		"season":
			return _find_catalog_by_name(host.fashion_seasons_catalog(), text)
		"content_role":
			return _find_catalog_by_name(host.content_roles_catalog(), text)
		"content_type":
			return _find_catalog_by_name(host.content_types_catalog(), text)
		"content_channel":
			return _find_catalog_by_name(host.content_channels_catalog(), text)
		"content_platform":
			return _find_catalog_by_name(host.content_platforms_catalog(), text)
		"ip_operation":
			return _find_catalog_by_name(host.content_ip_operations_catalog(), text)
		"funding_stage":
			return _find_funding_stage_by_name(text)
		"engineering_qualification":
			return _find_catalog_by_name(host.engineering_qualifications_catalog(), text)
		"engineering_zone":
			return _find_catalog_by_name(host.engineering_zone_types_catalog(), text)
		"prof_practice":
			return _find_catalog_by_name(host.prof_practice_types_catalog(), text)
		"prof_cert":
			return _find_catalog_by_name(host.prof_qualifications_catalog(), text)
		"life_service_category":
			return _find_catalog_by_name(host.life_service_categories_catalog(), text)
		"life_pet_stage":
			return _find_catalog_by_name(host.life_pet_service_catalog(), text)
		"tin_infra_type":
			return _find_catalog_by_name(host.tin_infra_types_catalog(), text)
		"tin_mode":
			return _find_catalog_by_name(host.tin_modes_catalog(), text)
		"competition":
			return _find_catalog_by_name(host.sports_competitions_catalog(), text)
		_:
			return ""

## 通用目录名回退：按 id 或显示名匹配条目列表（[{id,name}]）。
func _find_catalog_by_name(items: Array, text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for it in items:
		if it is Dictionary and String((it as Dictionary).get("id", "")) == needle:
			return String((it as Dictionary).get("id", ""))
	for it in items:
		if it is Dictionary and String((it as Dictionary).get("name", "")).find(needle) >= 0:
			return String((it as Dictionary).get("id", ""))
	return ""

## 融资轮次名回退：支持英文 id 与中文轮次名。
func _find_funding_stage_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	if host.content_industry.FUNDING_STAGES.has(needle):
		return needle
	var names := {"种子": "seed", "种子轮": "seed", "天使": "angel", "天使轮": "angel", "a": "a", "a轮": "a", "b": "b", "b轮": "b", "c": "c", "c轮": "c"}
	var low := needle.to_lower()
	if names.has(low):
		return String(names[low])
	if names.has(needle):
		return String(names[needle])
	return ""

## 辅具名回退：按辅具 id 或显示名匹配。
func _find_device_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.disability.DEVICES.keys():
		if String(key) == needle:
			return String(key)
	for key in host.disability.DEVICES.keys():
		if String((host.disability.DEVICES[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 养老模式名回退：按 id 或显示名匹配。
func _find_care_mode_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.disability.CARE_MODES.keys():
		if String(key) == needle:
			return String(key)
	for key in host.disability.CARE_MODES.keys():
		if String((host.disability.CARE_MODES[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 语言名回退：按语言 id 或显示名匹配。
func _find_language_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.language.LANGUAGES.keys():
		if String(key) == needle:
			return String(key)
	for key in host.language.LANGUAGES.keys():
		if String((host.language.LANGUAGES[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 文化名回退：按文化 id 或显示名匹配。
func _find_culture_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.language.CULTURES.keys():
		if String(key) == needle:
			return String(key)
	for key in host.language.CULTURES.keys():
		if String((host.language.CULTURES[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 作物名回退：按作物 id 或显示名匹配。
func _find_crop_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.agriculture.CROPS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.agriculture.CROPS.keys():
		if String((host.agriculture.CROPS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 牲畜名回退：按牲畜 id 或显示名匹配。
func _find_livestock_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.agriculture.LIVESTOCK.keys():
		if String(key) == needle:
			return String(key)
	for key in host.agriculture.LIVESTOCK.keys():
		if String((host.agriculture.LIVESTOCK[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 平台名回退：按平台 id 或显示名匹配。
func _find_platform_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.digital.CONTENT_PLATFORMS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.digital.CONTENT_PLATFORMS.keys():
		if String((host.digital.CONTENT_PLATFORMS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 黑客目标名回退：按目标 id 或显示名匹配。
func _find_hack_target_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.digital.HACK_TARGETS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.digital.HACK_TARGETS.keys():
		if String((host.digital.HACK_TARGETS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 网络安全职业名回退：按 id 或显示名匹配。
func _find_security_job_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.digital.SECURITY_JOBS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.digital.SECURITY_JOBS.keys():
		if String((host.digital.SECURITY_JOBS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 科技职业名回退：按 id 或显示名匹配。
func _find_late_tech_career_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.late_tech.CAREERS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.late_tech.CAREERS.keys():
		if String((host.late_tech.CAREERS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 科技任务名回退：按 id 或显示名匹配。
func _find_late_tech_mission_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for key in host.late_tech.MISSIONS.keys():
		if String(key) == needle:
			return String(key)
	for key in host.late_tech.MISSIONS.keys():
		if String((host.late_tech.MISSIONS[key] as Dictionary).get("name", "")).find(needle) >= 0:
			return String(key)
	return ""

## 知识产权名回退：在已登记 IP 中按 id 或标题匹配。
func _find_ip_asset_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	var ips: Array = host.ip_media_state().get("ips", [])
	for ip in ips:
		if ip is Dictionary and String((ip as Dictionary).get("id", "")) == needle:
			return String((ip as Dictionary).get("id", ""))
	for ip in ips:
		if ip is Dictionary and String((ip as Dictionary).get("title", "")).find(needle) >= 0:
			return String((ip as Dictionary).get("id", ""))
	return ""

## 组织名回退：在可加入组织与已加入组织中按名称匹配。
func _find_org_by_name(text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	var data: Dictionary = host.organizations_panel_data()
	for group in ["available", "memberships"]:
		for item in data.get(group, []):
			if not (item is Dictionary):
				continue
			var d: Dictionary = item
			if String(d.get("name", "")) == needle:
				return String(d.get("id", ""))
	for group in ["available", "memberships"]:
		for item in data.get(group, []):
			if not (item is Dictionary):
				continue
			var d: Dictionary = item
			if String(d.get("name", "")).find(needle) >= 0:
				return String(d.get("id", ""))
	return ""

## 在目录系统中按 id 或名称（含前后缀包含）查找定义 id。
func _find_by_name(system, text: String) -> String:
	var needle := text.strip_edges()
	if needle.is_empty():
		return ""
	for id in system.ids():
		var d: Dictionary = system.get_def(String(id))
		var name := String(d.get("name", ""))
		if name == needle or name.contains(needle) or needle.contains(name):
			return String(id)
	return ""

func _has_event(events: Array, kind: String) -> bool:
	for e in events:
		if typeof(e) == TYPE_DICTIONARY and String((e as Dictionary).get("type", "")) == kind:
			return true
	return false

func _first_known_skill(candidates: Array) -> String:
	for sid in candidates:
		if host.skills.has_def(String(sid)):
			return String(sid)
	return ""

func _skill_name(sid: String) -> String:
	var d: Dictionary = host.skills.get_def(sid)
	return String(d.get("name", sid))

func _item_name(item_id: String) -> String:
	var d: Dictionary = host.items.get_def(item_id)
	return String(d.get("name", item_id))

func _job_name(job_id: String) -> String:
	var d: Dictionary = host.jobs.get_def(job_id)
	return String(d.get("name", job_id))

func _attr(player: Dictionary, group: String, key: String, fallback: float) -> float:
	var g: Variant = player.get("attrs", {})
	if g is Dictionary:
		var sub: Variant = (g as Dictionary).get(group, {})
		if sub is Dictionary:
			return float((sub as Dictionary).get(key, fallback))
	return fallback

func _duration_text(minutes: int) -> String:
	if minutes % DAY == 0 and minutes >= DAY:
		return "%d 天" % (minutes / DAY)
	if minutes % HOUR == 0:
		return "%d 小时" % (minutes / HOUR)
	return "%d 分钟" % minutes

# --- 结果构造 ---

func _ok(narration: Array, minutes: int, panel: String) -> Dictionary:
	return {"ok": true, "narration": narration, "minutes": minutes, "panel": panel, "action": "", "error": ""}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "narration": [], "minutes": 0, "panel": "", "action": "", "error": message}

func _panel(id: String, hint: String) -> Dictionary:
	panels.append(id)
	return _ok([hint], 0, id)

func _action(kind: String, hint: String) -> Dictionary:
	return {"ok": true, "narration": [hint], "minutes": 0, "panel": "", "action": kind, "error": ""}

func _stub(verb: String) -> Dictionary:
	return _ok(["「%s」这个动作还没有接入模拟。" % verb], 0, "")
