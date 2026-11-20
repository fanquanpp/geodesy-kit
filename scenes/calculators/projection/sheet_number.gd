# scenes/calculators/projection/sheet_number.gd —— sheet_gbt13989 地形图分幅编号（GB/T 13989）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _SH := preload("res://core/projection/sheet_gbt13989.gd")

func get_title() -> String:
	return "地形图分幅编号（GB/T 13989）"

func get_description() -> String:
	return "B/L → 图幅编号（1:100万 6°×4° 行 A-V 列 21-72；比例尺代码 B~K；行号自西北角起算）。"

func _setup() -> void:
	_add_row("纬度 B（°或度分秒）", "lat_deg", "如 39°54′27.1″", true)
	_add_row("经度 L（°或度分秒）", "lon_deg", "如 116°23′28.6″", true)
	_add_row("比例尺分母", "scale_denom", "1000000/500000/250000/100000/50000/25000/10000/5000", true)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _SH.forward(p)
