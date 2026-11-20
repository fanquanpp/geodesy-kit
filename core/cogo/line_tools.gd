# core/cogo/line_tools.gd —— GK-M5：点线关系（B8 点在线上/桩号偏距/垂足/点到线距）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M5 / §5 协议）：
#   - 纯静态函数、零引擎依赖；坐标/方位角约定同 cogo.gd（x=东、y=北、北起顺时针）；
#   - 线定义：起点 (x0,y0) + 坐标方位角 az（射线）；里程（桩号）沿方位方向为正；
#   - 投影：桩号 st = Δx·sin α + Δy·cos α；偏距 off = Δx·cos α − Δy·sin α（右侧为正，
#     右 = 沿线方位顺时针转 90°，法向量 (cos α, −sin α)）；
#   - 每个计算入口统一返回 §5 协议 {ok, value, steps, formula, error}。
class_name GKLineTools
extends RefCounted

const ON_LINE_TOL := 1e-6  # 点在线上判定阈值（m）

## 纯原语：点到射线（起点+方位）的投影。返回 {station, offset, dist, az_pt_deg, foot_x, foot_y}。
static func point_line(x0: float, y0: float, az_deg: float, x: float, y: float) -> Dictionary:
	if not (is_finite(x0) and is_finite(y0) and is_finite(az_deg) and is_finite(x) and is_finite(y)):
		return {}
	var ar := deg_to_rad(az_deg)
	var sa := sin(ar)
	var ca := cos(ar)
	var dx := x - x0
	var dy := y - y0
	var station := dx * sa + dy * ca
	var offset := dx * ca - dy * sa
	var fx := x0 + station * sa
	var fy := y0 + station * ca
	return {
		"station": station,
		"offset": offset,
		"dist": sqrt(dx * dx + dy * dy),
		"az_pt_deg": GKAngles.azimuth(dx, dy),
		"foot_x": fx, "foot_y": fy,
	}

## B8 桩号与偏距（含垂足与点线距）。输入：{x0_m, y0_m, az_deg, x_m, y_m, len_m(可选)}。
## len_m 给出线长时，桩号超出 [0, len] 附加检核步骤提示（不判失败）。
static func point_line_rel(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x0 := _num(p, "x0_m", "起点 x", bad)
	var y0 := _num(p, "y0_m", "起点 y", bad)
	var az := _ang(p, "az_deg", "线方位角", bad)
	var x := _num(p, "x_m", "待检查点 x", bad)
	var y := _num(p, "y_m", "待检查点 y", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var has_len := false
	var len_v := 0.0
	if p.has("len_m"):
		len_v = _num(p, "len_m", "线长", bad)
		if not bad.is_empty():
			return _fail(_join_bad(bad))
		if len_v < 0.0:
			return _fail("线长不能为负数")
		has_len = len_v > 0.0
	var r := point_line(x0, y0, az, x, y)
	var st: float = r["station"]
	var off: float = r["offset"]
	var dist: float = r["dist"]
	var az_pt: float = r["az_pt_deg"]
	var side_txt := "线上"
	if off > ON_LINE_TOL:
		side_txt = "右侧"
	elif off < -ON_LINE_TOL:
		side_txt = "左侧"
	var on_line := absf(off) <= ON_LINE_TOL
	var steps := [
		_step("1. 计算桩号（沿线投影）", "st = Δx·sin α + Δy·cos α",
			"st = %s·sin %s + %s·cos %s" % [_f(x - x0), GKAngles.deg_to_dms_str(az), _f(y - y0), GKAngles.deg_to_dms_str(az)],
			"st = %s m" % _f(st)),
		_step("2. 计算偏距（右正左负）", "off = Δx·cos α − Δy·sin α（右 = 沿线方位顺时针 90°）",
			"off = %s·cos %s − %s·sin %s" % [_f(x - x0), GKAngles.deg_to_dms_str(az), _f(y - y0), GKAngles.deg_to_dms_str(az)],
			"off = %s m（%s）" % [_f(off), side_txt]),
		_step("3. 垂足与点线距", "垂足 = 起点 + st·u(α)；点线距 = |off|；直线距离 = √(Δx²+Δy²)",
			"垂足由桩号回投；|off| = %s" % _f(absf(off)),
			"垂足 (%s, %s)，点线距 = %s m，直线距离 = %s m" % [_f(r["foot_x"]), _f(r["foot_y"]), _f(absf(off)), _f(dist)]),
	]
	if has_len and (st < 0.0 or st > len_v):
		steps.append(_step("4. 桩号范围检核", "0 ≤ st ≤ 线长",
			"线长 = %s m，桩号 = %s m" % [_f(len_v), _f(st)],
			"桩号超出线段范围 [0, %s]（点位于射线延长段）" % _f(len_v)))
	else:
		steps.append(_step("4. 桩号范围检核", "0 ≤ st ≤ 线长" if has_len else "未提供线长，跳过范围检核",
			"桩号 = %s m" % _f(st),
			"桩号在范围内" if has_len else "如需范围检核请输入线长"))
	return {
		"ok": true,
		"value": {
			"station_m": st, "offset_m": off,
			"dist_m": dist, "side": side_txt,
			"on_line": on_line,
			"az_pt_deg": az_pt, "az_pt_dms": GKAngles.deg_to_dms_str(az_pt),
			"x_foot_m": r["foot_x"], "y_foot_m": r["foot_y"],
			"point_line_dist_m": absf(off),
		},
		"steps": steps,
		"formula": "点线投影：st = Δx·sin α + Δy·cos α（桩号），off = Δx·cos α − Δy·sin α（偏距，右正）。"
			+ "垂足 = 起点 + st·u(α)；点线距 = |off|。",
		"error": "",
	}

## B8 垂足（含桩号/偏距回显）。输入：{x0_m, y0_m, az_deg, x_m, y_m}。
static func foot(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x0 := _num(p, "x0_m", "起点 x", bad)
	var y0 := _num(p, "y0_m", "起点 y", bad)
	var az := _ang(p, "az_deg", "线方位角", bad)
	var x := _num(p, "x_m", "已知点 x", bad)
	var y := _num(p, "y_m", "已知点 y", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var r := point_line(x0, y0, az, x, y)
	var st: float = r["station"]
	var off: float = r["offset"]
	return {
		"ok": true,
		"value": {
			"x_foot_m": r["foot_x"], "y_foot_m": r["foot_y"],
			"station_m": st, "offset_m": off,
			"point_line_dist_m": absf(off),
		},
		"steps": [
			_step("1. 计算桩号", "st = Δx·sin α + Δy·cos α",
				"st = %s" % _f(st),
				"st = %s m" % _f(st)),
			_step("2. 计算垂足坐标", "x_F = x0 + st·sin α；y_F = y0 + st·cos α",
				"x_F = %s + %s·sin %s；y_F = %s + %s·cos %s" % [
					_f(x0), _f(st), GKAngles.deg_to_dms_str(az),
					_f(y0), _f(st), GKAngles.deg_to_dms_str(az)],
				"垂足 = (%s, %s)" % [_f(r["foot_x"]), _f(r["foot_y"])]),
			_step("3. 点线距", "|off| = |Δx·cos α − Δy·sin α|",
				"off = %s" % _f(off),
				"点线距 = %s m" % _f(absf(off))),
		],
		"formula": "垂足：将已知点沿线方位投影，F = (x0 + st·sin α, y0 + st·cos α)；点线距 = |偏距|。",
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

static func _num(p: Dictionary, key: String, label: String, bad: Array) -> float:
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
		var t := String(v).strip_edges().replace("−", "-")
		if t.is_empty():
			bad.append("请输入「%s」" % label)
			return NAN
		if t.is_valid_float():
			var f2 := t.to_float()
			if is_finite(f2):
				return f2
		bad.append("「%s」不是有效数字：%s" % [label, t])
		return NAN
	bad.append("「%s」输入类型不支持" % label)
	return NAN

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
