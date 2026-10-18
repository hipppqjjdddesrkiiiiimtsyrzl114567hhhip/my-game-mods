# -*- coding: utf-8 -*-
"""
Mod: 战斗自动获胜

所有战斗一进入就判定胜利，按正常流程发放经验、金币和掉落。
"""

MOD_INFO = {
    "name": "战斗自动获胜",
    "version": "1.0.0",
    "game_version": ">=2.0.0",
    "description": "所有战斗立即判定为胜利，正常发放经验、金币和掉落。",
}


def on_engine_load(engine_cls, ctx):
    # 拿到回合战斗模块的引用
    battle_module = ctx.get("battle_module")
    if battle_module is None:
        print("* 警告：[战斗自动获胜] 未找到回合战斗引擎，Mod 未生效。")
        return
    if not hasattr(battle_module, "battle"):
        print("* 警告：[战斗自动获胜] 战斗引擎缺少 battle()，Mod 未生效。")
        return

    def battle_auto_win(bd, mechs, pats, interactive=True, editor_mode=False):
        """替换 BATTLE.battle：直接返回 'win'。"""
        enemies = bd.get("enemy", []) or []
        names = "、".join(str(e.get("name", "?")) for e in enemies) or "敌人"
        flavors = bd.get("flavors") or []
        if flavors:
            print(f"\n{flavors[0]}")
        print(f"*[自动获胜] 你击败了 {names}！")
        return "win"

    def get_last_battle_summary():
        """让引擎按满 TP 结算金币（tp=100 时金币 = 基础值）。"""
        return {"tp": 100}

    # 注入到战斗模块
    battle_module.battle = battle_auto_win
    battle_module.get_last_battle_summary = get_last_battle_summary

    print("* Mod [战斗自动获胜] 已注入战斗引擎。")