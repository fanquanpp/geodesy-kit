# core/ellipsoid/rhumb.gd —— A12 恒向线（等角航线/loxodrome）正反解
#
# 精确 Mercator 参数法（球面严格式，ARCHITECTURE.md §4 GK-M2 指定）：
#   等量纬度 ψ(φ) = ln tan(π/4 + φ/2)；
#   Δψ = ψ(φ₂) − ψ(φ₁)；方位角 az = atan2(Δλ, Δψ)（常向线性质：沿航线上处处相等）；
#   距离 d = |Δφ|·R / cos(az)（球面上 dφ = cos(az)·ds/R 严格成立）。
#   等纬退化（|Δψ|≤1e-10，即沿平行圈东西航行）：d = R·|Δλ|·cos φ（平行圈弧长）。
#   反解：δ=d/R；Δφ = δ·cos(az)；φ₂ = φ₁+Δφ；q = Δψ/Δφ（Δφ≈0 时取 cos φ₁）；
#         Δλ = δ·sin(az)/q；λ₂ = λ₁ + Δλ。
# 半径默认 R₁ = (2a+b)/3（WGS84 = 6371008.7714 m，与向量口径一致）。
# 验收【构造·_scripts/gen_vectors_b.py:79-91 复跑一致】：
#   北京(39.9075276,116.3912757) → 上海(31.1666667,121.4666667)：
#   d = 1074590.1 m，az = 154.7528°（R1=6371008.7714 m）。
# 协议：static func forward/inverse(p) -> {ok, value, steps, formula, error}。
class_name GKRhumb
extends RefCounted

const SRC_NOTE := "恒向线精确 Mercator 参数法（Δψ 等量纬度，球面严格式）"

## 等量纬度 ψ(φ)
static func psi(lat_deg: float) -> float:
	var phi := deg_to_rad(lat_deg)
	return log(tan(PI / 4.0 + phi / 2.0))

## 从参数取平均半径：p.radius_m 优先；否则按 datum/a+inv_f 取 R1=(2a+b)/3。
## 指定了未知 datum 名返回 NAN（不静默回落默认椭球）。
static func _radius_of(p: Dictionary) -> float:
	var r := float(p.get("radius_m", NAN))
	if is_finite(r) and r > 0.0:
		return r
	var datum := String(p.get("datum", ""))
	var el := {}
	if datum != "":
		el = GKEllipsoid.params(datum)
		if el.is_empty():
			return NAN
	else:
		var a := float(p.get("a", 6378137.0))
		var inv_f := float(p.get("inv_f", 298.257223563))
		if a > 0.0 and inv_f > 0.0:
			el = GKEllipsoid.derived(a, inv_f)
	if el.is_empty():
		return NAN
	return GKEllipsoid.mean_radius(float(el["a"]), float(el["b"]))

static func _fail(err: String, formula := SRC_NOTE) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": err}

## §5 协议：正解（两点 → 距离与方位角）。p = {lat1_deg, lon1_deg, lat2_deg, lon2_deg, datum|radius_m}
static func forward(p: Dictionary) -> Dictionary:
	var r := _radius_of(p)
	if not (is_finite(r) and r > 0.0):
		return _fail("平均半径缺失或不合法（需 radius_m>0 或合法 datum/a+inv_f）")
	var lat1 := float(p.get("lat1_deg", NAN))
	var lon1 := float(p.get("lon1_deg", NAN))
	var lat2 := float(p.get("lat2_deg", NAN))
	var lon2 := float(p.get("lon2_deg", NAN))
	for v in [lat1, lon1, lat2, lon2]:
		if not is_finite(v):
			return _fail("输入不是有效数值（起点/终点经纬度需为数字）")
	if absf(lat1) > 90.0 or absf(lat2) > 90.0:
		return _fail("纬度超出范围：|B| ≤ 90°")
	# 经差规范化到 (−180°, 180°]，避免跨 180° 航线绕远路
	var dlam_deg := GKAngles.normalize_deg(lon2 - lon1 + 180.0) - 180.0
	var dphi := deg_to_rad(lat2 - lat1)
	var dlam := deg_to_rad(dlam_deg)
	var dpsi := psi(lat2) - psi(lat1)
	var az := NAN
	var dist := NAN
	var degenerate := absf(dpsi) <= 1e-10
	if degenerate:
		# 等纬（沿平行圈）：方位 90°/270°，距离=平行圈弧长
		az = 90.0 if dlam >= 0.0 else 270.0
		dist = r * absf(dlam) * cos(deg_to_rad(lat1))
		if absf(dlam) < 1e-14:
			az = 0.0
			dist = 0.0
	else:
		az = rad_to_deg(atan2(dlam, dpsi))
		if az < 0.0:
			az += 360.0
		var ca := cos(deg_to_rad(az))
		dist = absf(dphi) * r / absf(ca) if absf(ca) > 1e-15 else 0.0
		if dist == 0.0:
			az = 0.0
	var steps := [
		{"title": "1. 计算等量纬度差（Mercator 参数）",
			"formula": "ψ = ln tan(π/4 + φ/2)；Δψ = ψ₂ − ψ₁",
			"substitution": "ψ₁ = %s，ψ₂ = %s" % [String.num(psi(lat1), 9), String.num(psi(lat2), 9)],
			"result": "Δψ = %s rad" % String.num(dpsi, 9)},
		{"title": "2. 计算恒向线方位角",
			"formula": "az = atan2(Δλ, Δψ)",
			"substitution": "Δλ = %s°，Δψ = %s" % [String.num(dlam_deg, 9), String.num(dpsi, 9)],
			"result": "az = %s°" % String.num(az, 4)},
		{"title": "3. 计算恒向线距离",
			"formula": "d = |Δφ|·R / cos(az)（等纬时 d = R·|Δλ|·cos φ）",
			"substitution": "R = %s m，Δφ = %s rad" % [String.num(r, 4), String.num(dphi, 9)],
			"result": "d = %s m" % String.num(dist, 1)},
	]
	return {
		"ok": true,
		"value": {"distance_m": dist, "azimuth_deg": az, "dpsi_rad": dpsi, "radius_m": r},
		"steps": steps,
		"formula": "恒向线正解（%s；R1=(2a+b)/3）" % SRC_NOTE,
		"error": "",
	}

## §5 协议：反解（起点+方位+距离 → 终点）。p = {lat1_deg, lon1_deg, az_deg, distance_m, datum|radius_m}
static func inverse(p: Dictionary) -> Dictionary:
	var r := _radius_of(p)
	if not (is_finite(r) and r > 0.0):
		return _fail("平均半径缺失或不合法（需 radius_m>0 或合法 datum/a+inv_f）")
	var lat1 := float(p.get("lat1_deg", NAN))
	var lon1 := float(p.get("lon1_deg", NAN))
	var az := float(p.get("az_deg", NAN))
	var d := float(p.get("distance_m", NAN))
	for v in [lat1, lon1, az, d]:
		if not is_finite(v):
			return _fail("输入不是有效数值（起点/方位/距离需为数字）")
	if absf(lat1) > 90.0:
		return _fail("纬度超出范围：|B| ≤ 90°")
	if d < 0.0:
		return _fail("距离不能为负数")
	var az_n := GKAngles.normalize_deg(az)
	var delta := d / r
	var dphi := delta * cos(deg_to_rad(az_n))
	var lat2 := lat1 + rad_to_deg(dphi)
	if lat2 > 90.0 or lat2 < -90.0:
		return _fail("终点纬度超出 ±90°（恒向线到达极点后无定义），请缩短距离")
	var dpsi := psi(lat2) - psi(lat1)
	# 精确逆：恒向线上 tan(az) = Δλ/Δψ → Δλ = Δψ·tan(az)；
	# 等纬退化（|Δψ|≈0，az≈±90°）时按平行圈弧长：Δλ = δ·sin(az)/cos(φ₁)。
	var dlam := 0.0
	var caz := cos(deg_to_rad(az_n))
	if absf(caz) > 1e-8 and absf(dpsi) > 1e-12:
		dlam = dpsi * sin(deg_to_rad(az_n)) / caz
	else:
		var c1 := cos(deg_to_rad(lat1))
		if absf(c1) > 1e-15:
			dlam = delta * sin(deg_to_rad(az_n)) / c1
	var lon2 := lon1 + rad_to_deg(dlam)
	var steps := [
		{"title": "1. 计算角距与纬度增量",
			"formula": "δ = d/R；Δφ = δ·cos(az)",
			"substitution": "δ = %s / %s = %s rad" % [String.num(d, 1), String.num(r, 4), String.num(delta, 9)],
			"result": "Δφ = %s rad → B₂ = %s°" % [String.num(dphi, 9), String.num(lat2, 6)]},
		{"title": "2. 计算等量纬度差",
			"formula": "Δψ = ln tan(π/4+φ₂/2) − ln tan(π/4+φ₁/2)",
			"substitution": "ψ₁ = %s，ψ₂ = %s" % [String.num(psi(lat1), 9), String.num(psi(lat2), 9)],
			"result": "Δψ = %s rad" % String.num(dpsi, 9)},
		{"title": "3. 计算经度增量",
			"formula": "Δλ = Δψ·tan(az)（等纬时 Δλ = δ·sin(az)/cos φ₁）",
			"substitution": "az = %s°，Δψ = %s rad" % [String.num(az_n, 4), String.num(dpsi, 9)],
			"result": "Δλ = %s° → L₂ = %s°" % [String.num(rad_to_deg(dlam), 9), String.num(lon2, 6)]},
	]
	return {
		"ok": true,
		"value": {"lat2_deg": lat2, "lon2_deg": lon2, "delta_rad": delta},
		"steps": steps,
		"formula": "恒向线反解（%s）" % SRC_NOTE,
		"error": "",
	}
