# core/projection/mercator.gd —— GK-M3-5a Web 墨卡托（EPSG:3857，球面公式作用于 WGS84 经纬度）
#
# 定义：a=6378137，x=a·rad(L)，y=a·ln[tan(π/4+rad(B)/2)]，FE=FN=0。
# 边界自洽：B_max=±85.05112878°；反算阈值 y_max=y(B_max)（≠a·π，直接用 a·π 会拒绝正算边界点）；
# |B|>B_max 与 |y|>y_max 一律拒绝，B=B_max 可被反算还原。
# pyproj EPSG:3857 复核：天安门 (39.9075276,116.3912757)→(12956617.544,4852513.528)。
# 球面近似非等角严格椭球墨卡托（EPSG:9804），半字长精度口径不适用。
class_name GKMercator
extends RefCounted
const _AN := preload("res://core/math/angles.gd")

const A := 6378137.0
## 正算纬度边界（度）：|B| ≤ B_max 可算，|B| > B_max 拒绝
const MAX_LAT := 85.05112878
## 反算 y 拒绝阈值（米）：y_max = y(MAX_LAT)（同一正算公式自洽计算），约 20037508.343039
const MAX_Y_M := 20037508.343039

## 球面墨卡托低层正算（任意半径/基准经纬度）。返回 {x_m, y_m}；非法返回 {}。
static func fwd(lat_deg: float, lon_deg: float, radius: float = A) -> Dictionary:
	if not is_finite(lat_deg) or not is_finite(lon_deg) or radius <= 0.0:
		return {}
	if absf(lat_deg) > MAX_LAT:
		return {}
	var phi := lat_deg * PI / 180.0
	var lam := lon_deg * PI / 180.0
	return {"x_m": radius * lam, "y_m": radius * log(tan(PI / 4.0 + phi / 2.0))}

## 球面墨卡托低层反算。返回 {lat_deg, lon_deg}；非法返回 {}。
static func inv(x_m: float, y_m: float, radius: float = A) -> Dictionary:
	if not is_finite(x_m) or not is_finite(y_m) or radius <= 0.0:
		return {}
	var lam := x_m / radius
	if absf(lam) > PI:
		return {}
	# 反算拒绝阈值与正算边界同一公式自洽：|y| > y(MAX_LAT) = MAX_Y_M 拒绝
	var y_max := radius * log(tan(PI / 4.0 + MAX_LAT * PI / 360.0))
	if absf(y_m) > y_max:
		return {}
	var phi := 2.0 * atan(exp(y_m / radius)) - PI / 2.0
	var lat := rad_to_deg(phi)
	if absf(lat) > MAX_LAT:
		return {}
	return {"lat_deg": lat, "lon_deg": rad_to_deg(lam)}

## §5 协议正算。p: {lat_deg/lat_dms, lon_deg/lon_dms}
static func forward(p: Dictionary) -> Dictionary:
	var lat := _num(p, "lat_deg", "lat_dms")
	var lon := _num(p, "lon_deg", "lon_dms")
	if is_nan(lat) or is_nan(lon):
		return _err("纬度/经度不是有效数字（可接受十进制度或度分秒文本）")
	var r := fwd(lat, lon, A)
	if r.is_empty():
		return _err("纬度 %s 超出 Web 墨卡托适用域（|B| ≤ %.8f°）" % [String.num(lat, 4), MAX_LAT])
	var value := {
		"x_m": r["x_m"], "y_m": r["y_m"],
		"lat_deg": lat, "lon_deg": lon,
		"epsg": 3857,
	}
	var phi := lat * PI / 180.0
	var steps := [
		{"title": "1. Web 墨卡托正算（EPSG:3857）", "formula": "x = a·rad(L)，y = a·ln[tan(π/4 + rad(B)/2)]，a = 6378137 m",
			"substitution": "B=%s°，L=%s°" % [String.num(lat, 8), String.num(lon, 8)],
			"result": "x=%.4f m，y=%.4f m" % [r["x_m"], r["y_m"]]},
		{"title": "2. 适用域说明", "formula": "球面近似；|B| ≤ %.8f°，对应 |y| ≤ %.6f m（正反算同一公式自洽）",
			"substitution": "tan(π/4+B/2)=%.12f" % tan(PI / 4.0 + phi / 2.0),
			"result": "y/a = ln(...) = %.12f；边界 y_max = y(B_max)=%.6f m" % [r["y_m"] / A, MAX_Y_M]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "Web 墨卡托 EPSG:3857（球面公式；高纬变形大，非严格椭球等角投影）",
			"error": ""}

## §5 协议反算。p: {x_m, y_m}
static func inverse(p: Dictionary) -> Dictionary:
	var x := _f(p, "x_m", NAN)
	var y := _f(p, "y_m", NAN)
	if is_nan(x) or is_nan(y):
		return _err("x_m/y_m 不是有效数字")
	var r := inv(x, y, A)
	if r.is_empty():
		return _err("反算失败：坐标超出 Web 墨卡托域（|x| ≤ %d m，|y| < %.6f m，对应 |B| < %.9f°）" % [int(A * PI), MAX_Y_M, MAX_LAT])
	var value := {
		"lat_deg": r["lat_deg"], "lon_deg": r["lon_deg"],
		"lat_dms": _AN.deg_to_dms_str(r["lat_deg"], 3),
		"lon_dms": _AN.deg_to_dms_str(r["lon_deg"], 3),
		"epsg": 3857,
	}
	var steps := [
		{"title": "1. Web 墨卡托反算", "formula": "L = rad(x/a)，B = 2·arctan(e^(y/a)) - π/2",
			"substitution": "x=%.4f m，y=%.4f m" % [x, y],
			"result": "B=%.8f°，L=%.8f°" % [r["lat_deg"], r["lon_deg"]]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "Web 墨卡托 EPSG:3857 反算（边界口径与正算同一公式自洽：|y| < %.6f m）" % MAX_Y_M,
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

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "Web 墨卡托 EPSG:3857", "error": msg}
