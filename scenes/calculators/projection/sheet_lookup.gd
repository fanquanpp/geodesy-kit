# scenes/calculators/projection/sheet_lookup.gd —— sheet_gbt13989_lookup 图幅范围反查（GB/T 13989）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _SH := preload("res://core/projection/sheet_gbt13989.gd")

func get_title() -> String:
	return "图幅范围反查（GB/T 13989）"

func get_description() -> String:
	return "由图幅编号给出该图经纬范围（行自西北角起算）。"

func _setup() -> void:
	_add_row("图幅编号", "sheet_code", "如 J50E001010 或 J50", true)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _SH.lookup(p)
