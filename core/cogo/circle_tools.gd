# core/cogo/circle_tools.gd —— GK-M5：三点定圆（B9）+ 圆弧要素反算
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M5 / §5 协议）：
#   - 纯静态函数、零引擎依赖；坐标/方位角约定同 cogo.gd（x=东、y=北、北起顺时针）；
#   - 三点定圆：两弦垂直平分线联立（等价于线性方程组），
#     2(x₂−x₁)·X + 2(y₂−y₁)·Y = x₂²+y₂²−x₁²−y₁² 与 2(x₃−x₁)·X + 2(y₃−y₁)·Y = … ；
#     三点共线（行列式≈0）无解；
#   - 圆弧要素：圆心角 Δ（顺/逆时针方向化到 (0°, 360°]）、弧长 L = R·Δrad、
#     弦长 C = 2R·sin(Δ/2)、弓高 f = R(1−cos(Δ/2))、扇形面积 = R²Δrad/2、
#     弓形面积 = R²(Δrad − sin Δrad)/2（Δ>180° 时为优弧弓形）；
#   - 每个计算入口统一返回 §5 协议 {ok, value, steps, formula, error}。
class_name GKCircleTools
extends RefCounted

## 纯原语：三点外接圆。返回 {cx, cy, r}；共线/重复点/非有限 → {}。
static func circumcircle(x1: float, y1: float, x2: float, y2: float, x3: float, y3: float) -> Dictionary:
	if not (is_finite(x1) and is_finite(y1) and is_finite(x2) and is_finite(y2)
			and is_finite(x3) and is_finite(y3)):
		return {}
	var a1 := 2.0 * (x2 - x1)
	var b1 := 2.0 * (y2 - y1)
	var c1 := x2 * x2 + y2 * y2 - x1 * x1 - y1 * y1
	var a2 := 2.0 * (x3 - x1)
	var b2 := 2.0 * (y3 - y1)
	var c2 := x3 * x3 + y3 * y3 - x1 * x1 - y1 * y1
	var det := a1 * b2 - a2 * b1
	var scale := maxf(absf(a1 * b2), absf(a2 * b1))
	if absf(det) < 1e-10 * maxf(scale, 1.0):
		return {}  # 三点共线或重合
	var cx := (c1 * b2 - c2 * b1) / det
	var cy := (a1 * c2 - a2 * c1) / det
	var dx := x1 - cx
	var dy := y1 - cy
	return {"cx": cx, "cy": cy, "r": sqrt(dx * dx + dy * dy)}

## B9 三点定圆。输入：{x1_m, y1_m, x2_m, y2_m, x3_m, y3_m}。
static func three_point_circle(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x1 := _num(p, "x1_m", "点1 x", bad)
	var y1 := _num(p, "y1_m", "点1 y", bad)
	var x2 := _num(p, "x2_m", "点2 x", bad)
	var y2 := _num(p, "y2_m", "点2 y", bad)
	var x3 := _num(p, "x3_m", "点3 x", bad)
	var y3 := _num(p, "y3_m", "点3 y", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var r := circumcircle(x1, y1, x2, y2, x3, y3)
	if r.is_empty():
		return _fail("三点共线或存在重合点，不能确定唯一的圆")
	var cx: float = r["cx"]
	var cy: float = r["cy"]
	var rad: float = r["r"]
	# 半径检核：三点到圆心距离互差
	var d1 := inv_len(cx, cy, x1, y1)
	var d2 := inv_len(cx, cy, x2, y2)
	var d3 := inv_len(cx, cy, x3, y3)
	var rdiff := maxf(maxf(absf(d1 - d2), absf(d2 - d3)), absf(d1 - d3))
	return {
		"ok": true,
		"value": {
			"cx_m": cx, "cy_m": cy, "r_m": rad,
			"r_diff_m": rdiff,
			"d1_m": d1, "d2_m": d2, "d3_m": d3,
		},
		"steps": [
			_step("1. 建立垂直平分线方程组", "2(x₂−x₁)X + 2(y₂−y₁)Y = x₂²+y₂²−x₁²−y₁²（与点 1、3 同理）",
				"两条弦的垂直平分线联立（2×2 线性方程组）",
				"行列式 |D| = %s" % _f(_det_val(x1, y1, x2, y2, x3, y3), 6)),
			_step("2. 解圆心", "克莱姆法则解 (X, Y)",
				"X、Y 由方程组直接解出",
				"圆心 = (%s, %s)" % [_f(cx), _f(cy)]),
			_step("3. 半径与检核", "R = |P₁ − 圆心|；检核三点到圆心距离互差",
				"R₁ = %s，R₂ = %s，R₃ = %s" % [_f(d1), _f(d2), _f(d3)],
				"R = %s m，互差 = %s m" % [_f(rad), _f(rdiff, 9)]),
		],
		"formula": "三点定圆：圆心是两弦垂直平分线交点（等价线性方程组），R 为圆心到任一点距离。"
			+ "三点共线时方程组奇异，无解。",
		"error": "",
	}

## B9 圆弧要素反算（方位式）。输入：{cx_m, cy_m, r_m, az1_deg, az2_deg, dir}。
## dir："cw"（顺时针，默认）/"ccw"（逆时针）。az1=az2 时按全圆 360° 处理。
static func arc_by_azimuth(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var cx := _num(p, "cx_m", "圆心 x", bad)
	var cy := _num(p, "cy_m", "圆心 y", bad)
	var rad := _num(p, "r_m", "半径 R", bad)
	var az1 := _ang(p, "az1_deg", "起始方位角", bad)
	var az2 := _ang(p, "az2_deg", "终止方位角", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var dir_txt := "顺时针"
	var is_cw := true
	if p.has("dir"):
		var t := String(p["dir"]).strip_edges().to_lower()
		if t == "ccw" or t == "逆时针" or t == "逆" or t == "l":
			dir_txt = "逆时针"
			is_cw = false
		elif t == "cw" or t == "顺时针" or t == "顺" or t == "r" or t.is_empty():
			dir_txt = "顺时针"
			is_cw = true
		else:
			return _fail("弧方向只支持 cw（顺时针）或 ccw（逆时针），输入：%s" % t)
	if rad <= 0.0:
		return _fail("半径必须为正数（输入 %.4f）" % rad)
	var a1 := GKAngles.normalize_deg(az1)
	var a2 := GKAngles.normalize_deg(az2)
	# 展开角：顺时针 Δ = (a2−a1) mod 360；逆时针 Δ = (a1−a2) mod 360；相等 → 全圆 360°
	var delta := GKAngles.normalize_deg(a2 - a1) if is_cw else GKAngles.normalize_deg(a1 - a2)
	var full_circle := false
	if absf(delta) < 1e-9:
		delta = 360.0
		full_circle = true
	var e := arc_elements(rad, delta)
	return {
		"ok": true,
		"value": {
			"az1_deg": a1, "az2_deg": a2, "dir": dir_txt,
			"delta_deg": delta, "delta_dms": GKAngles.deg_to_dms_str(delta),
			"r_m": rad,
			"arc_m": e["arc"], "chord_m": e["chord"],
			"sagitta_m": e["sagitta"],
			"sector_area_m2": e["sector"], "segment_area_m2": e["segment"],
			"full_circle": full_circle,
		},
		"steps": [
			_step("1. 计算圆心角", "Δ = (α₂ − α₁) mod 360°（顺时针）；相等视为全圆 360°",
				"α₁ = %s°，α₂ = %s°，方向 = %s" % [_f(a1, 4), _f(a2, 4), dir_txt],
				"Δ = %s°（%s）" % [_f(delta, 6), "全圆" if full_circle else "部分弧"]),
			_step("2. 弧长与弦长", "L = R·Δrad；C = 2R·sin(Δ/2)",
				"L = %s×%s rad；C = 2×%s·sin(%s/2)" % [_f(rad), _f(delta * PI / 180.0, 9), _f(rad), _f(delta, 6)],
				"L = %s m，C = %s m" % [_f(e["arc"]), _f(e["chord"])]),
			_step("3. 弓高", "f = R·(1 − cos(Δ/2))",
				"f = %s·(1 − cos(%s/2))" % [_f(rad), _f(delta, 6)],
				"f = %s m" % _f(e["sagitta"])),
			_step("4. 扇形与弓形面积", "扇形 = R²·Δrad/2；弓形 = R²·(Δrad − sin Δrad)/2",
				"Δrad = %s" % _f(delta * PI / 180.0, 9),
				"扇形 = %s m²，弓形 = %s m²" % [_f(e["sector"]), _f(e["segment"])]),
		],
		"formula": "圆弧要素：L = R·Δrad，C = 2R·sin(Δ/2)，f = R(1−cos(Δ/2))，"
			+ "扇形 = R²Δrad/2，弓形 = R²(Δrad−sin Δrad)/2。Δ>180° 时弓形为优弧弓形。",
		"error": "",
	}

## B9 圆弧要素反算（三点式：弧过 P₁→P₂→P₃，方向由 P₂ 所在侧确定）。
## 输入：{x1_m, y1_m, x2_m, y2_m, x3_m, y3_m}。
static func arc_by_points(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x1 := _num(p, "x1_m", "起点 P₁ x", bad)
	var y1 := _num(p, "y1_m", "起点 P₁ y", bad)
	var x2 := _num(p, "x2_m", "弧上点 P₂ x", bad)
	var y2 := _num(p, "y2_m", "弧上点 P₂ y", bad)
	var x3 := _num(p, "x3_m", "终点 P₃ x", bad)
	var y3 := _num(p, "y3_m", "终点 P₃ y", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var c := circumcircle(x1, y1, x2, y2, x3, y3)
	if c.is_empty():
		return _fail("三点共线或存在重合点，不能确定唯一的圆")
	var cx: float = c["cx"]
	var cy: float = c["cy"]
	var rad: float = c["r"]
	var az1 := GKAngles.azimuth(x1 - cx, y1 - cy)
	var az2m := GKAngles.azimuth(x2 - cx, y2 - cy)
	var az3 := GKAngles.azimuth(x3 - cx, y3 - cy)
	# 方向判定：顺时针弧 P₁→P₃ 的展开角内若包含 P₂，则方向为顺时针
	var cw_end := GKAngles.normalize_deg(az3 - az1)
	var cw_mid := GKAngles.normalize_deg(az2m - az1)
	var is_cw := cw_mid <= cw_end
	var delta := cw_end
	var dir_txt := "顺时针"
	if not is_cw:
		delta = GKAngles.normalize_deg(-cw_end)
		dir_txt = "逆时针"
	if absf(delta) < 1e-9:
		delta = 360.0
	var e := arc_elements(rad, delta)
	return {
		"ok": true,
		"value": {
			"cx_m": cx, "cy_m": cy, "r_m": rad,
			"az1_deg": az1, "az3_deg": az3, "dir": dir_txt,
			"delta_deg": delta, "delta_dms": GKAngles.deg_to_dms_str(delta),
			"arc_m": e["arc"], "chord_m": e["chord"],
			"sagitta_m": e["sagitta"],
			"sector_area_m2": e["sector"], "segment_area_m2": e["segment"],
		},
		"steps": [
			_step("1. 三点定圆", "圆心与半径由两弦垂直平分线联立解出（同 B9 三点定圆）",
				"三点 (%s, %s)、(%s, %s)、(%s, %s)" % [_f(x1), _f(y1), _f(x2), _f(y2), _f(x3), _f(y3)],
				"圆心 (%s, %s)，R = %s m" % [_f(cx), _f(cy), _f(rad)]),
			_step("2. 起终方位与方向判定", "α₁ = α(圆心→P₁)，α₃ = α(圆心→P₃)；P₂ 落在顺时针展开弧内 → 顺时针",
				"α₁ = %s°，α₂(弧上) = %s°，α₃ = %s°" % [_f(az1, 6), _f(az2m, 6), _f(az3, 6)],
				"方向 = %s，圆心角 Δ = %s°" % [dir_txt, _f(delta, 6)]),
			_step("3. 弧长与弦长", "L = R·Δrad；C = 2R·sin(Δ/2)",
				"L = %s×%s rad；C = 2×%s·sin(%s/2)" % [_f(rad), _f(delta * PI / 180.0, 9), _f(rad), _f(delta, 6)],
				"L = %s m，C = %s m" % [_f(e["arc"]), _f(e["chord"])]),
			_step("4. 弓高与面积", "f = R(1−cos(Δ/2))；扇形 = R²Δrad/2；弓形 = R²(Δrad−sin Δrad)/2",
				"Δrad = %s" % _f(delta * PI / 180.0, 9),
				"f = %s m，扇形 = %s m²，弓形 = %s m²" % [_f(e["sagitta"]), _f(e["sector"]), _f(e["segment"])]),
		],
		"formula": "三点弧反算：先三点定圆，再由圆心到三点方位角判定弧方向（P₂ 在顺时针展开弧内则为顺时针），"
			+ "要素公式同圆弧反算。",
		"error": "",
	}

## 圆弧要素原语：R、圆心角 Δ（度，(0, 360]）→ 要素字典
static func arc_elements(r_m: float, delta_deg: float) -> Dictionary:
	var th := delta_deg * PI / 180.0
	return {
		"arc": r_m * th,
		"chord": 2.0 * r_m * sin(th / 2.0),
		"sagitta": r_m * (1.0 - cos(th / 2.0)),
		"sector": r_m * r_m * th / 2.0,
		"segment": r_m * r_m * (th - sin(th)) / 2.0,
	}

static func inv_len(x1: float, y1: float, x2: float, y2: float) -> float:
	var dx := x2 - x1
	var dy := y2 - y1
	return sqrt(dx * dx + dy * dy)

static func _det_val(x1: float, y1: float, x2: float, y2: float, x3: float, y3: float) -> float:
	return 2.0 * (x2 - x1) * (2.0 * (y3 - y1)) - 2.0 * (x3 - x1) * (2.0 * (y2 - y1))

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
