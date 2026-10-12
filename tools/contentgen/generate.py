#!/usr/bin/env python3
"""浮生录内容目录生成器（任务 50）。

按 R56 内容硬指标，为 `content/catalog/<category>.json` 补齐条目。
生成是确定性的、可重复运行的：先读取现有条目并原样保留，再在无键冲突的前提下
追加程序化生成的条目，直至达到目标数量。因此重复运行不会改变既有手工条目。

用法：
    python3 tools/contentgen/generate.py            # 写入 content/catalog
    python3 tools/contentgen/generate.py --dry-run  # 只报告差异，不写文件

生成后由 `tools/contentbuilder validate/coverage` 硬阻断校验。
"""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "content" / "catalog"

KEY_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$")

TARGETS = {
    "sites": 1000,
    "place_types": 100,
    "jobs": 200,
    "skills": 140,
    "items": 1000,
    "diseases": 80,
    "certificates": 30,
    "entertainment": 100,
    "events": 300,
    "achievements": 300,
    "codex": 500,
    "transport": 12,
    "finance": 40,
    "manufacturing": 50,
    "awards": 40,
    "organizations": 30,
    "anomalies": 2000,
    "activities": 20,
    "languages": 10,
    "festivals": 10,
    "primary_industry": 30,
}

QUALITIES = ["common", "uncommon", "rare", "epic", "legendary"]
QCN = ["入门", "标准", "精良", "高端", "典藏"]


def load_entries(name: str) -> list[dict]:
    path = CATALOG / f"{name}.json"
    if not path.exists():
        return []
    doc = json.loads(path.read_text(encoding="utf-8"))
    return list(doc.get("entries", []))


def existing_keys(entries: list[dict]) -> set[str]:
    return {str(e.get("content_key", "")) for e in entries}


def slug(text: str) -> str:
    out = []
    for ch in text:
        if ch.isascii() and (ch.isalnum() or ch == "_"):
            out.append(ch.lower())
        else:
            out.append("_")
    s = "".join(out)
    s = re.sub(r"_+", "_", s).strip("_")
    if not s:
        # 非 ASCII 名称（如中文）回退为稳定 CRC32 十六进制令牌。
        import zlib
        s = "n%04x" % (zlib.crc32(text.encode("utf-8")) & 0xFFFF)
    return s


def save(name: str, entries: list[dict], dry: bool) -> int:
    entries = entries[:]
    # 补齐来源标记：缺省视为生成条目；显式 curated 的人工条目原样保留。
    for e in entries:
        e.setdefault("source", "generated")
    entries.sort(key=lambda e: e["content_key"])
    doc = {"category": name, "entries": entries}
    data = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    if not dry:
        (CATALOG / f"{name}.json").write_text(data, encoding="utf-8")
    return len(entries)


class Builder:
    """按类别累积条目，自动去重并限制到目标数量。"""

    def __init__(self, name: str):
        self.name = name
        self.target = TARGETS.get(name, 0)
        self.entries = load_entries(name)
        self.keys = existing_keys(self.entries)
        self.added = 0

    def add(self, key: str, fields: dict) -> bool:
        if key in self.keys or not KEY_RE.match(key):
            return False
        entry = {"content_key": key}
        entry.update(fields)
        # 标记来源，便于再生成时不覆盖人工策展（curated）条目。
        entry["source"] = "generated"
        self.entries.append(entry)
        self.keys.add(key)
        self.added += 1
        return True

    @property
    def need(self) -> int:
        return max(0, self.target - len(self.entries))

    def full(self) -> bool:
        return len(self.entries) >= self.target

    def finalize(self, dry: bool) -> tuple[int, int]:
        total = save(self.name, self.entries, dry)
        return total, self.added


# ------------------------------------------------------------------ helpers


def expand(names: list[str], bases: list[str]) -> list[tuple[str, str]]:
    """返回 (name, key_slug) 的笛卡尔积组合。"""
    return [(f"{n}{b}", f"{slug(b)}") for n in names for b in bases]


# ------------------------------------------------------------------ builders


def build_jobs(b: Builder) -> None:
    # 行业 -> (行业键, 中文组名, [岗位…])
    industries = {
        "agriculture": ("农业", ["农民", "农机手", "兽医", "农技员", "渔民", "林农", "养殖户", "果园工", "茶农", "畜牧员"]),
        "industry": ("工业", ["普工", "技工", "车工", "焊工", "电工", "质检员", "生产主管", "厂长", "设备工程师", "仓储员"]),
        "construction": ("建筑", ["木工", "瓦工", "钢筋工", "施工员", "监理", "造价师", "设计师", "项目经理", "安全员", "测量员"]),
        "transport": ("交通", ["司机", "公交司机", "网约车司机", "列车员", "飞行员", "空乘", "船长", "船员", "调度员", "票务员"]),
        "it": ("信息技术", ["程序员", "测试工程师", "运维工程师", "产品经理", "架构师", "算法工程师", "数据工程师", "安全工程师", "前端工程师", "项目经理"]),
        "finance": ("金融", ["柜员", "信贷员", "理财顾问", "证券经纪人", "分析师", "基金经理", "投行顾问", "精算师", "风控专员", "审计助理"]),
        "medical": ("医疗", ["护士", "全科医生", "专科医师", "外科医生", "麻醉师", "药剂师", "检验师", "影像师", "心理医生", "公卫医师"]),
        "education": ("教育", ["幼师", "小学教师", "中学教师", "大学讲师", "教授", "研究员", "辅导员", "培训讲师", "教务员", "特教老师"]),
        "legal": ("法律", ["律师", "法官", "检察官", "书记员", "法务", "公证员", "仲裁员", "助理律师", "调解员", "执法员"]),
        "service": ("生活服务", ["服务员", "厨师", "咖啡师", "理发师", "美容师", "按摩师", "导游", "月嫂", "家政员", "保洁员"]),
        "entertain": ("文娱", ["演员", "歌手", "乐手", "舞者", "主播", "电竞选手", "导演", "编剧", "摄影师", "经纪人"]),
        "media": ("媒体", ["记者", "编辑", "主持人", "公关", "广告策划", "文案", "运营", "编导", "校对", "内容审核"]),
        "government": ("政务", ["公务员", "基层干部", "警察", "消防员", "军人", "城管", "社区工作者", "税务员", "海关员", "信访员"]),
        "research": ("科研", ["研究生", "研究员", "工程师", "实验员", "技术员", "学术助理", "博士后", "数据员", "仪器员", "院士助理"]),
        "art": ("艺术", ["画家", "雕塑家", "设计师", "作家", "书法家", "策展人", "插画师", "陶艺师", "非遗传承人", "评论家"]),
        "sports": ("体育", ["运动员", "教练", "裁判", "经纪人", "队医", "体能师", "青训教练", "赛事运营", "体育记者", "康复师"]),
        "catering": ("餐饮", ["厨师长", "面点师", "调酒师", "餐饮经理", "采购员", "调味师", "凉菜师", "烘焙师", "传菜主管", "食品安全员"]),
        "retail": ("零售", ["店员", "店长", "采购", "督导", "区域经理", "理货员", "收银员", "陈列师", "客服主管", "仓管"]),
        "handicraft": ("手工业", ["木匠", "裁缝", "陶艺师", "钟表匠", "珠宝匠", "铁匠", "皮具师", "竹编师", "玉雕师", "漆艺师"]),
        "professional": ("专业服务", ["会计", "审计师", "咨询顾问", "猎头", "市场调研员", "检测员", "验厂员", "估价师", "翻译", "公证助理"]),
        "emerging": ("新兴职业", ["自媒体人", "短视频博主", "网红", "带货主播", "无人机操作员", "机器人运维", "数据分析师", "直播运营", "虚拟形象设计师", "AI训练师"]),
    }
    levels = [1, 2, 3, 4, 5]
    for ikey, (iname, titles) in industries.items():
        for idx, title in enumerate(titles):
            level = levels[idx % len(levels)]
            salary = 400000 + level * 350000 + (idx * 3700)
            key = f"occupation.{ikey}.{slug(title)}_{idx:02d}"
            b.add(key, {"name": title, "industry": ikey, "level": level, "salary_base": salary, "entry": "job"})
            if b.full():
                return


def build_skills(b: Builder) -> None:
    domains = {
        "life": ("生活", ["烹饪", "清洁", "理财", "驾驶", "急救", "育儿", "维修", "收纳", "园艺", "缝纫", "烘焙", "采购", "谈判", "预算", "家居设计", "宠物养护", "养生", "防身", "出行规划", "垃圾分类"]),
        "career": ("职业", ["编程", "设计", "写作", "会计", "销售", "谈判", "管理", "演讲", "项目管理", "数据分析", "客户服务", "供应链", "质量管理", "商务礼仪", "办公软件", "市场调研", "合同审核", "团队协作", "时间管理", "复盘"]),
        "academic": ("学术", ["数学", "物理", "化学", "生物", "历史", "哲学", "外语", "地理", "统计学", "逻辑学", "经济学", "心理学", "社会科学", "考古", "天文学", "医学基础", "法学基础", "工程原理", "文献检索", "实验设计"]),
        "art": ("艺术", ["绘画", "声乐", "乐器", "舞蹈", "表演", "摄影", "书法", "雕塑", "陶艺", "设计构成", "色彩学", "剪辑", "作曲", "戏剧", "插画", "篆刻", "装帧", "策展", "美学鉴赏", "艺术史"]),
        "sports": ("体育", ["跑酷", "游泳", "格斗", "球类", "田径", "瑜伽", "举重", "登山", "骑行", "滑板", "射击", "射箭", "柔道", "体操", "滑雪", "冲浪", "跆拳道", "跳绳", "马拉松", "体能训练"]),
        "social": ("社交", ["社交礼仪", "共情", "说服", "伪装", "领导", "谈判", "调解", "公关", "演讲", "倾听", "幽默", "人脉经营", "危机沟通", "跨文化沟通", "示弱", "赞美", "拒绝", "协作", "影响力", "读心"]),
        "crime": ("犯罪", ["开锁", "扒窃", "诈骗", "黑客", "赌术", "反侦察", "伪证", "洗钱", "跟踪", "易容", "撬锁", "造假", "走私", "恐吓", "销赃", "赌博", "逃税", "反审讯", "盯梢", "团伙协作"]),
    }
    for dkey, (dname, names) in domains.items():
        for idx, nm in enumerate(names):
            key = f"skill.{dkey}.{slug(nm)}_{idx:02d}"
            b.add(key, {"name": nm, "domain": dkey, "max_level": 5 + (idx % 3)})
            if b.full():
                return


def build_items(b: Builder) -> None:
    categories = {
        "food": ["大米", "面粉", "食用油", "猪肉", "鸡蛋", "白菜", "苹果", "牛奶"],
        "daily": ["洗发水", "牙膏", "洗衣液", "抽纸", "锅具", "餐具", "毛巾", "拖鞋"],
        "clothing": ["T恤", "牛仔裤", "外套", "运动鞋", "帽子", "围巾", "手套", "腰带"],
        "electronics": ["手机", "笔记本电脑", "平板", "耳机", "相机", "洗衣机", "冰箱", "空调"],
        "furniture": ["床", "沙发", "餐桌", "椅子", "衣柜", "书桌", "书柜", "床垫"],
        "tools": ["扳手", "螺丝刀", "电钻", "卷尺", "钳子", "锤子", "工具箱", "水平仪"],
        "books": ["教材", "小说", "专业书", "杂志", "词典", "画册", "传记", "工具书"],
        "medicine": ["感冒药", "退烧药", "胃药", "降压药", "维生素", "创可贴", "消炎药", "眼药水"],
        "luxury": ["名表", "名包", "珠宝", "豪车", "香水", "丝巾", "钢笔", "眼镜"],
        "collectibles": ["邮票", "钱币", "字画", "球鞋", "手办", "古董", "纪念币", "唱片"],
        "agriculture": ["种子", "化肥", "农药", "农机", "饲料", "地膜", "水泵", "大棚膜"],
        "industrial": ["钢材", "塑料粒", "电路板", "轴承", "电机", "电缆", "合金", "元器件"],
        "beverage": ["矿泉水", "可乐", "咖啡", "茶叶", "果汁", "啤酒", "白酒", "红酒"],
        "snack": ["薯片", "巧克力", "饼干", "坚果", "糖果", "肉干", "果冻", "爆米花"],
        "sports": ["篮球", "足球", "羽毛球拍", "瑜伽垫", "哑铃", "跳绳", "泳镜", "护膝"],
        "pet": ["猫粮", "狗粮", "猫砂", "宠物窝", "牵引绳", "玩具球", "宠物零食", "驱虫药"],
        "stationery": ["钢笔", "笔记本", "橡皮", "订书机", "便签", "文件夹", "胶带", "尺子"],
        "baby": ["奶粉", "尿不湿", "婴儿车", "奶瓶", "玩具", "湿巾", "安全座椅", "辅食"],
        "garden": ["花盆", "园艺剪", "营养土", "花种", "喷壶", "铲子", "花架", "肥料"],
        "music": ["吉他", "口琴", "电子琴", "小提琴", "笛子", "手鼓", "麦克风", "调音器"],
        "camera": ["三脚架", "镜头", "闪光灯", "滤镜", "存储卡", "摄影包", "云台", "反光板"],
        "kitchen": ["炒锅", "电饭煲", "微波炉", "烤箱", "刀具", "砧板", "料理机", "热水壶"],
        "gaming": ["游戏机", "手柄", "机械键盘", "鼠标", "显示器", "电竞椅", "耳机架", "散热器"],
        "outdoor": ["帐篷", "睡袋", "登山包", "头灯", "水壶", "指南针", "登山杖", "防潮垫"],
        "craft": ["陶土", "颜料", "画笔", "毛线", "针线", "木板", "胶水", "珠子"],
    }
    for ckey, bases in categories.items():
        for vi, q in enumerate(QUALITIES):
            for bi, base in enumerate(bases):
                price = 500 + vi * 12000 + bi * 137
                key = f"item.{ckey}.{slug(base)}_{vi}_{bi}"
                b.add(key, {"name": f"{QCN[vi]}{base}", "category": ckey, "quality": q, "price": price, "weight": round(0.1 + bi * 0.2, 2)})
                if b.full():
                    return


def build_diseases(b: Builder) -> None:
    groups = {
        "常见": ["感冒", "发烧", "胃炎", "高血压", "糖尿病", "心脏病", "哮喘", "关节炎", "偏头痛", "胃肠炎"],
        "传染": ["流感", "肺炎", "肺结核", "肝炎", "麻疹", "霍乱", "猩红热", "水痘", "痢疾", "登革热"],
        "精神": ["抑郁", "焦虑", "双相", "精神分裂", "惊恐障碍", "强迫症", "创伤后应激", "社交恐惧", "进食障碍", "睡眠障碍",
                 "注意缺陷", "自闭谱系", "人格障碍", "成瘾共病", "疑病症", "躯体化障碍", "老年痴呆", "谵妄", "适应障碍", "解离障碍"],
        "成瘾": ["烟瘾", "酒精依赖", "药物依赖", "赌博成瘾", "网络成瘾"],
        "职业环境": ["尘肺", "职业性耳聋", "农药中毒", "重金属中毒", "放射病"],
        "外伤": ["骨折", "烧伤", "创伤", "器官损伤", "脑震荡", "软组织挫伤"],
        "遗传慢性": ["贫血", "过敏", "癫痫", "肾病", "痛风", "甲状腺疾病", "高血脂", "骨质疏松"],
        "其他": ["近视", "白内障", "中耳炎", "皮炎", "湿疹", "痔疮", "牙周炎", "结石", "静脉曲张", "腰椎间盘突出",
                 "肩周炎", "腱鞘炎", "肥胖症", "营养不良", "维生素缺乏", "免疫紊乱", "热射病", "冻伤", "食物中毒", "职业病性肺病"],
    }
    severity = {"常见": 1, "传染": 2, "精神": 2, "成瘾": 3, "职业环境": 3, "外伤": 2, "遗传慢性": 2, "其他": 1}
    for cat, names in groups.items():
        for idx, nm in enumerate(names):
            key = f"disease.{slug(cat)}.{slug(nm)}_{idx:02d}"
            b.add(key, {"name": nm, "category": cat, "severity": severity.get(cat, 1)})
            if b.full():
                return


def build_certificates(b: Builder) -> None:
    items = [
        ("身份证", "公安"), ("户口本", "公安"), ("C1 驾照", "交通"), ("A 类驾照", "交通"), ("B 类驾照", "交通"),
        ("护照", "出入境"), ("签证", "出入境"), ("教师资格证", "教育"), ("会计证", "财政"), ("律师执业证", "司法"),
        ("医师资格证", "卫生"), ("护士证", "卫生"), ("厨师证", "人社"), ("飞行执照", "民航"), ("心理咨询师", "卫生"),
        ("一级建造师", "住建"), ("消防设施操作员", "应急"), ("电工证", "应急"), ("焊工证", "应急"), ("保安证", "公安"),
        ("导游证", "文旅"), ("翻译资格证", "外事"), ("游泳救生员", "体育"), ("健身教练证", "体育"), ("铲车证", "市场监管"),
        ("报关员证", "海关"), ("食品经营许可证", "市场监管"), ("药品经营许可证", "药监"), ("排污许可证", "生态环境"), ("特种设备作业证", "市场监管"),
    ]
    for idx, (nm, issuer) in enumerate(items):
        b.add(f"cert.{slug(nm)}_{idx:02d}", {"name": nm, "issuer": issuer})
        if b.full():
            return


def build_entertainment(b: Builder) -> None:
    groups = {
        "居家": ["电子游戏", "追剧", "烹饪", "园艺", "手工", "读书", "拼图", "烘焙", "卡拉OK", "桌游", "听音乐", "养花", "下厨", "看直播", "泡茶", "养宠物", "写字", "冥想", "涂色", "做手工皂", "织毛衣", "做手账"],
        "户外": ["徒步", "露营", "钓鱼", "骑行", "滑雪", "攀岩", "冲浪", "野餐", "骑行长途", "观鸟", "越野跑", "漂流", "滑翔", "洞穴探险", "登山", "划船", "采蘑菇", "放风筝", "踏青", "划桨板", "钓鱼比赛", "越野露营"],
        "文化": ["看展览", "看演出", "听音乐会", "逛博物馆", "听讲座", "看话剧", "参观美术馆", "逛书店", "看非遗", "参加读书会", "看戏曲", "逛庙会", "看摄影展", "听相声", "参观科技馆", "看烟花", "看纪录片", "看舞剧", "听评书", "参观故居", "看民间艺术", "听脱口秀"],
        "竞技": ["踢足球", "打篮球", "打羽毛球", "打乒乓", "打电竞", "下棋", "打台球", "打网球", "打排球", "玩保龄球", "打高尔夫", "练拳击", "射箭", "飞盘", "打门球", "玩飞镖", "划龙舟", "打棒球", "练跆拳道", "打桌球", "玩滑板", "打沙包"],
        "夜生活": ["泡酒吧", "唱 KTV", "蹦夜店", "吃宵夜", "逛夜市", "看球赛直播", "玩剧本杀", "玩密室逃脱", "听现场音乐", "打深夜麻将", "泡深夜 spa", "夜市小吃巡礼", "露天电影", "深夜观影", "夜跑", "看夜景", "逛深夜书吧"],
        "收藏": ["集邮", "收手办", "收球鞋", "淘古玩", "收钱币", "收字画", "收唱片", "收模型", "收卡牌", "收茶具", "收名表", "收相机", "收老物件", "收漫画", "收邮票册", "收纪念章", "收古书"],
    }
    for gkey, names in groups.items():
        for idx, nm in enumerate(names):
            key = f"ent.{slug(gkey)}.{slug(nm)}_{idx:02d}"
            b.add(key, {"name": nm, "category": gkey, "fee": 0 + idx * 50, "minutes": 30 + idx * 10})
            if b.full():
                return


def build_events(b: Builder) -> None:
    groups = {
        "机遇": ["中奖", "升职机会", "捡漏", "贵人相助", "桃花运", "意外之财", "中签", "旧友重逢", "被人赏识", "投资获利"],
        "意外": ["交通事故", "失窃", "突发疾病", "车祸", "被骗", "家中漏水", "丢钱包", "摔伤", "停电", "突发加班"],
        "社会": ["政策变动", "物价上涨", "邻里纠纷", "舆论风波", "法律纠纷", "社区选举", "公益募捐", "志愿活动", "拆迁公告", "限购新政"],
        "环境": ["地震", "洪水", "台风", "干旱", "野火", "泥石流", "暴雪", "冰雹", "疫情", "沙尘暴"],
        "剧情": ["家庭矛盾", "热恋", "分手", "友情考验", "事业转折", "生育", "亲人离世", "旧识来访", "秘密暴露", "命运抉择"],
        "隐藏": ["遇见异常", "拾得古籍", "梦境预警", "神秘来信", "时空异动", "灵异目击", "符箓显灵", "气运逆转", "得到法器", "窥见天机"],
    }
    contexts = ["", "在清晨", "在雨夜", "在街头", "在职场", "在旅途", "在深夜", "在故乡", "在异乡", "在人群中"]
    for gkey, stems in groups.items():
        for si, stem in enumerate(stems):
            for ci, ctx in enumerate(contexts):
                name = f"{ctx}{stem}" if ctx else stem
                key = f"event.{slug(gkey)}.{slug(stem)}_{si:02d}_{ci:02d}"
                b.add(key, {"name": name, "type": gkey, "weight": 5 + si % 5, "priority": si % 3 + 1})
                if b.full():
                    return


def build_achievements(b: Builder) -> None:
    categories = {
        "career": ("职业", ["首次入职", "升职", "成为主管", "成为高管", "创办公司", "行业获奖"]),
        "wealth": ("财富", ["第一个百万", "第一个千万", "资产过亿", "投资翻倍", "还清债务", "实现财务自由"]),
        "family": ("家庭", ["结婚", "生子", "四世同堂", "金婚", "家庭和睦", "传承三代"]),
        "social": ("社交", ["结交好友", "人脉过百", "成为意见领袖", "调解纠纷", "收获挚友", "广结善缘"]),
        "travel": ("旅行", ["初出远门", "游遍全省", "走遍全国", "踏足邻国", "环游世界", "抵达极地"]),
        "collect": ("收藏", ["首个藏品", "集齐一套", "收藏过百", "稀世珍品", "藏品估值百万", "私人博物馆"]),
        "crime": ("犯罪", ["初次得手", "全身而退", "金盆洗手", "被捕入狱", "越狱", "改邪归正"]),
        "honor": ("荣誉", ["获得表彰", "荣获大奖", "入选名人堂", "当选院士", "获得国家级荣誉", "载入史册"]),
        "anomaly": ("异常", ["初次遭遇", "收容实体", "觉醒能力", "掌握术法", "进出异常", "窥破真相"]),
        "health": ("健康", ["坚持锻炼", "老年康健", "战胜重病", "百岁高寿", "身体机能巅峰", "医者仁心"]),
        "academic": ("学术", ["读完本科", "获得硕士", "获得博士", "发表论文", "出版专著", "获得科研突破"]),
        "art": ("艺术", ["首次登台", "举办个展", "作品获奖", "成为名家", "作品传世", "开宗立派"]),
    }
    tiers = [1, 3, 10, 30, 100]
    for ckey, (cname, metrics) in categories.items():
        for mi, metric in enumerate(metrics):
            for ti, tier in enumerate(tiers):
                key = f"ach.{ckey}.{mi:02d}_{ti}"
                b.add(key, {"name": f"{metric}·{tier}级", "category": ckey, "metric": f"{ckey}_{mi}", "threshold": float(tier)})
                if b.full():
                    return


def build_codex(b: Builder) -> None:
    categories = {
        "location": ("地点", ["街巷", "公园", "地标", "车站", "商圈", "古迹", "河畔", "山丘", "港口", "广场"]),
        "item": ("物品", ["器物", "工具", "服饰", "食药品", "电子品", "书籍", "收藏品", "机械", "材料", "杂物"]),
        "creature": ("生物", ["飞禽", "走兽", "水族", "昆虫", "菌类", "草木", "花木", "猛兽", "灵物", "异种"]),
        "disease": ("疾病", ["常见病", "传染病", "精神类", "外伤", "慢性病", "职业病", "遗传病", "中毒", "成瘾", "杂症"]),
        "anomaly": ("异常实体", ["物品型", "生物型", "地点型", "现象型", "信息型", "人形", "模因", "时空型", "认知危害", "现实扭曲"]),
        "lore": ("见闻", ["传说", "轶事", "掌故", "秘辛", "谚语", "古籍", "碑文", "野史", "民谣", "手记"]),
        "event": ("事件", ["天灾", "人祸", "命案", "事故", "集会", "庆典", "灾难", "争端", "变迁", "奇闻"]),
        "person": ("人物", ["工匠", "商贾", "游侠", "隐士", "官员", "艺者", "学者", "医者", "僧道", "异人"]),
        "organization": ("组织", ["行会", "商帮", "门派", "会社", "军团", "教团", "联盟", "世家", "帮派", "机构"]),
        "custom": ("民俗", ["节令", "婚俗", "丧仪", "祭礼", "食俗", "衣俗", "游艺", "禁忌", "卜筮", "庙会"]),
    }
    idx_global = 0
    for ckey, (cname, topics) in categories.items():
        for ti, topic in enumerate(topics):
            for n in range(5):
                idx_global += 1
                key = f"codex.{ckey}.{slug(topic)}_{ti:02d}_{n}"
                b.add(key, {"name": f"{topic}·卷{n + 1}", "category": ckey, "description": f"{cname}类目下的{topic}条目之{n + 1}。"})
                if b.full():
                    return


def build_transport(b: Builder) -> None:
    items = [("步行", "walk", 5.0), ("自行车", "bike", 15.0), ("公交", "bus", 25.0), ("地铁", "metro", 40.0),
             ("出租", "taxi", 45.0), ("网约车", "ride_hailing", 45.0), ("自驾", "car", 60.0), ("火车", "train", 90.0),
             ("高铁", "high_speed_rail", 300.0), ("长途汽车", "coach", 70.0), ("飞机", "plane", 800.0), ("轮船", "ship", 35.0)]
    for nm, kind, spd in items:
        b.add(f"transport.{kind}", {"name": nm, "kind": kind, "speed": spd})


def build_finance(b: Builder) -> None:
    items = [
        ("消费龙头股", "stock", 0.18), ("科技成长股", "stock", 0.28), ("金融蓝筹股", "stock", 0.14), ("能源周期股", "stock", 0.24),
        ("医药白马股", "stock", 0.20), ("地产板块股", "stock", 0.26), ("制造业指数基金", "fund", 0.12), ("宽基指数基金", "fund", 0.10),
        ("行业主题基金", "fund", 0.22), ("债券型基金", "fund", 0.05), ("货币基金", "fund", 0.02), ("对冲基金份额", "fund", 0.30),
        ("国债", "bond", 0.03), ("地方债", "bond", 0.045), ("企业债", "bond", 0.07), ("可转债", "bond", 0.12),
        ("高收益债", "bond", 0.20), ("股指期货", "derivative", 0.45), ("商品期货", "derivative", 0.40), ("期权合约", "derivative", 0.55),
        ("外汇合约", "derivative", 0.35), ("利率互换", "derivative", 0.15), ("黄金", "commodity", 0.16), ("原油", "commodity", 0.42),
        ("铜", "commodity", 0.30), ("大豆", "commodity", 0.25), ("比特币", "crypto", 0.85), ("以太坊", "crypto", 0.90),
        ("稳定币", "crypto", 0.10), ("NFT 资产", "crypto", 0.95), ("银行理财", "wealth", 0.06), ("信托产品", "wealth", 0.12),
        ("私募股权", "wealth", 0.40), ("REITs", "wealth", 0.18), ("年金保险", "insurance", 0.08), ("分红险", "insurance", 0.09),
        ("万能险", "insurance", 0.07), ("商品 ETF", "fund", 0.15), ("黄金 ETF", "fund", 0.16), ("行业债券组合", "bond", 0.08),
    ]
    for idx, (nm, kind, risk) in enumerate(items):
        b.add(f"fin.{slug(nm)}_{idx:02d}", {"name": nm, "kind": kind, "risk": risk})


def build_manufacturing(b: Builder) -> None:
    items = [
        ("食品加工", 1), ("纺织服装", 2), ("家具制造", 2), ("造纸印刷", 2), ("化工原料", 3), ("医药制造", 4),
        ("金属冶炼", 3), ("机械装备", 3), ("电子元件", 4), ("汽车零部件", 4), ("建材生产", 2), ("日化用品", 3),
        ("半导体制造", 5), ("精密仪器", 5), ("航空航天部件", 6), ("新能源电池", 5), ("钢材轧制", 3), ("水泥熟料", 2),
        ("玻璃制造", 3), ("陶瓷制品", 2), ("橡胶制品", 3), ("塑料制品", 3), ("涂料油墨", 3), ("化肥农药", 3),
        ("饲料加工", 2), ("酿酒制糖", 2), ("烟草加工", 3), ("皮革制品", 2), ("家电组装", 4), ("通信设备", 5),
        ("光伏组件", 5), ("风电设备", 5), ("机器人本体", 6), ("数控机床", 5), ("工程机械", 4), ("船舶制造", 5),
        ("轨道交通装备", 6), ("医疗器械", 5), ("玩具制造", 3), ("文体用品", 3), ("包装材料", 2), ("再生资源回收", 3),
        ("大宗批发", 3), ("跨境电商", 5), ("供应链服务", 4), ("仓储物流", 3), ("冷链运输", 4), ("成品零售", 3),
        ("原材料贸易", 3), ("元器件分销", 5),
    ]
    for idx, (nm, era) in enumerate(items):
        b.add(f"mfg.{slug(nm)}_{idx:02d}", {"name": nm, "era": era})


def build_awards(b: Builder) -> None:
    items = [
        ("自然科学奖", "学术"), ("技术发明奖", "学术"), ("科技进步奖", "学术"), ("青年科学奖", "学术"), ("院士称号", "学术"),
        ("文学奖", "文学"), ("诗歌奖", "文学"), ("小说奖", "文学"), ("散文奖", "文学"), ("儿童文学奖", "文学"),
        ("最佳影片奖", "影视"), ("最佳导演奖", "影视"), ("最佳男演员", "影视"), ("最佳女演员", "影视"), ("最佳编剧奖", "影视"),
        ("年度专辑奖", "音乐"), ("最佳歌手", "音乐"), ("最佳作曲", "音乐"), ("最佳乐队", "音乐"), ("金曲奖", "音乐"),
        ("赛季 MVP", "体育"), ("最佳射手", "体育"), ("最佳教练", "体育"), ("最佳新人", "体育"), ("终身成就奖", "体育"),
        ("工艺美术大师", "艺术"), ("美术金像奖", "艺术"), ("摄影金像奖", "艺术"), ("设计红星奖", "艺术"), ("非遗传承人", "艺术"),
        ("年度企业家", "商业"), ("创新企业奖", "商业"), ("社会责任奖", "商业"), ("行业领军奖", "商业"), ("青年创业奖", "商业"),
        ("名医荣誉", "医疗"), ("杰出教师", "教育"), ("杰出律师", "法律"), ("杰出工程师", "工程"), ("杰出志愿者", "公益"),
    ]
    for idx, (nm, field) in enumerate(items):
        b.add(f"award.{slug(nm)}_{idx:02d}", {"name": nm, "field": field})


def build_organizations(b: Builder) -> None:
    items = [
        ("总工会", "工会"), ("行业联合会", "协会"), ("企业家俱乐部", "俱乐部"), ("环保 NGO", "NGO"), ("动物保护协会", "NGO"),
        ("志愿者服务团", "志愿"), ("校友会", "社团"), ("读书会", "社团"), ("登山协会", "俱乐部"), ("摄影协会", "俱乐部"),
        ("青年商会", "协会"), ("妇女联合会", "协会"), ("消费者协会", "协会"), ("残疾人联合会", "协会"), ("红十字会", "公益"),
        ("慈善基金会", "公益"), ("社区互助会", "社团"), ("钓友会", "俱乐部"), ("棋友会", "俱乐部"), ("戏曲票友会", "社团"),
        ("科研学会", "协会"), ("医师协会", "协会"), ("律师协会", "协会"), ("教师工会", "工会"), ("记者协会", "协会"),
        ("秘密读书会", "结社"), ("异常研究会", "结社"), ("夜行社", "结社"), ("同乡会", "社团"), ("宗亲会", "社团"),
    ]
    for idx, (nm, kind) in enumerate(items):
        b.add(f"org.{slug(nm)}_{idx:02d}", {"name": nm, "kind": kind})


def build_anomalies(b: Builder) -> None:
    prefixes = ["静默", "逆流", "蚀刻", "低语", "苍白", "琥珀", "锈蚀", "虚空", "镜像", "黄昏",
                "蠕行", "回响", "浮游", "灰烬", "暗涌", "漩涡", "缄默", "幽蓝", "龟裂", "沧桑"]
    nouns = ["之匣", "之钟", "之人", "之镜", "之书", "之塔", "之门", "之影", "之种", "之歌"]
    containments = ["Safe", "Euclid", "Keter", "Thaumiel", "Apollyon", "Explained", "Neutralized", "Pending"]
    threats = ["白", "绿", "黄", "红", "黑"]
    classes = ["模因", "认知危害", "信息危害", "现实扭曲", "时空", "生物", "物品", "超自然"]
    forms = ["物品", "生物", "地点", "现象", "信息", "人形"]
    serials = ["", "·甲", "·乙", "·丙", "·丁", "·戊", "·己", "·庚", "·辛", "·壬"]
    i = 0
    for serial in serials:
        for pi, pre in enumerate(prefixes):
            for ni, noun in enumerate(nouns):
                i += 1
                name = f"{pre}{noun}{serial}"
                key = f"anomaly.lt_{i:04d}"
                b.add(key, {
                    "name": name,
                    "containment": containments[i % len(containments)],
                    "threat": threats[i % len(threats)],
                    "class": classes[i % len(classes)],
                })
                if b.full():
                    return


def build_activities(b: Builder) -> None:
    items = [
        ("行业博览会", "会展"), ("科技发布会", "会展"), ("春季订货会", "会展"), ("招聘会", "会展"), ("房车展", "会展"),
        ("演唱会", "演出"), ("露天音乐节", "演出"), ("话剧巡演", "演出"), ("舞蹈专场", "演出"), ("戏曲汇演", "演出"),
        ("体育联赛", "赛事"), ("锦标赛", "赛事"), ("电竞总决赛", "赛事"), ("城市马拉松", "赛事"), ("田径运动会", "赛事"),
        ("元宵灯会", "节庆"), ("新春庙会", "节庆"), ("嘉年华", "节庆"), ("烟花大会", "节庆"), ("花车巡游", "节庆"),
    ]
    for idx, (nm, kind) in enumerate(items):
        b.add(f"activity.{slug(nm)}_{idx:02d}", {"name": nm, "kind": kind})


def build_languages(b: Builder) -> None:
    items = [("汉语普通话", "中国"), ("英语", "国际"), ("粤语", "华南"), ("吴语", "江南"), ("闽南语", "闽台"),
             ("日语", "东亚"), ("韩语", "东亚"), ("法语", "欧洲"), ("西班牙语", "欧美"), ("阿拉伯语", "中东")]
    for idx, (nm, region) in enumerate(items):
        b.add(f"lang.{slug(nm)}_{idx:02d}", {"name": nm, "region": region})


def build_festivals(b: Builder) -> None:
    items = [("元旦", 1, 1), ("春节", 1, 22), ("元宵节", 2, 5), ("清明节", 4, 4), ("端午节", 6, 10),
             ("中秋节", 9, 15), ("国庆节", 10, 1), ("七夕", 8, 14), ("重阳节", 10, 4), ("除夕", 1, 21)]
    for idx, (nm, month, day) in enumerate(items):
        b.add(f"festival.{slug(nm)}_{idx:02d}", {"name": nm, "month": month, "day": day})


PLACE_TYPE_GROUPS = {
    "居住": ["公寓", "小区", "别墅", "宿舍", "养老院", "救助站", "廉租房", "民宿"],
    "餐饮": ["中餐厅", "快餐店", "火锅店", "咖啡厅", "酒吧", "夜市", "食堂", "茶楼", "面包房", "小吃街"],
    "零售": ["超市", "便利店", "商场", "书店", "药店", "花店", "烟酒店", "五金店", "母婴店", "宠物店", "菜市场", "批发市场"],
    "医疗": ["综合医院", "专科医院", "诊所", "牙科", "心理诊所", "急救中心", "药房", "体检中心", "康复中心", "疾控中心"],
    "教育": ["幼儿园", "小学", "中学", "大学", "职校", "培训机构", "图书馆", "实验室", "体育馆", "自习室"],
    "政务": ["派出所", "法院", "检察院", "政府机关", "民政局", "税务局", "车管所", "出入境", "社保中心", "政务大厅"],
    "交通": ["地铁站", "公交站", "火车站", "高铁站", "机场", "港口", "加油站", "停车场", "客运站", "收费站"],
    "文娱": ["影院", "KTV", "健身房", "网吧", "游乐场", "博物馆", "美术馆", "剧院", "体育场", "电竞馆", "桌游吧", "台球厅"],
    "宗教": ["寺庙", "教堂", "清真寺", "道观", "祠堂", "佛堂"],
    "产业": ["工厂", "矿区", "农场", "渔港", "仓库", "发电站", "工地", "养殖场", "产业园", "物流园"],
    "金融": ["银行", "证券营业部", "保险公司", "当铺", "小贷公司", "交易所", "ATM 网点", "理财网点"],
    "自然": ["公园", "山", "湖", "海滩", "森林", "沙漠", "湿地", "峡谷", "草原", "溶洞"],
    "特殊": ["黑市", "赌场", "夜店", "收容站", "异常收容点", "地下拳场", "走私码头", "义庄"],
}


def place_type_list() -> list[tuple[str, str]]:
    """返回所有场所类型的 (key_suffix, name)。key 为 place.<slug>_<idx>。"""
    out: list[tuple[str, str]] = []
    for gkey, names in PLACE_TYPE_GROUPS.items():
        for idx, nm in enumerate(names):
            out.append((f"{slug(nm)}_{idx:02d}", nm))
    return out


def build_place_types(b: Builder) -> None:
    for gkey, names in PLACE_TYPE_GROUPS.items():
        for idx, nm in enumerate(names):
            b.add(f"place.{slug(nm)}_{idx:02d}", {"name": nm, "group": gkey})
    return


def build_sites(b: Builder) -> None:
    regions = {
        "east": "城东", "west": "城西", "south": "城南", "north": "城北", "central": "城中",
        "hitech": "高新区", "oldtown": "老城", "riverside": "滨江", "univ": "大学城", "industrial": "工业园",
    }
    for rkey, rname in regions.items():
        for pslug, pname in place_type_list():
            b.add(f"site.{rkey}_{pslug}", {
                "name": f"{rname}{pname}",
                "scene": f"res://scenes/sites/{rkey}_{pslug}.tscn",
                "category": pslug,
                "radius": 30.0,
            })
            if b.full():
                return


def build_primary_industry(b: Builder) -> None:
    groups = {
        "crop": ["水稻", "小麦", "玉米", "大豆", "蔬菜", "水果", "棉花", "茶叶", "油料", "薯类", "糖料", "烟草"],
        "livestock": ["猪", "牛", "羊", "鸡", "鸭", "鹅", "兔", "马"],
        "aquatic": ["鱼", "虾", "蟹", "贝", "藻类"],
        "forestry": ["橡胶", "药材", "木材", "竹材"],
        "process": ["饲料加工", "粮食烘干", "果蔬保鲜", "水产加工", "乳制品原料", "肉制品原料"],
    }
    for gkey, names in groups.items():
        for idx, nm in enumerate(names):
            b.add(f"primary.{slug(nm)}_{idx:02d}", {"name": nm, "sector": gkey})
    return


BUILDERS = [
    build_jobs, build_skills, build_items, build_diseases, build_certificates,
    build_entertainment, build_events, build_achievements, build_codex,
    build_transport, build_finance, build_manufacturing, build_awards,
    build_organizations, build_anomalies, build_activities, build_languages,
    build_festivals, build_place_types, build_sites, build_primary_industry,
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # 类别名到 Builder 的映射由各 build 函数内部决定，这里按 TARGETS 收集。
    order = list(TARGETS.keys())
    results = []
    for name in order:
        b = Builder(name)
        fn = globals().get(f"build_{name}")
        if fn is None:
            results.append((name, len(b.entries), 0, b.target))
            continue
        fn(b)
        total, added = b.finalize(args.dry_run)
        results.append((name, total, added, b.target))

    print(f"{'类别':<18}{'现有':>6}{'新增':>6}{'目标':>6}  状态")
    ok = True
    for name, total, added, target in results:
        status = "达标" if total >= target else "不足"
        if total < target:
            ok = False
        print(f"{name:<18}{total:>6}{added:>6}{target:>6}  {status}")
    print("（dry-run，未写文件）" if args.dry_run else "已写入 content/catalog")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
