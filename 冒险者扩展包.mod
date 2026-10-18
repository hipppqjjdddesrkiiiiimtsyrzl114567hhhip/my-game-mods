# -*- coding: utf-8 -*-
"""
冒险者扩展包 Adventurer's Expansion
文字 RPG 引擎 mod  v1.0.0

新增内容：
  · 新地图：雪山、雪山顶
  · 新装备：龙鳞剑、秘银甲、智慧戒指
  · 新物品：高级药水、复活羽毛
  · 新战斗：雪怪、雪王
  · 新任务：征服雪王
  · 每日祝福系统（每天第一次进入游戏随机获得 buff）
"""

MOD_INFO = {
    "name": "冒险者扩展包",
    "version": "1.0.0",
    "game_version": ">=2.0.0",
    "description": "添加雪山区域、新装备、新物品、新任务和每日祝福系统。",
}


# ==================================================================
#                      引擎级补丁（启动时应用一次）
# ==================================================================
def on_engine_load(engine_cls, ctx):
    """给 RPGEngine 添加"首次进入游戏"提示钩子。"""
    em = ctx["engine_module"]

    def _init_hook(self, *args, **kwargs):
        # 原始 __init__ 已被调用，这里只做额外初始化
        print("\n  ★ [冒险者扩展包] 已加载 v1.0.0")
        print("    新内容：雪山 / 龙鳞剑 / 秘银甲 / 智慧戒指 / 雪王任务 / 每日祝福")
        return None  # 不覆盖原返回值

    em._chain_patch(engine_cls, "__init__", _init_hook)
    print("* [扩展包] 引擎级补丁已应用")


# ==================================================================
#                      冒险数据补丁（每次开始游戏前）
# ==================================================================
def on_rpg_load(data, ctx):
    _add_equipment(data)
    _add_items(data)
    _add_quests(data)
    _add_battles(data)
    _add_maps(data)


# ==================================================================
#                      冒险启动钩子（每日祝福）
# ==================================================================
def on_rpg_start(engine, ctx):
    _daily_bless(engine, ctx)


# ==================================================================
#                      具体实现
# ==================================================================
def _add_equipment(data):
    """把新装备塞进 equipment 数据库（已存在则跳过）。"""
    eq_db = data.setdefault("equipment", {})

    if "龙鳞剑" not in eq_db:
        eq_db["龙鳞剑"] = {
            "slot": "weapon", "atk": 18, "def": 3, "maxhp": 0,
            "desc": "用古老巨龙的鳞片打造的锋利长剑",
        }
    if "秘银甲" not in eq_db:
        eq_db["秘银甲"] = {
            "slot": "armor", "atk": 0, "def": 12, "maxhp": 30,
            "desc": "轻盈却坚固的秘银护甲",
        }
    if "智慧戒指" not in eq_db:
        eq_db["智慧戒指"] = {
            "slot": "accessory", "atk": 3, "def": 2, "maxhp": 15,
            "desc": "蕴含古老智慧的戒指",
        }


def _add_items(data):
    """加入新物品（按名字去重，避免存档反复叠加）。"""
    items = data.setdefault("items", [])
    existing = {it.get("name") for it in items if isinstance(it, dict)}

    if "高级药水" not in existing:
        items.append({
            "name": "高级药水", "count": 2, "target": "one",
            "effects": [{"type": "hp", "amount": 80}],
        })
    if "复活羽毛" not in existing:
        items.append({
            "name": "复活羽毛", "count": 1, "target": "one",
            "effects": [{"type": "hp", "amount": "full"}],
        })


def _add_quests(data):
    quests = data.setdefault("quests", {})

    if "征服雪王" not in quests:
        quests["征服雪王"] = {
            "title": "征服雪王",
            "desc": "传说雪山顶端盘踞着一位雪王，雪山向导请求你击败他。",
            "stages": [
                {"desc": "击败雪王", "flag": "雪王击败", "op": "==", "value": True},
                {"desc": "返回向导处报告", "flag": "雪王报告", "op": "==", "value": True},
            ],
            "on_start": [
                {"type": "text", "text": "雪山向导：愿雪山之灵指引你。"},
            ],
            "on_complete": [
                {"type": "gold", "amount": 200},
                {"type": "exp", "target": "all", "amount": 100},
                {"type": "text", "text": "雪山向导向你鞠躬，并赠予你丰厚的报酬。"},
            ],
        }


def _add_battles(data):
    battles = data.setdefault("battles", {})

    if "雪怪" not in battles:
        battles["雪怪"] = {
            "quit_behavior": "reload",
            "battle_file": "",
            "win_reward": {"exp": 35, "gold": 20, "drops": [
                {"name": "高级药水", "count": 1, "chance": 0.5},
            ]},
            "lose_reward": {"exp": 0, "gold": 0, "drops": []},
            "spare_reward": {"exp": 20, "gold": 10, "drops": []},
            "quit_reward": {"exp": 0, "gold": 0, "drops": []},
            "enemy": [{
                "name": "雪怪", "hp": 180, "maxhp": 180, "atk": 18, "def": 3,
                "mercy": 0, "tp": 0, "pattern": "rain",
                "acts": [{
                    "type": "attack", "label": "冰霜爪击", "cost": 0,
                    "weight": 1, "pattern": "rain",
                    "view_text": "准备冰霜爪击", "result_text": "",
                    "mechanic": "",
                }],
                "view": {}, "check_text": "一只浑身覆雪的凶兽",
            }],
            "flavors": ["雪怪咆哮着冲了过来！"],
            "state_display": {}, "mechanics": {},
            "stg": {
                "enabled": True,
                "dodge": {"width": 40, "height": 14, "fps": 20,
                          "duration": 6.0, "player_speed": 1},
                "patterns": {
                    "rain": {"type": "rain", "interval": 6,
                             "speed": 0.6, "char": "*"},
                },
            },
            "script": "",
        }

    if "雪王" not in battles:
        battles["雪王"] = {
            "quit_behavior": "reload",
            "battle_file": "",
            "win_reward": {"exp": 120, "gold": 100, "drops": [
                {"name": "龙鳞剑",   "count": 1, "chance": 1.0},
                {"name": "秘银甲",   "count": 1, "chance": 1.0},
                {"name": "智慧戒指", "count": 1, "chance": 0.7},
            ]},
            "lose_reward": {"exp": 0, "gold": 0, "drops": []},
            "spare_reward": {"exp": 60, "gold": 50, "drops": []},
            "quit_reward": {"exp": 0, "gold": 0, "drops": []},
            "enemy": [{
                "name": "雪王", "hp": 600, "maxhp": 600, "atk": 25, "def": 8,
                "mercy": 0, "tp": 0, "pattern": "fan",
                "acts": [
                    {"type": "attack", "label": "暴风雪", "cost": 0,
                     "weight": 2, "pattern": "fan",
                     "view_text": "准备暴风雪", "result_text": "",
                     "mechanic": ""},
                    {"type": "attack", "label": "寒冰吐息", "cost": 10,
                     "weight": 1, "pattern": "spiral",
                     "view_text": "准备寒冰吐息", "result_text": "",
                     "mechanic": ""},
                ],
                "view": {}, "check_text": "雪山顶端的王者，威严而冰冷",
            }],
            "flavors": ["雪王缓缓起身，狂风呼啸而来……"],
            "state_display": {}, "mechanics": {},
            "stg": {
                "enabled": True,
                "dodge": {"width": 40, "height": 14, "fps": 20,
                          "duration": 8.0, "player_speed": 1},
                "patterns": {
                    "fan":    {"type": "fan", "interval": 20, "count": 7,
                               "spread": 0.25, "speed": 0.6, "char": "*"},
                    "spiral": {"type": "spiral", "interval": 4,
                               "speed": 0.6, "char": "o"},
                },
            },
            "script": "",
        }


def _add_maps(data):
    maps = data.setdefault("maps", {})
    start_map = data.get("start_map", "")

    # 找一个接入点：优先"村庄"，其次开始地图，再次任意地图
    entry = None
    if "村庄" in maps:
        entry = "村庄"
    elif start_map and start_map in maps:
        entry = start_map
    elif maps:
        entry = next(iter(maps.keys()))

    # —— 雪山 ——
    if "雪山" not in maps:
        maps["雪山"] = {
            "desc": "被终年积雪覆盖的山脚下，寒气逼人。",
            "exits": {"北": "雪山顶"},
            "save_point": True,
            "npcs": [{
                "name": "雪山向导",
                "desc": "一位裹着厚厚毛皮的老者。",
                "dialogue": [
                    "山顶的雪王已经困扰我们很久了……",
                    "如果你能击败他，我会给你丰厚的报酬。",
                ],
                "events": [
                    {"type": "quest", "action": "start", "name": "征服雪王"},
                ],
            }],
            "encounters": ["雪怪"],
        }
        if entry:
            maps["雪山"]["exits"]["南"] = entry

    # —— 雪山顶 ——
    if "雪山顶" not in maps:
        maps["雪山顶"] = {
            "desc": "刺骨的寒风呼啸而过，雪王的宫殿就在眼前。",
            "exits": {"南": "雪山"},
            "save_point": False,
            "npcs": [],
            "encounters": [],
            "on_enter": [
                {"type": "text", "text": "狂风呼啸，雪王威严地站了起来……"},
                {"type": "battle", "preset": "雪王",
                 "on_win": [
                     {"type": "set", "flag": "雪王击败", "value": True},
                 ]},
            ],
        }

    # —— 在接入点开一个"西北"出口通向雪山 ——
    if entry and entry in maps:
        ex = maps[entry].setdefault("exits", {})
        if "西北" not in ex:
            ex["西北"] = "雪山"


def _daily_bless(engine, ctx):
    """每日祝福：每天第一次进入游戏时随机获得 buff。"""
    import datetime
    import random

    em = ctx.get("engine_module")
    today = datetime.date.today().isoformat()

    # flags 属于动态数据，会随存档恢复，因此可作跨日判定
    if engine.flags.get("_adv_bless_day") == today:
        return

    engine.flags["_adv_bless_day"] = today

    party = engine.data.get("party", [])
    choice = random.choice(["gold", "heal", "exp", "atk", "maxhp"])

    print()
    print("=" * 52)
    print("  ★ 冒险者扩展包：今日祝福 ★")
    print("=" * 52)

    if choice == "gold":
        engine.gold += 80
        print("  你的钱包变重了…… 金币 +80")
    elif choice == "heal":
        eq_db = engine.data.get("equipment", {})
        for m in party:
            try:
                eff_max = em._effective_stats(m, eq_db)[0] if em else m.get("maxhp", 100)
            except Exception:
                eff_max = int(m.get("maxhp", 100))
            m["hp"] = eff_max
        print("  温暖的光芒笼罩队伍…… 全员 HP 回满")
    elif choice == "exp":
        if party:
            engine.grant_exp(party, 30)
            print("  你感到更加熟练了…… 全队经验 +30")
    elif choice == "atk":
        if party:
            m = random.choice(party)
            m["atk"] = int(m.get("atk", 0)) + 3
            print(f"  力量涌入 {m.get('name','?')} 的身体…… 攻击 +3")
    elif choice == "maxhp":
        if party:
            m = random.choice(party)
            m["maxhp"] = int(m.get("maxhp", 100)) + 20
            m["hp"] = int(m.get("hp", 0)) + 20
            print(f"  生命之力注入 {m.get('name','?')}…… 最大HP +20")

    print("=" * 52)