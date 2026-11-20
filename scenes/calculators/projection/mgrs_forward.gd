# scenes/calculators/projection/mgrs_forward.gd —— a13_mgrs_fwd MGRS 编码（A13）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _MG := preload("res://core/projection/mgrs.gd")

func get_title() -> String:
	return "MGRS 编码（A13）"

func get_description() -> String:
	return "B/L → MGRS 网格参考串（US NGA 字母方格方案，含挪威/斯瓦尔巴例外与 UPS）。"

func _setup() -> void:
	_add_row("纬度 B（°或度分秒）", "lat_deg", "如 39.9075278", true)
	_add_row("经度 L（°）", "lon_deg", "如 116.3912778", true)
	_add_row("精度位数", "precision", "1=10km … 5=1m（缺省 5）", false)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _MG.forward(p)
