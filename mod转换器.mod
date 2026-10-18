# -*- coding: utf-8 -*-
"""
mod_to_json.mod —— mod → JSON 转换器（v1.0）

功能：
  扫描游戏目录下所有 .mod 文件，把标记了 MOD_INFO["export"] 的
  mod 转换成对应的 RPG 冒险 JSON 或战斗 JSON，保存到游戏目录。

转换源 mod 示例（RPG）：
    # ---------- my_adventure.mod ----------
    MOD_INFO = {
        "name": "my_adventure",
        "version": "1.0",
        "export": "rpg",                  # "rpg" 或 "battle"
        "export_name": "my_adventure",    # 可选，输出文件名（无 .json）
    }
    RPG_DATA = {
        "meta": {"title": "我的冒险"},
        "start_map": "起点",
        "player_name": "勇者",
        "gold": 0,
        "party": [ ... ],
        "maps": { "起点": {"desc": "起点", "exits": {}} },
        # 其它字段同 rpg_data.json
    }
    # ----------------------------------------

转换源 mod 示例（战斗）：
    # ---------- my_battle.mod ----------
    MOD_INFO = {
        "name": "my_battle",
        "version": "1.0",
        "export": "battle",
        "export_name": "my_battle",
    }
    BATTLE_DATA = {
        "party": [ ... ],
        "enemy": [ ... ],
        "items": [ ... ],
        "flavors": [ ... ],
        "stg": { ... },
        # 其它字段同 battle_data.json
    }
    # ----------------------------------------

也可以写函数动态生成：
    def make_rpg():    return { ... }
    def make_battle(): return { ... }

覆盖规则：
  · 目标 JSON 不存在              → 转换
  · 目标 JSON 已存在、内容相同     → 跳过
  · 目标 JSON 已存在、内容不同，
    且 JSON 比源 mod 新（用户改过）→ 跳过，保留用户修改
  · 目标 JSON 已存在、内容不同，
    且源 mod 更新                  → 覆盖（旧 JSON 备份为 .bak）

关闭自动转换：
  把 AUTO_RUN_ON_STARTUP 改成 False。此时不会在启动时扫描，
  但会向引擎模块注册以下函数，可在其他 mod 中手动触发：
      ctx["engine_module"].convert_one_mod("my.mod", force=True)
      ctx["engine_module"].convert_mods_to_json(force=True)
"""

import os
import json


MOD_INFO = {
    "name": "mod_to_json",
    "version": "1.0",
    "game_version": ">=2.0.0",
    "description": "把标记了 export 的 mod 转换成 RPG/战斗 JSON",
}

# 改成 False 可关闭启动时自动扫描（仍可手动调用 convert_mods_to_json）
AUTO_RUN_ON_STARTUP = True


# ==================================================================
#                       工具
# ==================================================================
def _base_dir():
    """返回 mod 所在目录（通常也就是游戏目录）。"""
    try:
        return os.path.dirname(os.path.abspath(__file__))
    except NameError:
        return os.getcwd()


def _load_mod_file(path):
    """在隔离命名空间中执行一个 mod 文件，返回它的全局命名空间。"""
    try:
        with open(path, "r", encoding="utf-8") as f:
            code = f.read()
    except Exception as e:
        return None, f"读取失败：{e}"
    ns = {
        "__file__": path,
        "__name__": "_mod_export_" + os.path.splitext(os.path.basename(path))[0],
    }
    try:
        exec(compile(code, path, "exec"), ns)
    except Exception as e:
        return None, f"执行失败：{type(e).__name__}: {e}"
    return ns, None


def _extract_rpg(ns):
    data = ns.get("RPG_DATA")
    if isinstance(data, dict):
        return data
    fn = ns.get("make_rpg")
    if callable(fn):
        try:
            r = fn()
        except Exception as e:
            print(f"E:make_rpg() 失败：{type(e).__name__}: {e}")
            return None
        return r if isinstance(r, dict) else None
    return None


def _extract_battle(ns):
    data = ns.get("BATTLE_DATA")
    if isinstance(data, dict):
        return data
    fn = ns.get("make_battle")
    if callable(fn):
        try:
            r = fn()
        except Exception as e:
            print(f"E:make_battle() 失败：{type(e).__name__}: {e}")
            return None
        return r if isinstance(r, dict) else None
    return None


# ==================================================================
#                       单个 mod 转换
# ==================================================================
def _convert_one(path, force=False):
    """转换单个 mod 文件。

    返回 (status, message)：
      status = "converted" | "skipped" | "error" | "not_target"
    """
    fn = os.path.basename(path)

    # 1) 加载 mod
    ns, err = _load_mod_file(path)
    if ns is None:
        return "error", f"{fn}: {err}"

    info = ns.get("MOD_INFO")
    if not isinstance(info, dict):
        return "not_target", ""

    export = info.get("export")
    if export not in ("rpg", "battle"):
        return "not_target", ""

    # 2) 提取数据
    if export == "rpg":
        data = _extract_rpg(ns)
        kind = "RPG 冒险"
    else:
        data = _extract_battle(ns)
        kind = "战斗"
    if not isinstance(data, dict):
        return "error", f"{fn}: 标记了 export={export}，但未提供有效数据"

    # 3) 序列化
    try:
        text = json.dumps(data, ensure_ascii=False, indent=2)
    except Exception as e:
        return "error", f"{fn}: 数据无法序列化为 JSON：{e}"

    # 4) 决定输出路径
    base = info.get("export_name") or os.path.splitext(fn)[0]
    target = os.path.join(_base_dir(), f"{base}.json")
    rel = os.path.basename(target)

    # 5) 冲突检测
    if os.path.exists(target):
        try:
            with open(target, "r", encoding="utf-8") as f:
                old = f.read()
        except Exception:
            old = ""

        if old == text:
            return "skipped", f"[{kind}] {fn}: 内容未变"

        if not force:
            try:
                if os.path.getmtime(target) > os.path.getmtime(path):
                    return ("skipped",
                            f"[{kind}] {fn}: 目标已手动修改，保留 {rel}")
            except OSError:
                pass

        # 备份旧内容
        try:
            with open(target + ".bak", "w", encoding="utf-8") as f:
                f.write(old)
        except Exception:
            pass

    # 6) 写入
    try:
        with open(target, "w", encoding="utf-8") as f:
            f.write(text)
    except Exception as e:
        return "error", f"{fn}: 写入 {rel} 失败：{e}"

    return "converted", f"[{kind}] {fn} → {rel}"


# ==================================================================
#                       批量扫描
# ==================================================================
def convert_all(force=False):
    """扫描所有 .mod 文件，把标记了 export 的转换成 JSON。

    返回 (converted, skipped, errors) 计数/列表。
    """
    here = _base_dir()
    try:
        files = sorted(fn for fn in os.listdir(here)
                       if fn.lower().endswith(".mod"))
    except Exception as e:
        return 0, 0, [f"列出 .mod 文件失败：{e}"]

    self_name = ""
    try:
        self_name = os.path.basename(__file__)
    except NameError:
        pass

    converted = 0
    skipped = 0
    errors = []

    for fn in files:
        if fn == self_name:
            continue
        try:
            status, msg = _convert_one(os.path.join(here, fn), force=force)
        except Exception as e:
            errors.append(f"{fn}: {type(e).__name__}: {e}")
            continue

        if status == "converted":
            print(f"  ✓ {msg}")
            converted += 1
        elif status == "skipped":
            print(f"  - {msg}")
            skipped += 1
        elif status == "error":
            errors.append(msg)

    return converted, skipped, errors


# 给外部（其他 mod / 调试用）暴露单个转换入口
def convert_one_mod(path, force=False):
    return _convert_one(path, force=force)


# ==================================================================
#                       引擎钩子
# ==================================================================
def on_engine_load(engine_cls, ctx):
    # 先把函数挂到引擎模块，无论自动转换是否启用都可以调用
    try:
        em = ctx.get("engine_module")
        if em is not None:
            em.convert_one_mod = convert_one_mod
            em.convert_mods_to_json = convert_all
    except Exception:
        pass

    if not AUTO_RUN_ON_STARTUP:
        print("\n*[mod_to_json] 自动转换已关闭 "
              "（把 AUTO_RUN_ON_STARTUP 改成 True 可启用）")
        return

    print("\n*[mod_to_json] 扫描转换源 mod……")
    try:
        converted, skipped, errors = convert_all()
    except Exception as e:
        print(f"E:[mod_to_json] 转换失败：{type(e).__name__}: {e}")
        return

    if converted == 0 and skipped == 0 and not errors:
        print("  （未发现标记 export 的 mod，什么都没做）")
        return

    if converted or skipped:
        print(f"*[mod_to_json] 完成：转换 {converted} 个，跳过 {skipped} 个")
    if errors:
        print("*[mod_to_json] 错误：")
        for e in errors:
            print(f"  · {e}")