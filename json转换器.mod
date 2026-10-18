# -*- coding: utf-8 -*-
"""
json_to_mod.mod —— 把 RPG / 战斗 JSON 转换成 .mod（v1.0）

功能：
  · RPG 编辑器   → "9. 增强工具 → 4. 转换为 mod"
  · 战斗编辑器   → 主菜单 "9. 转换为 mod"
  · 输入 JSON 路径 → 生成对应的 .mod 文件
  · 生成的 .mod 与 mod_to_json.mod 完全兼容，
    可以再被它转回 JSON（闭环）

生成的 .mod 结构：
    MOD_INFO = {"name": ..., "export": "rpg"|"battle",
                "export_name": ..., "version": "1.0"}
    RPG_DATA   = { ... }     # 类型为 rpg
    BATTLE_DATA = { ... }    # 类型为 battle
"""

import os
import json
import copy


MOD_INFO = {
    "name": "json_to_mod",
    "version": "1.0",
    "game_version": ">=2.0.0",
    "description": "在编辑器中添加'转换为 mod'选项，生成 mod_to_json 可识别的转换源 mod",
}


# ==================================================================
#                       基础工具
# ==================================================================
def _base_dir():
    """mod 文件所在目录（即游戏目录）。"""
    try:
        return os.path.dirname(os.path.abspath(__file__))
    except NameError:
        return os.getcwd()


def _detect_kind(data):
    """判定数据是 RPG 还是战斗。"""
    if not isinstance(data, dict):
        return None
    if "maps" in data or "start_map" in data:
        return "rpg"
    if "enemy" in data or "flavors" in data or "stg" in data:
        return "battle"
    return None


def _safe_export_name(name):
    s = "".join(c for c in str(name) if c.isalnum() or c in " _-")
    return s.strip() or "exported"


# ==================================================================
#                       Python 字面量渲染
# ==================================================================
def _py_repr(obj, indent=0):
    """把对象递归渲染成合法的 Python 字面量字符串。

    保证 json.load() 出来的值（dict/list/str/int/float/bool/None）
    全部可被 repr 化为可 exec 的形式。
    """
    pad = "    " * indent
    inner = "    " * (indent + 1)

    if isinstance(obj, dict):
        if not obj:
            return "{}"
        rows = []
        for k, v in obj.items():
            rows.append(f"{inner}{_py_repr(k)}: {_py_repr(v, indent + 1)}")
        return "{\n" + ",\n".join(rows) + "\n" + pad + "}"

    if isinstance(obj, list):
        if not obj:
            return "[]"
        # 纯标量短列表合并为单行更紧凑
        try:
            if all(not isinstance(x, (dict, list)) for x in obj):
                line = "[" + ", ".join(_py_repr(x) for x in obj) + "]"
                if len(line) <= 80:
                    return line
        except Exception:
            pass
        rows = [inner + _py_repr(x, indent + 1) for x in obj]
        return "[\n" + ",\n".join(rows) + "\n" + pad + "]"

    if isinstance(obj, str):
        return repr(obj)
    if obj is True:
        return "True"
    if obj is False:
        return "False"
    if obj is None:
        return "None"
    if isinstance(obj, float):
        # NaN / ±Inf 需要特殊包装
        if obj != obj:
            return "float('nan')"
        if obj == float("inf"):
            return "float('inf')"
        if obj == float("-inf"):
            return "float('-inf')"
        return repr(obj)
    return repr(obj)


def _make_mod_content(export_name, kind, data):
    data_key = "RPG_DATA" if kind == "rpg" else "BATTLE_DATA"
    header = (
        "# -*- coding: utf-8 -*-\n"
        '"""\n'
        f"转换源 mod：{export_name}\n"
        f"类型：{kind}\n"
        "（由 json_to_mod 自动生成，可配合 mod_to_json.mod 转回 JSON）\n"
        '"""\n\n'
    )
    info = (
        "MOD_INFO = {\n"
        f"    \"name\": {_py_repr(export_name)},\n"
        "    \"version\": \"1.0\",\n"
        f"    \"export\": {_py_repr(kind)},\n"
        f"    \"export_name\": {_py_repr(export_name)},\n"
        "}\n\n"
    )
    body = f"{data_key} = {_py_repr(data)}\n"
    return header + info + body


# ==================================================================
#                       转换核心
# ==================================================================
def _convert_file_to_mod(path, export_name=None, ask_bool=None, force=False):
    """把 JSON 文件转换成 .mod。

    返回 (ok: bool, message: str)
        · ok=True 时 message 是输出文件的完整路径
        · ok=False 时 message 是错误/原因
    """
    path = os.path.abspath(path)
    if not os.path.exists(path):
        return False, f"文件不存在：{path}"

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return False, f"读取失败：{e}"

    if not isinstance(data, dict):
        return False, "文件内容不是 JSON 对象"

    kind = _detect_kind(data)
    if kind is None:
        return False, "无法判断类型（既不像 RPG，也不像战斗数据）"

    base = os.path.splitext(os.path.basename(path))[0]
    export_name = _safe_export_name(export_name or base)
    mod_path = os.path.join(_base_dir(), export_name + ".mod")

    if os.path.exists(mod_path) and not force:
        if ask_bool is not None:
            if not ask_bool(f"{export_name}.mod 已存在，覆盖？", False):
                return False, "已取消"
        else:
            return False, (f"目标已存在：{mod_path}"
                           "（传 force=True 可强制覆盖）")

    content = _make_mod_content(export_name, kind, data)
    try:
        with open(mod_path, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception as e:
        return False, f"写入失败：{e}"

    return True, mod_path


# ==================================================================
#                       交互式入口
# ==================================================================
def _interactive_convert(em, default_path=None, default_name=None, ask_bool=None):
    """在编辑器中调用的交互式转换。"""
    print()
    print("=" * 50)
    print("  转换为 mod")
    print("=" * 50)
    print("  把 RPG 或战斗 JSON 转成 .mod 文件。")
    print("  生成的 mod 可被 mod_to_json.mod 反转换回 JSON。")
    print()

    # 默认值解析
    if default_path:
        try:
            default_path = em._resolve_json_path(default_path)
        except Exception:
            pass
        if not os.path.exists(default_path):
            default_path = None

    if default_path:
        hint = f"（默认 {os.path.basename(default_path)}；回车用默认）"
    else:
        hint = "（回车取消）"

    try:
        path = input(f"JSON 文件路径{hint}> ").strip()
    except EOFError:
        return

    if not path:
        if default_path:
            path = default_path
        else:
            print("*已取消")
            return

    try:
        resolved = em._resolve_json_path(path)
    except Exception:
        resolved = path

    if not os.path.exists(resolved):
        print(f"E:文件不存在：{resolved}")
        _pause_input()
        return

    base = os.path.splitext(os.path.basename(resolved))[0]
    name_hint = default_name or _safe_export_name(base)

    try:
        export_name = input(f"导出名（默认 {name_hint}）> ").strip()
    except EOFError:
        export_name = ""
    if not export_name:
        export_name = name_hint

    ok, msg = _convert_file_to_mod(
        resolved,
        export_name=export_name,
        ask_bool=ask_bool,
        force=False,
    )

    if ok:
        print()
        print(f"*已生成 mod：{os.path.basename(msg)}")
        print(f"  完整路径：{msg}")
        print()
        print("  提示：")
        print("    · 该 mod 可被 mod_to_json.mod 转回 JSON")
        print("    · 也可在 M. Mod 管理 里查看详情")
    else:
        print(f"E:{msg}")

    _pause_input()


def _pause_input():
    try:
        input("按回车继续……")
    except EOFError:
        pass


# ==================================================================
#                       Patch：RPG 编辑器
# ==================================================================
def _patch_rpg_editor(em):
    editor_cls = getattr(em, "RPGEditor", None)
    if editor_cls is None:
        return False
    if getattr(editor_cls, "_json_to_mod_patched", False):
        return True  # 已 patch 过

    def new_enhanced_tools(self):
        while True:
            print()
            print("===== 增强工具 =====")
            print("  1. 全局搜索")
            print("  2. 数据统计")
            print("  3. 备份管理")
            print("  4. 转换为 mod  ← 新增")
            print("  Q. 返回")
            try:
                c = input("选择> ").strip().upper()
            except EOFError:
                return
            if c == "Q" or c == "":
                return
            if c == "1":
                self._tool_search()
            elif c == "2":
                self._tool_statistics()
            elif c == "3":
                self._tool_backups()
            elif c == "4":
                # 默认用当前编辑器打开的文件 & 标题作为导出名
                default_path = self.path
                default_name = None
                try:
                    title = (self.data or {}).get("meta", {}).get("title", "")
                    if title:
                        default_name = _safe_export_name(title)
                except Exception:
                    pass
                _interactive_convert(
                    em,
                    default_path=default_path,
                    default_name=default_name,
                    ask_bool=em._ask_bool,
                )

    editor_cls._enhanced_tools = new_enhanced_tools
    editor_cls._json_to_mod_patched = True
    return True


# ==================================================================
#                       Patch：战斗编辑器
# ==================================================================
def _patch_battle_editor(em, battle_mod):
    editor_cls = getattr(battle_mod, "Editor", None)
    if editor_cls is None:
        return False
    if getattr(editor_cls, "_json_to_mod_patched", False):
        return True

    def new_run(self):
        while True:
            name = os.path.basename(self.path) if self.path else "未命名"
            star = "  [未保存]" if self.dirty else ""
            print()
            print("=" * 60)
            print("  回合战斗数据编辑器")
            print("=" * 60)
            print(f"  文件：{name}{star}")
            print("-" * 60)
            print("  1. 编辑队伍")
            print("  2. 编辑敌人")
            print("  3. 编辑物品")
            print("  4. 编辑风味文本")
            print("  5. 编辑 STG 躲避弹幕")
            print("  6. 编辑机制")
            print("  7. 编辑战斗脚本")
            print("  8. 校验数据")
            print("  9. 转换为 mod  ← 新增")
            print("-" * 60)
            print("  O. 打开文件      S. 保存")
            print("  A. 另存为        N. 新建")
            print("  R. 运行          Q. 返回主菜单")
            try:
                c = input("选择> ").strip().upper()
            except EOFError:
                return

            if c == "Q":
                if self._confirm_exit():
                    return
            elif c == "1":
                self.menu_party()
            elif c == "2":
                self.menu_enemies()
            elif c == "3":
                self.menu_items()
            elif c == "4":
                self.menu_flavors()
            elif c == "5":
                self.menu_stg()
            elif c == "6":
                self.menu_mechanics()
            elif c == "7":
                self.menu_script()
            elif c == "8":
                self.validate()
            elif c == "9":
                default_path = self.path
                default_name = None
                if self.path:
                    base = os.path.splitext(os.path.basename(self.path))[0]
                    default_name = _safe_export_name(base)
                _interactive_convert(
                    em,
                    default_path=default_path,
                    default_name=default_name,
                    ask_bool=em._ask_bool,
                )
            elif c == "R":
                self.run_battle()
            elif c == "O":
                if not self._confirm_discard():
                    continue
                try:
                    p = battle_mod._ask_text("文件路径",
                                              self.path or "battle_data.json")
                except Exception:
                    p = input("文件路径> ").strip()
                if p:
                    try:
                        p = battle_mod._resolve_path_for_open(p)
                    except Exception:
                        pass
                    if os.path.exists(p):
                        self.load(p)
                    else:
                        print(f"E:文件不存在：{p}")
            elif c == "S":
                self.save()
            elif c == "A":
                try:
                    p = battle_mod._ask_text("保存为",
                                              self.path or "battle_data.json")
                except Exception:
                    p = input("保存为> ").strip()
                if p:
                    self.save(p)
            elif c == "N":
                if not self._confirm_discard():
                    continue
                self.data = copy.deepcopy(battle_mod.EMPTY_TEMPLATE)
                self.path = None
                self.dirty = True
                print("*已新建空模板")

    editor_cls.run = new_run
    editor_cls._json_to_mod_patched = True
    return True


# ==================================================================
#                       引擎钩子
# ==================================================================
def on_engine_load(engine_cls, ctx):
    em = ctx.get("engine_module")
    battle_mod = ctx.get("battle_module")

    if em is None:
        print("E:[json_to_mod] 无法获取引擎模块，放弃初始化")
        return

    # 把函数挂到引擎模块，供其他 mod / 控制台调用
    try:
        em.json_to_mod_convert = _convert_file_to_mod
        em.json_to_mod_interactive = _interactive_convert
    except Exception:
        pass

    ok_rpg = _patch_rpg_editor(em)
    if ok_rpg:
        print("* [json_to_mod] RPG 编辑器已添加转换选项"
              "（9. 增强工具 → 4. 转换为 mod）")

    if battle_mod is not None and hasattr(battle_mod, "Editor"):
        ok_battle = _patch_battle_editor(em, battle_mod)
        if ok_battle:
            print("* [json_to_mod] 战斗编辑器已添加转换选项"
                  "（主菜单 → 9. 转换为 mod）")
    else:
        print("  （未检测到战斗编辑器，跳过战斗侧 patch）")

    print("  * 提示：转换生成的 .mod 与 mod_to_json.mod 完全兼容，可双向互转")