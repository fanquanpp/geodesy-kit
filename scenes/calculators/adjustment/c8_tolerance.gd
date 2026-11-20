# scenes/calculators/adjustment/c8_tolerance.gd —— C8 限差检核计算器（自输限差模式 + 可选查表）
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const TL := preload("res://core/adjustment/tolerance.gd")

func _build_fields() -> void:
	_add_section("标量检核（角度闭合差 fβ / 高差闭合差 fh 等）")
	add_input_row("检核项名称", "name", "角度闭合差")
	add_input_row("实际值", "actual", "2.4")
	add_input_row("限差（±双侧）", "limit", "8")
	add_input_row("单位（仅展示，如 ″ / mm）", "unit", "″")
	add_input_row("依据（如：用户输入限差·图根级）", "basis", "用户输入限差（图根级自定）")
	_add_section("相对闭合差检核（可选，如导线 1/k）")
	add_input_row("实际 1/k 的 k", "actual_k", "")
	add_input_row("限差 1/k 的 k", "limit_k", "")

func run() -> Dictionary:
	var errors := PackedStringArray()
	var name: String = String(_field_text("name")).strip_edges()
	var actual := _num(_field_text("actual"))
	var limit := _num(_field_text("limit"))
	var unit: String = String(_field_text("unit")).strip_edges()
	var basis: String = String(_field_text("basis")).strip_edges()
	if name.is_empty():
		errors.append("检核项名称不能为空")
	if is_nan(actual):
		errors.append("实际值须为数字")
	if is_nan(limit) or limit < 0.0:
		errors.append("限差须为非负数字")
	if errors.size() > 0:
		return _parse_fail(errors)
	var res := TL.check_scalar({"name": name, "actual": actual, "limit": limit,
		"unit": unit, "basis": basis})
	# 相对闭合差（可选）：两项都填才检核，并把结果并进 value
	var ak_t := _field_text("actual_k").strip_edges()
	var lk_t := _field_text("limit_k").strip_edges()
	if not ak_t.is_empty() and not lk_t.is_empty():
		var ak := _num(ak_t)
		var lk := _num(lk_t)
		if is_nan(ak) or ak <= 0.0 or is_nan(lk) or lk <= 0.0:
			var e2: Dictionary = _parse_fail(PackedStringArray(["相对闭合差的 k 须为正数"]))
			return e2
		var r2 := TL.check_relative({"name": name, "actual_k": ak, "limit_k": lk, "basis": basis})
		if bool(r2.get("ok", false)):
			var v: Dictionary = res["value"]
			v["rel_actual_k"] = ak
			v["rel_limit_k"] = lk
			v["ok_limit"] = bool(v.get("ok_limit", true)) and bool(r2["value"]["ok_limit"])
			res["steps"] = res["steps"] + r2["steps"]
	return res

func get_title() -> String:
	return "限差检核（C8）"

func get_description() -> String:
	return "超限提示含三要素（实际值/限差值/依据）。⚠ 规范限差表（GB 50026 等）未核读前 data/tolerance.json 为占位空表，本页按用户自输限差检核——请如实填写依据。"

func get_entry_id() -> String:
	return "c8_tolerance"
