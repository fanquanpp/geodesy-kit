# core/ellipsoid/blh_xyz.gd —— A6 大地坐标(B,L,h) ↔ 空间直角坐标(X,Y,Z)
#
# 算法（EPSG GN7-2 §4.1.1 同族闭式）：正算 N=a/√(1−e²sin²B)，X=(N+h)cosB·cosL、Y=(N+h)cosB·sinL、
# Z=(N(1−e²)+h)sinB；反算 Bowring ε 闭式（θ 迭代变量，B/h 一次还原）。
# 验收（ARCHITECTURE.md §4 GK-M2）：GN7-2 算例 → (3771793.968, 140253.342, 5124304.349)（pyproj 逐位一致）；
# CGCS2000 天安门 → (−2177748.227, 4388723.160, 4070142.752)（pyproj EPSG:4490 复核）。
# 协议：forward/inverse(p) -> {ok, value, steps, formula, error}；core 禁引擎 API。
class_name GKBlhXYZ
extends RefCounted

const SRC_NOTE := "EPSG Guidance Note 7-2 §4.1.1（正算 9602 闭式 + Bowring 反算）"

## 从参数字典取椭球（a/inv_f 或 datum 名）。失败返回 {}。
## 指定了未知 datum 名返回 {}（不静默回落默认椭球）。
static func _ellipsoid_of(p: Dictionary) -> Dictionary:
	var datum := String(p.get("datum", ""))
	if datum != "":
		var d := GKEllipsoid.params(datum)
		if d.is_empty():
			return {}
		return d
	var a := float(p.get("a", 6378137.0))
	var inv_f := float(p.get("inv_f", 298.257223563))
	if a > 0.0 and inv_f > 0.0:
		return GKEllipsoid.derived(a, inv_f)
	return {}

## 协议数值键取值：GDScript float("x") 会静默得 0.0，非数值字符串须显式归为 NAN
static func _numf(v: Variant, default_v := NAN) -> float:
	if v is String:
		var t := String(v).strip_edges().replace("−", "-")
		if not t.is_valid_float():
			return NAN
		return t.to_float()
	if v == null:
		return default_v
	return float(v)

## 纯数值正算：B/L/h（度）+ 椭球派生量 → {x, y, z}。输入非法返回 {}。
static func blh_to_xyz(lat_deg: float, lon_deg: float, h_m: float, el: Dictionary) -> Dictionary:
	if el.is_empty():
		return {}
	if not (is_finite(lat_deg) and is_finite(lon_deg) and is_finite(h_m)):
		return {}
	if absf(lat_deg) > 90.0:
		return {}
	var a: float = el["a"]
	var e2: float = el["e2"]
	var sl := sin(deg_to_rad(lat_deg))
	var cl := cos(deg_to_rad(lat_deg))
	var n := a / sqrt(1.0 - e2 * sl * sl)
	var l := deg_to_rad(lon_deg)
	return {
		"x": (n + h_m) * cl * cos(l),
		"y": (n + h_m) * cl * sin(l),
		"z": (n * (1.0 - e2) + h_m) * sl,
		"n": n,
	}

## 纯数值反算：X/Y/Z + 椭球派生量 → {lat, lon, h, n}。失败返回 {}。
## 极点特例（p≈0）：B=±90°，h=|Z|−b(1−e²... ) 按 M=a(1−e²) 处理。
static func xyz_to_blh(x: float, y: float, z: float, el: Dictionary) -> Dictionary:
	if el.is_empty():
		return {}
	if not (is_finite(x) and is_finite(y) and is_finite(z)):
		return {}
	var a: float = el["a"]
	var b: float = el["b"]
	var e2: float = el["e2"]
	var ep2: float = el["ep2"]
	var p := sqrt(x * x + y * y)
	if p == 0.0 and z == 0.0:
		return {}
	if p < 1e-12 * a:
		# 极点：经度无定义取 0，纬度 ±90；椭球面极点处 Z = ±b，h = |Z| − b
		var lat_p := 90.0 if z > 0.0 else -90.0
		var h_p := absf(z) - b
		return {"lat": lat_p, "lon": 0.0, "h": h_p, "n": a * (1.0 - e2)}
	var lon := rad_to_deg(atan2(y, x))
	var theta := atan2(z * a, p * b)
	var st := sin(theta)
	var ct := cos(theta)
	var lat := rad_to_deg(atan2(z + ep2 * b * st * st * st, p - e2 * a * ct * ct * ct))
	var sl := sin(deg_to_rad(lat))
	var n := a / sqrt(1.0 - e2 * sl * sl)
	var h := p / cos(deg_to_rad(lat)) - n
	return {"lat": lat, "lon": lon, "h": h, "n": n}

## §5 协议入口：BLH → XYZ。p = {lat_deg, lon_deg, h_m, datum|a+inv_f}
static func forward(p: Dictionary) -> Dictionary:
	var el := _ellipsoid_of(p)
	if el.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": SRC_NOTE,
				"error": "椭球参数缺失或不合法（需 datum 名或 a>0、1/f>0）"}
	var lat := _numf(p.get("lat_deg", NAN))
	var lon := _numf(p.get("lon_deg", NAN))
	var h := _numf(p.get("h_m", NAN))
	if not (is_finite(lat) and is_finite(lon) and is_finite(h)):
		return {"ok": false, "value": {}, "steps": [], "formula": SRC_NOTE,
				"error": "输入不是有效数值（纬度/经度/高程需为数字）"}
	if absf(lat) > 90.0:
		return {"ok": false, "value": {}, "steps": [], "formula": SRC_NOTE,
				"error": "纬度超出范围：|B| ≤ 90°，当前 B = %s" % String.num(lat, 6)}
	var r := blh_to_xyz(lat, lon, h, el)
	var a: float = el["a"]
	var e2: float = el["e2"]
	var n: float = r["n"]
	var steps := [
		{"title": "1. 计算卯酉圈曲率半径",
			"formula": "N = a / √(1 − e²·sin²B)",
			"substitution": "N = %s / √(1 − %s × sin²%s°)" % [String.num(a, 4), String.num(e2, 12), String.num(lat, 6)],
			"result": "N = %s m" % String.num(n, 4)},
		{"title": "2. 计算空间直角坐标",
			"formula": "X = (N+h)·cosB·cosL；Y = (N+h)·cosB·sinL；Z = (N(1−e²)+h)·sinB",
			"substitution": "B = %s°，L = %s°，h = %s m" % [String.num(lat, 6), String.num(lon, 6), String.num(h, 4)],
			"result": "X = %s m；Y = %s m；Z = %s m" % [String.num(r["x"], 4), String.num(r["y"], 4), String.num(r["z"], 4)]},
	]
	return {
		"ok": true,
		"value": {"x_m": r["x"], "y_m": r["y"], "z_m": r["z"], "N_m": n},
		"steps": steps,
		"formula": "BLH→XYZ 闭式正算（%s）" % SRC_NOTE,
		"error": "",
	}

## §5 协议入口：XYZ → BLH。p = {x_m, y_m, z_m, datum|a+inv_f}
static func inverse(p: Dictionary) -> Dictionary:
	var el := _ellipsoid_of(p)
	if el.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": SRC_NOTE,
				"error": "椭球参数缺失或不合法（需 datum 名或 a>0、1/f>0）"}
	var x := _numf(p.get("x_m", NAN))
	var y := _numf(p.get("y_m", NAN))
	var z := _numf(p.get("z_m", NAN))
	if not (is_finite(x) and is_finite(y) and is_finite(z)):
		return {"ok": false, "value": {}, "steps": [], "formula": SRC_NOTE,
				"error": "输入不是有效数值（X/Y/Z 需为数字）"}
	var r := xyz_to_blh(x, y, z, el)
	if r.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": SRC_NOTE,
				"error": "点位于地心（X=Y=Z=0）或坐标非法，无法反算大地坐标"}
	var a: float = el["a"]
	var b: float = el["b"]
	var e2: float = el["e2"]
	var ep2: float = el["ep2"]
	var p_p := sqrt(x * x + y * y)
	var lat: float = r["lat"]
	var theta := atan2(z * a, p_p * b)
	var st := sin(theta)
	var steps := [
		{"title": "1. 计算辅助量 p 与经度",
			"formula": "p = √(X²+Y²)；L = atan2(Y, X)",
			"substitution": "p = √(%s² + %s²)" % [String.num(x, 4), String.num(y, 4)],
			"result": "p = %s m；L = %s°" % [String.num(p_p, 4), String.num(r["lon"], 9)]},
		{"title": "2. 计算辅助角 θ（参数纬度逼近）",
			"formula": "θ = atan2(Z·a, p·b)",
			"substitution": "θ = atan2(%s × %s, %s × %s)" % [String.num(z, 4), String.num(a, 4), String.num(p_p, 4), String.num(b, 4)],
			"result": "θ = %s°" % String.num(rad_to_deg(theta), 9)},
		{"title": "3. Bowring 闭式反算纬度",
			"formula": "B = atan2(Z + e′²·b·sin³θ, p − e²·a·cos³θ)",
			"substitution": "e² = %s，e′² = %s，sinθ = %s" % [String.num(e2, 12), String.num(ep2, 12), String.num(st, 9)],
			"result": "B = %s°（%s）" % [String.num(lat, 9), GKAngles.deg_to_dms_str(lat, 4)]},
		{"title": "4. 计算大地高",
			"formula": "h = p/cosB − N，N = a/√(1−e²·sin²B)",
			"substitution": "N = %s m" % String.num(r["n"], 4),
			"result": "h = %s m" % String.num(r["h"], 4)},
	]
	return {
		"ok": true,
		"value": {
			"lat_deg": r["lat"], "lon_deg": r["lon"], "h_m": r["h"],
			"lat_dms": GKAngles.deg_to_dms_str(lat, 4),
			"lon_dms": GKAngles.deg_to_dms_str(r["lon"], 4),
			"N_m": r["n"],
		},
		"steps": steps,
		"formula": "XYZ→BLH 闭式反算（Bowring 法，%s）" % SRC_NOTE,
		"error": "",
	}
