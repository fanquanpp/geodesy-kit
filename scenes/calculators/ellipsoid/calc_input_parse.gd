# scenes/calculators/ellipsoid/calc_input_parse.gd —— 椭球域计算器共享输入解析（UI 层）
# 职责：文本框 → 数值的统一校验入口；非法输入由调用方给中文错误提示，不崩进程。
# 角度字段支持度分秒（53°48′33.82″ / 53 48 33.82）与十进制度（53.8094）两种写法。
class_name GKCalcInputParse
extends RefCounted

## 角度文本 → 十进制度。支持度分秒与十进制；非法返回 NAN。
static func parse_angle(text: String) -> float:
	var t := text.strip_edges()
	if t.is_empty():
		return NAN
	if t.is_valid_float():
		return t.to_float()
	var dms := GKAngles.parse_dms(t)
	return dms  # NAN 表示解析失败

## 纯数值文本 → float。非法/空返回 NAN。
static func parse_number(text: String) -> float:
	var t := text.strip_edges()
	if t.is_empty() or not t.is_valid_float():
		return NAN
	return t.to_float()

## 角度是否有效（含 ±90 界内检查，is_polar 允许 ±90）
static func is_lat_ok(lat: float, allow_pole := true) -> bool:
	if not is_finite(lat):
		return false
	if allow_pole:
		return absf(lat) <= 90.0
	return absf(lat) < 90.0

## 三组文本框判空：全空 → true
static func all_empty(texts: Array) -> bool:
	for t: String in texts:
		if not t.strip_edges().is_empty():
			return false
	return true
