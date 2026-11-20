# app/settings.gd —— 应用设置（单位制/精度/主题/UI 缩放），经 DataStore 表 "settings" 持久化
#
# 口径依据：
#   - UI 缩放档位（0.8/1.0/1.25/1.5）= 非游戏应用官方建议的 content_scale_factor
#     暴露项，兼作无障碍大字模式（ARCHITECTURE.md §1.3）；
#   - 主题热切换：Theme 是普通资源，可整体切换（调研 gui_skinning 口径）；
#   - decimals：结果小数位（1-12 合法，越界回退默认）。
class_name GKSettings
extends RefCounted

signal changed(key: String, value: Variant)

const TABLE := "settings"
const UI_SCALE_TIERS := [0.8, 1.0, 1.25, 1.5]

const DEFAULTS := {
	"unit_system": "SI",      # SI=国际单位制 / ENGINEERING=工程单位制
	"decimals": 4,            # 结果小数位
	"theme": "light",         # light=main.tres / dark=dark.tres
	"ui_scale": 1.0,          # content_scale_factor 档位
	"angle_input_style": "decimal",  # decimal=十进制度 / dms=度分秒优先
}

var _store: GKDataStore
var _values: Dictionary = {}

func _init(store: GKDataStore) -> void:
	_store = store
	_values = DEFAULTS.duplicate(true)
	for row: Dictionary in _store.load_table(TABLE):
		var key := String(row.get("key", ""))
		if DEFAULTS.has(key):
			_values[key] = row.get("value", DEFAULTS[key])

func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))

func get_decimals() -> int:
	var d := int(get_value("decimals"))
	if d < 1 or d > 12:
		return int(DEFAULTS["decimals"])
	return d

func set_value(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key):
		return false
	if key == "decimals" and (int(value) < 1 or int(value) > 12):
		return false
	if key == "ui_scale" and not UI_SCALE_TIERS.has(float(value)):
		return false
	if key == "theme" and not (value == "light" or value == "dark"):
		return false
	_values[key] = value
	_persist_key(key, value)
	changed.emit(key, value)
	return true

func _persist_key(key: String, value: Variant) -> void:
	# 设置项为"键值对表"：先删旧键行再追加（规模极小，整表重写亦可，但走行级更清晰）
	for row: Dictionary in _store.load_table(TABLE):
		if String(row.get("key", "")) == key:
			_store.delete_row(TABLE, int(row.get("rid", 0)))
	_store.append_row(TABLE, {"key": key, "value": value})

## 应用 UI 缩放到窗口（无障碍档位）
func apply_ui_scale(win: Window) -> void:
	win.content_scale_factor = float(get_value("ui_scale"))

## 应用主题到窗口：light → 恢复项目设置主题（main.tres）；dark → 热切换 dark.tres。
## 返回当前生效主题资源（light 返回 null 表示回落项目设置）。
func apply_theme(win: Window) -> Theme:
	var t := String(get_value("theme"))
	if t == "dark":
		var dark := load("res://themes/dark.tres") as Theme
		win.theme = dark
		return dark
	win.theme = null
	return null
