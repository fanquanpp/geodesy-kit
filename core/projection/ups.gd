# core/projection/ups.gd —— GK-M3-4 极方位等角投影 UPS（Universal Polar Stereographic，DMA TM 8358.2 §10）
#
# 定义：k0=0.994（极点比例因子），FE=FN=2,000,000，WGS84；北纬域 B≥84°，南纬域 B<-80°。
# 公式（Snyder 极方位等角 / DMA UPS，本会话经 pyproj EPSG:5041/5042 精确复核）：
#   S = √((1+e)^(1+e)·(1-e)^(1-e))
#   北：t = tan(π/4-B/2)·[(1-e·sinB)/(1+e·sinB)]^(-e/2) → 注意化简后的幂次，
#       ρ = 2·k0·a·t/S，E = FE + ρ·sinλ，N = FN - ρ·cosλ
#   南：t = tan(π/4+B/2)·[(1-e·sinB)/(1+e·sinB)]^(e/2)，
#       E = FE + ρ·sinλ，N = FN + ρ·cosλ
# 向量：北 (85,30)→(2277728.6957,1518959.7883)；南 (-85,30)→(2277728.6957,2481040.2117)。
class_name GKUps
extends RefCounted
const _GK := preload("res://core/projection/gauss_kruger.gd")
const _EL := preload("res://core/ellipsoid/ellipsoid.gd")
const _AN := preload("res://core/math/angles.gd")

const K0 := 0.994
const FE := 2000000.0
const FN := 2000000.0
const LAT_N_MIN := 84.0   # 北极区下界
const LAT_S_MAX := -80.0  # 南极区上界

## S 常数：√((1+e)^(1+e)·(1-e)^(1-e))
static func big_s(e: float) -> float:
	return sqrt(pow(1.0 + e, 1.0 + e) * pow(1.0 - e, 1.0 - e))

## 判定半球：north = B ≥ 84°，south = B < -80°；其余返回 ""（不在 UPS 域）
static func hemisphere_of(lat_deg: float) -> String:
	if lat_deg >= LAT_N_MIN and lat_deg <= 90.0:
		return "N"
	if lat_deg < LAT_S_MAX and lat_deg >= -90.0:
		return "S"
	return ""

## 低层正算。返回 {e_m, n_m, rho_m, hemi}；非法返回 {}。
static func fwd(lat_deg: float, lon_deg: float, ell: Dictionary, north: bool) -> Dictionary:
	if ell.is_empty() or not is_finite(lat_deg) or not is_finite(lon_deg):
		return {}
	if north and (lat_deg < LAT_N_MIN or lat_deg > 90.0):
		return {}
	if not north and (lat_deg >= LAT_S_MAX or lat_deg < -90.0):
		return {}
	var a: float = ell["a"]
	var e := sqrt(ell["e2"])
	var s_const := big_s(e)
	var phi := lat_deg * PI / 180.0
	var lam := lon_deg * PI / 180.0
	var sb := sin(phi)
	var base := pow((1.0 - e * sb) / (1.0 + e * sb), e / 2.0)
	var t: float
	if north:
		t = tan(PI / 4.0 - phi / 2.0) / base
	else:
		t = tan(PI / 4.0 + phi / 2.0) * base
	var rho := 2.0 * K0 * a * t / s_const
	var e_m := FE + rho * sin(lam)
	var n_m: float
	if north:
		n_m = FN - rho * cos(lam)
	else:
		n_m = FN + rho * cos(lam)
	return {"e_m": e_m, "n_m": n_m, "rho_m": rho, "hemi": "N" if north else "S"}

## 低层反算。返回 {lat_deg, lon_deg}；非法返回 {}。
static func inv(e_m: float, n_m: float, ell: Dictionary, north: bool) -> Dictionary:
	if ell.is_empty() or not is_finite(e_m) or not is_finite(n_m):
		return {}
	var a: float = ell["a"]
	var e := sqrt(ell["e2"])
	var s_const := big_s(e)
	var dx := e_m - FE
	var dy := n_m - FN
	var rho := sqrt(dx * dx + dy * dy)
	if rho < 1e-12:
		# 极点：经度不定，约定 λ=0
		return {"lat_deg": 90.0 if north else -90.0, "lon_deg": 0.0}
	# 北：E-FE = ρ·sinλ 且 FN-N = ρ·cosλ → λ=atan2(dx, FN-N)；南：N-FN = ρ·cosλ → λ=atan2(dx, dy)
	var lam: float
	if north:
		lam = atan2(dx, -dy)
	else:
		lam = atan2(dx, dy)
	# t 与 ρ 反解
	var t := rho * s_const / (2.0 * K0 * a)
	var chi := NAN  # 球面极方位纬度
	if north:
		# t = tan(π/4-φ/2)/base → tan(π/4-φ/2) = t·base
		chi = PI / 2.0 - 2.0 * atan(t)  # 先按球面（base 依 φ）迭代
		var phi := chi
		for _i in range(12):
			var sb := sin(phi)
			var base := pow((1.0 - e * sb) / (1.0 + e * sb), e / 2.0)
			phi = PI / 2.0 - 2.0 * atan(t * base)
		var lam_ret := lam
		return {"lat_deg": rad_to_deg(phi), "lon_deg": rad_to_deg(lam_ret)}
	else:
		# t = tan(π/4+φ/2)·base
		var phi := 2.0 * atan(t) - PI / 2.0
		for _i in range(12):
			var sb := sin(phi)
			var base := pow((1.0 - e * sb) / (1.0 + e * sb), e / 2.0)
			phi = 2.0 * atan(t / base) - PI / 2.0
		return {"lat_deg": rad_to_deg(phi), "lon_deg": rad_to_deg(lam)}

## §5 协议正算。p: {lat_deg/lat_dms, lon_deg/lon_dms, hemisphere? ("N"/"S" 缺省自动), datum?}
static func forward(p: Dictionary) -> Dictionary:
	var lat := _num(p, "lat_deg", "lat_dms")
	var lon := _num(p, "lon_deg", "lon_dms")
	if is_nan(lat) or is_nan(lon):
		return _err("纬度/经度不是有效数字（可接受十进制度或度分秒文本）")
	var ell := _resolve_ell(p)
	if ell.is_empty():
		return _ell_error(String(p.get("datum", "WGS84")))
	var north := true
	var auto := true
	var h := String(p.get("hemisphere", "")).strip_edges().to_lower()
	if h != "":
		auto = false
		if h == "n" or h == "北" or h == "north":
			north = true
		elif h == "s" or h == "南" or h == "south":
			north = false
		else:
			return _err("半球应填 N/S（或 北/南），留空则按纬度自动判定")
	else:
		var hh := hemisphere_of(lat)
		if hh == "":
			return _err("纬度 %s 不在 UPS 域（北纬 B≥84° 或南纬 B<-80°）" % String.num(lat, 4))
		north = hh == "N"
	var r := fwd(lat, lon, ell, north)
	if r.is_empty():
		return _err("正算失败：纬度 %s 不在 %s 半球 UPS 域" % [String.num(lat, 4), "北（B≥84°）" if north else "南（B<-80°）"])
	var value := {
		"e_m": r["e_m"], "n_m": r["n_m"],
		"hemisphere": r["hemi"], "rho_m": r["rho_m"],
		"datum": String(p.get("datum", "WGS84")),
		"k0": K0,
	}
	var steps := [
		{"title": "1. 常数", "formula": "S = √((1+e)^(1+e)·(1-e)^(1-e))，k0=0.994，FE=FN=2,000km",
			"substitution": "e=%.12f" % sqrt(ell["e2"]),
			"result": "S=%.12f" % big_s(sqrt(ell["e2"]))},
		{"title": "2. 极方位等角正算", "formula": "ρ = 2·k0·a·t/S；E = FE + ρ·sinλ；N = FN - ρ·cosλ（北） / N = FN + ρ·cosλ（南）",
			"substitution": "B=%s°，λ=%s°，半球=%s" % [String.num(lat, 6), String.num(lon, 6), "北" if north else "南"],
			"result": "ρ=%.4f m；E=%.4f m，N=%.4f m" % [r["rho_m"], r["e_m"], r["n_m"]]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "UPS 正算（极方位等角，k0=0.994，FE/FN=2,000km；DMA TM 8358.2 §10；pyproj EPSG:5041/5042 精确复核）",
			"error": ""}

## §5 协议反算。p: {e_m, n_m, hemisphere?, datum?}
static func inverse(p: Dictionary) -> Dictionary:
	var e := _f(p, "e_m", NAN)
	var n := _f(p, "n_m", NAN)
	if is_nan(e) or is_nan(n):
		return _err("E/N 不是有效数字")
	var ell := _resolve_ell(p)
	if ell.is_empty():
		return _ell_error(String(p.get("datum", "WGS84")))
	var north := true
	var h := String(p.get("hemisphere", "")).strip_edges().to_lower()
	if h == "":
		# UPS 网格 (E,N) 在南北半球重叠，无法仅凭坐标判定半球；
		# 缺省按北半球处理（文档约定），南半球请显式传 hemisphere="S"
		north = true
	elif h == "n" or h == "北" or h == "north":
		north = true
	elif h == "s" or h == "南" or h == "south":
		north = false
	else:
		return _err("半球应填 N/S（或 北/南），留空则自动判定")
	var r := inv(e, n, ell, north)
	if r.is_empty():
		return _err("反算失败：参数非法")
	var lat: float = r["lat_deg"]
	if (north and lat < LAT_N_MIN) or (not north and lat >= LAT_S_MAX):
		return _err("反算结果 B=%s 不在 %s 半球 UPS 域（请确认半球）" % [String.num(lat, 4), "北（B≥84°）" if north else "南（B<-80°）"])
	var value := {
		"lat_deg": lat, "lon_deg": r["lon_deg"],
		"lat_dms": _AN.deg_to_dms_str(lat, 3),
		"lon_dms": _AN.deg_to_dms_str(r["lon_deg"], 3),
		"hemisphere": "N" if north else "S",
		"datum": String(p.get("datum", "WGS84")),
	}
	var steps := [
		{"title": "1. 极距与经度", "formula": "ρ = √((E-FE)²+(N-FN)²)，λ = atan2(E-FE, ±(N-FN))",
			"substitution": "E=%.4f，N=%.4f，半球=%s" % [e, n, "北" if north else "南"],
			"result": "ρ=%.4f m，λ=%.8f°" % [sqrt(pow(e - FE, 2.0) + pow(n - FN, 2.0)), r["lon_deg"]]},
		{"title": "2. 纬度迭代", "formula": "t = ρ·S/(2·k0·a)，tan(π/4∓φ/2) 与 e 比式互代迭代",
			"substitution": "k0=%.4f，FE=FN=2,000,000 m" % K0,
			"result": "B=%.8f°" % lat},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "UPS 反算（极方位等角精确迭代；pyproj EPSG:5041/5042 精确复核）",
			"error": ""}

# ---------- 内部 ----------

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
	var datum := _GK.resolve_datum(String(p.get("datum", "WGS84")))
	return _EL.params(datum)

static func _ell_error(datum: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "UPS 投影",
			"error": "未知的椭球/基准「%s」。可用：%s" % [datum, ", ".join(_EL.list_builtin())]}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "UPS 投影（极方位等角 k0=0.994）", "error": msg}
