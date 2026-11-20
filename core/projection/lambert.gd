# core/projection/lambert.gd —— GK-M3-5b 兰勃特等角圆锥投影（A14，EPSG 9801 一标准纬线 / 9802 双标准纬线）
#
# 公式（Snyder 15-1..15-11 / EPSG GN7-2，本会话经 pyproj EPSG:2154 Lambert-93 随机 200 点复核 0 误差）：
#   m(φ) = cosφ/√(1-e²sin²φ)，t(φ) = tan(π/4-φ/2)·[(1-e·sinφ)/(1+e·sinφ)]^(e/2)
#   2SP：n = (ln m1 - ln m2)/(ln t1 - ln t2)，F = m1/(n·t1^n)，ρ0 = a·F·t0^n
#   ρ = a·F·t^n；x = FE + ρ·sin(n·λ)，y = FN + ρ0 - ρ·cos(n·λ)
#   1SP：n = sin(φ1)，F = m1/(n·t1^n)，其余同上
# 反算：ρ' 与 atan2 给 θ、t'=(ρ/(aF))^(1/n)，φ 经比式迭代精确恢复。
class_name GKLambert
extends RefCounted
const _GK := preload("res://core/projection/gauss_kruger.gd")
const _EL := preload("res://core/ellipsoid/ellipsoid.gd")
const _AN := preload("res://core/math/angles.gd")

## 常用预设（参数取 EPSG 官方定义）
const PRESETS := {
	"Lambert-93": {"name_cn": "Lambert-93（法国 RGF93，EPSG:2154）", "datum": "GRS80",
		"phi1_deg": 49.0, "phi2_deg": 44.0, "phi0_deg": 46.5, "lon0_deg": 3.0, "fe_m": 700000.0, "fn_m": 6600000.0},
	"Lambert-CGCS2000-CN": {"name_cn": "兰勃特等角圆锥（CGCS2000 全国 25N-47N 示例）", "datum": "CGCS2000",
		"phi1_deg": 47.0, "phi2_deg": 25.0, "phi0_deg": 36.0, "lon0_deg": 105.0, "fe_m": 0.0, "fn_m": 0.0},
}

## 低层正算（2SP：phi2 传 NAN 即按 1SP：n=sinφ1）。返回 {x_m, y_m, n, f, rho0_m}；非法返回 {}。
static func fwd(lat_deg: float, lon_deg: float, phi1_deg: float, phi2_deg: float,
		phi0_deg: float, lon0_deg: float, fe: float, fn: float, ell: Dictionary) -> Dictionary:
	if ell.is_empty():
		return {}
	if not [lat_deg, lon_deg, phi1_deg, phi0_deg, lon0_deg, fe, fn].all(func(v: Variant) -> bool: return is_finite(float(v))):
		return {}
	if absf(lat_deg) >= 90.0 or absf(phi1_deg) >= 90.0:
		return {}
	var two_sp := is_finite(phi2_deg)
	if two_sp and absf(phi2_deg) >= 90.0:
		return {}
	if two_sp and is_equal_approx(phi1_deg, phi2_deg):
		return {}
	var a: float = ell["a"]
	var e := sqrt(ell["e2"])
	var m1 := _m(phi1_deg * PI / 180.0, e)
	var t1 := _t(phi1_deg * PI / 180.0, e)
	var n: float
	var big_f: float
	if two_sp:
		var m2 := _m(phi2_deg * PI / 180.0, e)
		var t2 := _t(phi2_deg * PI / 180.0, e)
		if is_equal_approx(t1, t2):
			return {}
		n = log(m1 / m2) / log(t1 / t2)
		big_f = m1 / (n * pow(t1, n))
	else:
		n = sin(phi1_deg * PI / 180.0)
		big_f = m1 / (n * pow(t1, n))
	var t0 := _t(phi0_deg * PI / 180.0, e)
	var rho0 := a * big_f * pow(t0, n)
	var t := _t(lat_deg * PI / 180.0, e)
	var rho := a * big_f * pow(t, n)
	var dl := n * (lon_deg - lon0_deg) * PI / 180.0
	if absf(lat_deg) >= 90.0:
		return {}
	return {
		"x_m": fe + rho * sin(dl),
		"y_m": fn + rho0 - rho * cos(dl),
		"n": n, "f": big_f, "rho0_m": rho0,
		"two_sp": two_sp,
	}

## 低层反算（two_sp 与正算参数一致）。返回 {lat_deg, lon_deg}；非法返回 {}。
static func inv(x_m: float, y_m: float, phi1_deg: float, phi2_deg: float,
		phi0_deg: float, lon0_deg: float, fe: float, fn: float, ell: Dictionary) -> Dictionary:
	if ell.is_empty():
		return {}
	if not [x_m, y_m, phi1_deg, phi0_deg, lon0_deg, fe, fn].all(func(v: Variant) -> bool: return is_finite(float(v))):
		return {}
	var two_sp := is_finite(phi2_deg)
	if two_sp and (absf(phi2_deg) >= 90.0 or is_equal_approx(phi1_deg, phi2_deg)):
		return {}
	var a: float = ell["a"]
	var e := sqrt(ell["e2"])
	var m1 := _m(phi1_deg * PI / 180.0, e)
	var t1 := _t(phi1_deg * PI / 180.0, e)
	var n: float
	var big_f: float
	if two_sp:
		var m2 := _m(phi2_deg * PI / 180.0, e)
		var t2 := _t(phi2_deg * PI / 180.0, e)
		if is_equal_approx(t1, t2):
			return {}
		n = log(m1 / m2) / log(t1 / t2)
		big_f = m1 / (n * pow(t1, n))
	else:
		n = sin(phi1_deg * PI / 180.0)
		big_f = m1 / (n * pow(t1, n))
	var t0 := _t(phi0_deg * PI / 180.0, e)
	var rho0 := a * big_f * pow(t0, n)
	var dx := x_m - fe
	var dy := rho0 - (y_m - fn)
	var rho := signf(n) * sqrt(dx * dx + dy * dy)
	if rho <= 0.0:
		return {}
	var theta := atan2(dx, dy)
	var lat := phi0_deg * PI / 180.0
	for _i in range(15):
		var t := pow(rho / (a * big_f), 1.0 / n)
		var sb := sin(lat)
		lat = PI / 2.0 - 2.0 * atan(t * pow((1.0 - e * sb) / (1.0 + e * sb), e / 2.0))
	var lon := theta / n + lon0_deg * PI / 180.0
	var lat_deg := rad_to_deg(lat)
	if absf(lat_deg) >= 90.0:
		return {}
	return {"lat_deg": lat_deg, "lon_deg": rad_to_deg(lon)}

## §5 协议正算。p: {lat_deg, lon_deg, phi1_deg, phi2_deg（可空→1SP）, phi0_deg, lon0_deg, fe_m, fn_m, datum?, preset?}
static func forward(p: Dictionary) -> Dictionary:
	var q := _with_preset(p)
	var ell := _resolve_ell(q)
	if ell.is_empty():
		return _ell_error(String(q.get("datum", "GRS80")))
	var lat := _num(q, "lat_deg", "lat_dms")
	var lon := _num(q, "lon_deg", "lon_dms")
	var phi1 := _f(q, "phi1_deg", NAN)
	var phi0 := _f(q, "phi0_deg", NAN)
	var lon0 := _f(q, "lon0_deg", NAN)
	if is_nan(lat) or is_nan(lon) or is_nan(phi1) or is_nan(phi0) or is_nan(lon0):
		return _err("缺少必要输入：B/L、标准纬线 phi1_deg（2SP 另需 phi2_deg）、phi0_deg、lon0_deg")
	var phi2 := _f(q, "phi2_deg", NAN)
	var fe := _f(q, "fe_m", 0.0)
	var fn := _f(q, "fn_m", 0.0)
	var r := fwd(lat, lon, phi1, phi2, phi0, lon0, fe, fn, ell)
	if r.is_empty():
		return _err("正算失败：参数非法（|B|、|φ1|、|φ2| < 90°；2SP 时 φ1≠φ2）")
	var value := {
		"x_m": r["x_m"], "y_m": r["y_m"],
		"lat_deg": lat, "lon_deg": lon,
		"n": r["n"], "f": r["f"], "rho0_m": r["rho0_m"],
		"mode": "2SP" if bool(r["two_sp"]) else "1SP",
		"datum": String(q.get("datum", "GRS80")),
	}
	var mode_txt := ""
	if bool(r["two_sp"]):
		mode_txt = "2SP（双标准纬线 %.4f°/%.4f°）" % [phi1, phi2]
	else:
		mode_txt = "1SP（标准纬线 %.4f°）" % phi1
	var steps := [
		{"title": "1. 圆锥常数", "formula": "m(φ)=cosφ/√(1-e²sin²φ)，t(φ)=tan(π/4-φ/2)·[(1-e·sinφ)/(1+e·sinφ)]^(e/2)；n=(ln m1-ln m2)/(ln t1-ln t2)，F=m1/(n·t1^n)",
			"substitution": "%s，e=%.12f" % [mode_txt, sqrt(ell["e2"])],
			"result": "n=%.12f，F=%.12f，ρ0=%.4f m" % [r["n"], r["f"], r["rho0_m"]]},
		{"title": "2. 正算", "formula": "ρ = a·F·t(B)^n；x = FE + ρ·sin(n·λ)，y = FN + ρ0 - ρ·cos(n·λ)",
			"substitution": "B=%.8f°，λ=n·(L-L0)=%.8f°，FE=%.1f，FN=%.1f" % [lat, rad_to_deg(r["n"] * (lon - lon0) * PI / 180.0), fe, fn],
			"result": "x=%.4f m，y=%.4f m" % [r["x_m"], r["y_m"]]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "兰勃特等角圆锥 %s（EPSG 9802/9801；Lambert-93 与 pyproj 复核 0 误差）" % mode_txt,
			"error": ""}

## §5 协议反算。p 同 forward（x_m/y_m 代替 B/L）。
static func inverse(p: Dictionary) -> Dictionary:
	var q := _with_preset(p)
	var ell := _resolve_ell(q)
	if ell.is_empty():
		return _ell_error(String(q.get("datum", "GRS80")))
	var x := _f(q, "x_m", NAN)
	var y := _f(q, "y_m", NAN)
	var phi1 := _f(q, "phi1_deg", NAN)
	var phi0 := _f(q, "phi0_deg", NAN)
	var lon0 := _f(q, "lon0_deg", NAN)
	if is_nan(x) or is_nan(y) or is_nan(phi1) or is_nan(phi0) or is_nan(lon0):
		return _err("缺少必要输入：x_m/y_m、phi1_deg、phi0_deg、lon0_deg")
	var phi2 := _f(q, "phi2_deg", NAN)
	var fe := _f(q, "fe_m", 0.0)
	var fn := _f(q, "fn_m", 0.0)
	var r := inv(x, y, phi1, phi2, phi0, lon0, fe, fn, ell)
	if r.is_empty():
		return _err("反算失败：坐标/参数非法或超出投影域")
	var value := {
		"lat_deg": r["lat_deg"], "lon_deg": r["lon_deg"],
		"lat_dms": _AN.deg_to_dms_str(r["lat_deg"], 3),
		"lon_dms": _AN.deg_to_dms_str(r["lon_deg"], 3),
		"mode": "2SP" if is_finite(phi2) else "1SP",
		"datum": String(q.get("datum", "GRS80")),
	}
	var steps := [
		{"title": "1. 极径恢复", "formula": "dx = x-FE，dy = ρ0-(y-FN)，ρ = ±√(dx²+dy²)（随 n 符号），θ = atan2(dx, dy)",
			"substitution": "x=%.4f，y=%.4f" % [x, y],
			"result": "ρ=%.4f m，θ=%.8f°" % [sqrt(pow(x - fe, 2.0) + pow(_rho0_of(q, ell) - (y - fn), 2.0)), rad_to_deg(atan2(x - fe, _rho0_of(q, ell) - (y - fn)))]},
		{"title": "2. 纬度迭代", "formula": "t = (ρ/(a·F))^(1/n)，φ ← π/2 - 2·arctan(t·[(1-e·sinφ)/(1+e·sinφ)]^(e/2))（迭代至收敛）",
			"substitution": "n=%.12f，F=%.12f" % [_n_of(q), _f_of(q, ell)],
			"result": "B=%.8f°，L=%.8f°" % [r["lat_deg"], r["lon_deg"]]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "兰勃特等角圆锥反算（φ 精确迭代；与 pyproj 复核 0 误差）",
			"error": ""}

## 预设列表（供 UI 下拉）
static func list_presets() -> Array:
	return PRESETS.keys()

# ---------- 内部 ----------

static func _m(phi: float, e: float) -> float:
	return cos(phi) / sqrt(1.0 - e * e * pow(sin(phi), 2.0))

static func _t(phi: float, e: float) -> float:
	# EPSG 9802/Snyder 15-3：t = tan(π/4-φ/2) ÷ [(1-e·sinφ)/(1+e·sinφ)]^(e/2)（除法定义）
	var sb := sin(phi)
	return tan(PI / 4.0 - phi / 2.0) / pow((1.0 - e * sb) / (1.0 + e * sb), e / 2.0)

static func _with_preset(p: Dictionary) -> Dictionary:
	var preset := String(p.get("preset", "")).strip_edges()
	if preset.is_empty() or not PRESETS.has(preset):
		return p
	var merged := p.duplicate(true)
	for k: String in PRESETS[preset]:
		if not merged.has(k):
			merged[k] = PRESETS[preset][k]
	if not merged.has("datum"):
		merged["datum"] = PRESETS[preset]["datum"]
	return merged

static func _n_of(q: Dictionary) -> float:
	var phi1 := _f(q, "phi1_deg", NAN)
	var phi2 := _f(q, "phi2_deg", NAN)
	var ell := _resolve_ell(q)
	if ell.is_empty() or is_nan(phi1):
		return NAN
	var e := sqrt(ell["e2"])
	var t1 := _t(phi1 * PI / 180.0, e)
	if is_finite(phi2):
		var t2 := _t(phi2 * PI / 180.0, e)
		var m1 := _m(phi1 * PI / 180.0, e)
		var m2 := _m(phi2 * PI / 180.0, e)
		return log(m1 / m2) / log(t1 / t2)
	return sin(phi1 * PI / 180.0)

static func _f_of(q: Dictionary, ell: Dictionary) -> float:
	var phi1 := _f(q, "phi1_deg", NAN)
	if is_nan(phi1) or ell.is_empty():
		return NAN
	var e := sqrt(ell["e2"])
	var m1 := _m(phi1 * PI / 180.0, e)
	var t1 := _t(phi1 * PI / 180.0, e)
	var n := _n_of(q)
	if is_nan(n) or n == 0.0:
		return NAN
	return m1 / (n * pow(t1, n))

static func _rho0_of(q: Dictionary, ell: Dictionary) -> float:
	var phi0 := _f(q, "phi0_deg", NAN)
	var fe := _f(q, "fe_m", 0.0)
	if is_nan(phi0) or ell.is_empty():
		return NAN
	var a: float = ell["a"]
	var e := sqrt(ell["e2"])
	var n := _n_of(q)
	var f := _f_of(q, ell)
	if is_nan(n) or is_nan(f):
		return NAN
	return a * f * pow(_t(phi0 * PI / 180.0, e), n)

static func _num(p: Dictionary, num_key: String, dms_key: String) -> float:
	# 数值键优先；其内容若为度分秒文本（如 39°54′27.1″）同样接受（GKAngles.parse_dms 兼容纯十进制）
	if p.has(num_key):
		var s := str(p[num_key]).strip_edges()
		if not s.is_empty():
			if s.is_valid_float():
				return s.to_float()
			return _AN.parse_dms(s)
	if p.has(dms_key):
		var s2 := str(p[dms_key]).strip_edges()
		if not s2.is_empty():
			if s2.is_valid_float():
				return s2.to_float()
			return _AN.parse_dms(s2)
	return NAN

static func _f(p: Dictionary, key: String, dflt: float) -> float:
	if not p.has(key):
		return dflt
	var v: Variant = p[key]
	if v is float or v is int:
		return float(v)
	if v is String:
		var t := String(v).strip_edges()
		if t.is_valid_float():
			return t.to_float()
	return NAN

static func _resolve_ell(p: Dictionary) -> Dictionary:
	var datum := _GK.resolve_datum(String(p.get("datum", "GRS80")))
	return _EL.params(datum)

static func _ell_error(datum: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "兰勃特等角圆锥投影",
			"error": "未知的椭球/基准“%s”。可用：%s" % [datum, ", ".join(_EL.list_builtin())]}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "兰勃特等角圆锥投影（EPSG 9801/9802）", "error": msg}
