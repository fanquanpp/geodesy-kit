# core/cogo/angle_tools.gd —— GK-M5：角度格式/象限角换算（B5，调 M1 GKAngles）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M5）：
#   - 本文件是 M1 角度库的计算器化封装：全部换算委托 GKAngles，本文件不重复实现换算定义；
#   - 换算定义：1 gon = 0.9°（一周 400 gon）；1 rad = 180°/π；
#     度分秒只接受显式分隔（°′″、空格、-、:），"30.5" 一律按十进制度；
#   - 每个计算入口统一返回 §5 协议 {ok, value, steps, formula, error}。
class_name GKAngleTools
extends RefCounted

## B5 角度换算：输入十进制度（或度分秒文本）→ 度/度分秒/gon/rad/象限角。
## 输入：{deg: float} 或 {dms: String}。
static func convert(p: Dictionary) -> Dictionary:
	var deg := NAN
	if p.has("deg"):
		var v: Variant = p["deg"]
		if v is float or v is int:
			deg = float(v)
		elif v is String:
			deg = GKAngles.parse_dms(String(v))
	elif p.has("dms") and p["dms"] is String:
		deg = GKAngles.parse_dms(String(p["dms"]))
	if is_nan(deg) or not is_finite(deg):
		return _fail("角度输入不合法：请输十进制度（如 30.5）或度分秒（如 30°30′00″ / 30 30 00）")
	var d: Dictionary = GKAngles.deg_to_dms(deg, 1)
	var gon := GKAngles.deg_to_gon(deg)
	var rad := deg_to_rad(deg)
	var q: Dictionary = GKAngles.quadrant_from_azimuth(GKAngles.normalize_deg(deg))
	return {
		"ok": true,
		"value": {
			"deg": deg, "dms": GKAngles.deg_to_dms_str(deg, 1),
			"gon": gon, "rad": rad,
			"quadrant_text": q["text"], "quadrant_angle_deg": q["angle_deg"],
		},
		"steps": [
			_step("1. 角度规范化", "α = 原角 mod 360°（规范化到 [0°, 360°)）",
				"α = %s°" % _f(GKAngles.normalize_deg(deg), 6),
				"α = %s°" % _f(GKAngles.normalize_deg(deg), 6)),
			_step("2. 十进制度 → 度分秒", "D°M′S″：M = (角×60) mod 60，S = (角×3600) mod 60",
				"%s° → D=%s，M=%s，S=%s" % [_f(deg, 6), str(int(d["d"])), str(int(d["m"])), _f(d["s"], 1)],
				GKAngles.deg_to_dms_str(deg, 1)),
			_step("3. 换算 gon 与弧度", "gon = 角×10/9（1 gon = 0.9°）；rad = 角×π/180",
				"gon = %s×10/9；rad = %s×π/180" % [_f(deg, 6), _f(deg, 6)],
				"gon = %s，rad = %s" % [_f(gon, 6), _f(rad, 9)]),
			_step("4. 象限角", "北东 [0°,90°] / 南东 (90°,180°] / 南西 (180°,270°] / 北西 (270°,360°)",
				"方位 %s° 落入对应象限" % _f(GKAngles.normalize_deg(deg), 4),
				String(q["text"])),
		],
		"formula": "角度换算定义：1 gon = 0.9°（一周 = 400 gon）；1 rad = 180°/π；"
			+ "度分秒为六十进制。度分秒文本只接受显式分隔符，30.5 一律按十进制度。",
		"error": "",
	}

## B5 方位角 → 象限角。输入：{az_deg}。
static func az_to_quadrant(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var az := _ang(p, "az_deg", "方位角", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var az_n := GKAngles.normalize_deg(az)
	var q: Dictionary = GKAngles.quadrant_from_azimuth(az_n)
	return {
		"ok": true,
		"value": {
			"az_deg": az_n, "az_dms": GKAngles.deg_to_dms_str(az_n),
			"quadrant": q["quadrant"], "quadrant_angle_deg": q["angle_deg"],
			"text": q["text"],
		},
		"steps": [
			_step("1. 方位角规范化", "α = 原角 mod 360°",
				"α = %s°" % _f(az_n, 6),
				"α = %s°" % _f(az_n, 6)),
			_step("2. 判定象限并求象限角", "R = |α − 象限主值|（北东 α、南东 180°−α、南西 α−180°、北西 360°−α）",
				"α = %s°" % _f(az_n, 4),
				"%s（象限角 %s°）" % [String(q["quadrant"]), _f(q["angle_deg"], 6)]),
		],
		"formula": "象限角：从北或南起算的锐角。分区：北东 [0°,90°]、南东 (90°,180°]、"
			+ "南西 (180°,270°]、北西 (270°,360°)。",
		"error": "",
	}

## B5 象限角 → 方位角。输入：{quadrant: String, angle_deg: float}。
## 象限名接受 北东/NE/南东/SE/南西/SW/北西/NW（大小写不敏感）。
static func quadrant_to_az(p: Dictionary) -> Dictionary:
	var bad: Array = []
	if not p.has("quadrant") or not (p["quadrant"] is String):
		return _fail("缺少象限名（北东/南东/南西/北西 或 NE/SE/SW/NW）")
	var angle := _ang(p, "angle_deg", "象限角值", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var qname := String(p["quadrant"]).strip_edges()
	if angle < 0.0 or angle > 90.0:
		return _fail("象限角必须是 [0°, 90°] 内的锐角（输入 %s°）" % _f(angle, 4))
	var az := GKAngles.azimuth_from_quadrant(qname, angle)
	if is_nan(az):
		return _fail("无法识别的象限名：%s（请输 北东/南东/南西/北西 或 NE/SE/SW/NW）" % qname)
	return {
		"ok": true,
		"value": {
			"az_deg": az, "az_dms": GKAngles.deg_to_dms_str(az),
			"quadrant": qname, "quadrant_angle_deg": angle,
		},
		"steps": [
			_step("1. 象限名解析", "北东 → α = R；南东 → α = 180° − R；南西 → α = 180° + R；北西 → α = 360° − R",
				"象限 = %s，R = %s°" % [qname, _f(angle, 6)],
				"α = %s°" % _f(az, 6)),
			_step("2. 规范化到 [0°, 360°)", "α = 原角 mod 360°",
				"α = %s°" % _f(az, 6),
				GKAngles.deg_to_dms_str(az)),
		],
		"formula": "象限角 → 方位角：按象限分别换算（北东加 0°、南东 180°−R、南西 180°+R、北西 360°−R）。",
		"error": "",
	}

## B5 方位角推算。输入：{az_prev_deg, angle_deg, turn}；turn："左"（左角）/"右"（右角）。
static func propagate(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var az_prev := _ang(p, "az_prev_deg", "前一边方位角", bad)
	var angle := _ang(p, "angle_deg", "转折角", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var is_left := true
	if p.has("turn"):
		var t := String(p["turn"]).strip_edges().to_lower()
		if t == "右" or t == "r" or t == "right":
			is_left = false
		elif t == "左" or t == "l" or t == "left" or t.is_empty():
			is_left = true
		else:
			return _fail("转折角类型只支持 左/右，输入：%s" % t)
	var az_new := GKAngles.propagate_azimuth(az_prev, angle, is_left)
	var turn_txt := "左角" if is_left else "右角"
	var formula := "α_后 = α_前 + β − 180°（左角）" if is_left else "α_后 = α_前 − β + 180°（右角）"
	return {
		"ok": true,
		"value": {
			"az_prev_deg": GKAngles.normalize_deg(az_prev),
			"angle_deg": angle,
			"turn": turn_txt,
			"az_new_deg": az_new, "az_new_dms": GKAngles.deg_to_dms_str(az_new),
		},
		"steps": [
			_step("1. 方位角推算", formula,
				"α_前 = %s°，β = %s°（%s）" % [_f(GKAngles.normalize_deg(az_prev), 6), _f(angle, 6), turn_txt],
				"α_后 = %s°" % _f(az_new, 6)),
			_step("2. 规范化到 [0°, 360°)", "α = 原角 mod 360°（越周自动回卷）",
				"α_后 = %s°" % _f(az_new, 6),
				GKAngles.deg_to_dms_str(az_new)),
		],
		"formula": "方位角推算：左角 α_后 = α_前 + β − 180°；右角 α_后 = α_前 − β + 180°。结果规范化到 [0°, 360°)。",
		"error": "",
	}

# ---------- 协议小工具 ----------

static func _step(title: String, formula: String, substitution: String, result: String) -> Dictionary:
	return {"title": title, "formula": formula, "substitution": substitution, "result": result}

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}

static func _f(v: float, n := 4) -> String:
	var fmt := "%." + str(n) + "f"
	return fmt % v

static func _join_bad(bad: Array) -> String:
	var out := ""
	for i in bad.size():
		if i > 0:
			out += "；"
		out += String(bad[i])
	return out

static func _ang(p: Dictionary, key: String, label: String, bad: Array) -> float:
	if not p.has(key):
		bad.append("缺少输入项「%s」" % label)
		return NAN
	var v: Variant = p[key]
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return f
		bad.append("「%s」数值非有限" % label)
		return NAN
	if v is String:
		var t := String(v).strip_edges()
		if t.is_empty():
			bad.append("请输入「%s」" % label)
			return NAN
		var deg := GKAngles.parse_dms(t)
		if is_nan(deg):
			bad.append("「%s」不是有效角度：%s（可输 30.5 或 30 30 00）" % [label, t])
			return NAN
		return deg
	bad.append("「%s」输入类型不支持" % label)
	return NAN
