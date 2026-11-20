# scenes/calculators/projection/lambert_inverse.gd —— a14_lambert_inv 兰勃特等角圆锥反算（A14）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _LB := preload("res://core/projection/lambert.gd")

func get_title() -> String:
	return "兰勃特等角圆锥反算（A14）"

func get_description() -> String:
	return "兰勃特平面坐标 → B/L（φ 精确迭代）。"

func _setup() -> void:
	_add_row("x（m）", "x_m", "如 652301.565", true)
	_add_row("y（m）", "y_m", "如 6861302.726", true)
	_add_row("标准纬线 φ1（°）", "phi1_deg", "如 49", true)
	_add_row("第二标准纬线 φ2（°）", "phi2_deg", "2SP 时填写，如 44；留空按 1SP", false)
	_add_row("原点纬度 φ0（°）", "phi0_deg", "如 46.5", true)
	_add_row("原点经度 L0（°）", "lon0_deg", "如 3", true)
	_add_row("假东 FE（m）", "fe_m", "如 700000", false)
	_add_row("假北 FN（m）", "fn_m", "如 6600000", false)
	_add_row("基准", "datum", "GRS80 / CGCS2000 / WGS84", false)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _LB.inverse(p)
