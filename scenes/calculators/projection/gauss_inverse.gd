# scenes/calculators/projection/gauss_inverse.gd —— a3_gauss_inv 高斯投影计算器（反算）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _GK := preload("res://core/projection/gauss_kruger.gd")

func get_title() -> String:
	return "高斯投影计算器（反算）"

func get_description() -> String:
	return "高斯平面坐标 → B/L（μ1 迭代底点纬度 + Newton 精化，与 pyproj 复核 ≤0.02mm）。"

func _setup() -> void:
	_add_row("北坐标 x（m）", "x_m", "如 3597986.6234", true)
	_add_row("东坐标 y（m，含 500km 假东）", "y_m", "如 617474.9201", true)
	_add_row("中央子午线 L0（°）", "l0_deg", "如 117", true)
	_add_row("基准", "datum", "CGCS2000 / 北京54 / 西安80 / WGS84", false, LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _GK.inverse(p)
