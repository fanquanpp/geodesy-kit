# scenes/calculators/projection/zone_switch.gd —— a4_zone_switch 换带计算（A4 3°/6°）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _ZN := preload("res://core/projection/zones.gd")

func get_title() -> String:
	return "换带计算（A4 3°/6°）"

func get_description() -> String:
	return "原带高斯坐标 → 经纬度 → 新带坐标；换带限界 ±3.5°，超限中文提示改 6° 带。"

func _setup() -> void:
	_add_row("北坐标 x（m）", "x_m", "原带 x", true)
	_add_row("东坐标 y（m）", "y_m", "原带 y（自然 y）", true)
	_add_row("原中央子午线 L0（°）", "l0_from_deg", "如 117", true)
	_add_row("目标带宽（3 或 6）", "to_band", "3 / 6", true)
	_add_row("目标带号（可空自动）", "to_zone", "如 40（留空按经度自动）", false)
	_add_row("基准", "datum", "CGCS2000 / 北京54 / 西安80", false, LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _ZN.switch_zone(p)
