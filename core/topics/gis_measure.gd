# core/topics/gis_measure.gd —— GK-M8-8（I-GIS 量测）
#
# 内容（球面近似，平均半径 R₁ = (2a+b)/3 = 6371008.7714 m，与分派向量口径一致）：
#   - Haversine 大圆距离（权威构造向量：北京(39.9075276,116.3912757)→
#     上海(31.1666667,121.4666667) = 1074470.9 m）；
#   - 缓冲区经纬范围估算（dLat = r/R，dLon = r/(R·cosφ)，近极区作展宽提示与钳制）；
#   - IDW 反距离加权插值（幂 p 默认 2，精确命中直接返回样本值）；
#   - 球面多边形面积（Chamberlain–Duquette / Turf.js 同式：A = R²/2·Σ Δλ(2+sinφ₁+sinφ₂)）。
#
# 设计约定同 core/astro/solar.gd 头注。
class_name GKGisMeasure
extends RefCounted

const R_MEAN_M := 6371008.7714       # WGS84 平均半径 R1 = (2a+b)/3
const MU_PER_HA := 10000.0 / 666.6666666666666  # 1 公顷 = 15 亩

## Haversine 大圆距离（§5 协议）
## p: {lat1, lon1, lat2, lon2（度，东经北纬为正）, R_m 可选}
static func haversine(p: Dictionary) -> Dictionary:
	var lat1 := float(p.get("lat1", NAN))
	var lon1 := float(p.get("lon1", NAN))
	var lat2 := float(p.get("lat2", NAN))
	var lon2 := float(p.get("lon2", NAN))
	var r := float(p.get("R_m", R_MEAN_M))
	var chk := _check_ll(lat1, lon1, "点1")
	if chk != "":
		return _err(chk)
	chk = _check_ll(lat2, lon2, "点2")
	if chk != "":
		return _err(chk)
	if not is_finite(r) or r <= 0.0:
		return _err("球半径 R 非法：应为正（默认平均半径 6371008.7714 m）")
	var p1 := deg_to_rad(lat1)
	var l1 := deg_to_rad(lon1)
	var p2 := deg_to_rad(lat2)
	var l2 := deg_to_rad(lon2)
	var dp := p2 - p1
	var dl := l2 - l1
	var a := sin(dp / 2.0) * sin(dp / 2.0) + cos(p1) * cos(p2) * sin(dl / 2.0) * sin(dl / 2.0)
	a = clampf(a, 0.0, 1.0)
	var dist := 2.0 * r * asin(sqrt(a))
	var central := rad_to_deg(2.0 * asin(sqrt(a)))
	var value := {
		"dist_m": dist,
		"dist_km": dist / 1000.0,
		"central_deg": central,
		"R_m": r,
	}
	var steps := [
		{"title": "1. Haversine 半角公式",
			"formula": "a = sin²(Δφ/2) + cosφ₁·cosφ₂·sin²(Δλ/2)",
			"substitution": "Δφ = %.9f°，Δλ = %.9f°" % [lat2 - lat1, lon2 - lon1],
			"result": "a = %.12f" % a},
		{"title": "2. 大圆距离",
			"formula": "d = 2R·asin(√a)",
			"substitution": "2×%.1f×asin(√%.12f)" % [r, a],
			"result": "d = %.4f m（圆心角 %.6f°）" % [dist, central]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "Haversine 大圆距离（球近似，R₁ = %.1f m）；米级精度需求请用椭球大地线（M2 geodesic）" % r,
			"error": ""}

## 缓冲区经纬范围估算（§5 协议）
## p: {lat, lon, radius_m, R_m 可选}
static func buffer_bbox(p: Dictionary) -> Dictionary:
	var lat := float(p.get("lat", NAN))
	var lon := float(p.get("lon", NAN))
	var radius := float(p.get("radius_m", NAN))
	var r := float(p.get("R_m", R_MEAN_M))
	var chk := _check_ll(lat, lon, "中心点")
	if chk != "":
		return _err(chk)
	if not is_finite(radius) or radius <= 0.0 or radius > 2000000.0:
		return _err("缓冲半径非法：应为 0 < r ≤ 2 000 000 m")
	if not is_finite(r) or r <= 0.0:
		return _err("球半径 R 非法")
	var dlat := rad_to_deg(radius / r)
	var dlon := 360.0
	var note := ""
	if absf(lat) + dlat < 89.99:
		dlon = dlat / maxf(cos(deg_to_rad(lat)), 1e-9)
	else:
		note = "缓冲区含极点附近，经度方向覆盖全经度范围"
	var value := {
		"lat_min_deg": lat - dlat,
		"lat_max_deg": lat + dlat,
		"lon_min_deg": -180.0 if note != "" else lon - dlon,
		"lon_max_deg": 180.0 if note != "" else lon + dlon,
		"dlat_deg": dlat,
		"dlon_deg": dlon,
	}
	if note != "":
		value["note"] = note
	var steps := [
		{"title": "1. 纬度方向角距",
			"formula": "Δφ = r/R（弧度）→ 度",
			"substitution": "%.1f/%.1f = %.9f rad" % [radius, r, radius / r],
			"result": "Δφ = %.9f°" % dlat},
		{"title": "2. 经度方向角距",
			"formula": "Δλ = Δφ/cosφ（纬圈半径收缩）",
			"substitution": "cosφ = %.9f" % cos(deg_to_rad(lat)),
			"result": "Δλ = %.9f°" % dlon + ("（%s）" % note if note != "" else "")},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "缓冲区经纬范围球面估算（正圆近似，范围框为包含缓冲圆的经纬矩形）",
			"error": ""}

## IDW 反距离加权插值（§5 协议）
## p: {samples: "lat,lon,val;lat,lon,val;...", target_lat, target_lon, power=2, R_m 可选}
static func idw(p: Dictionary) -> Dictionary:
	var samples: Variant = _parse_samples(String(p.get("samples", "")))
	if samples is String:
		return _err(samples)
	var tlat := float(p.get("target_lat", NAN))
	var tlon := float(p.get("target_lon", NAN))
	var pw := float(p.get("power", 2.0))
	var r := float(p.get("R_m", R_MEAN_M))
	var chk := _check_ll(tlat, tlon, "目标点")
	if chk != "":
		return _err(chk)
	if not is_finite(pw) or pw <= 0.0:
		return _err("幂参数 p 非法：应为正（常用 1~3，默认 2）")
	if not is_finite(r) or r <= 0.0:
		return _err("球半径 R 非法")
	# 权重：1/d^p（精确命中 → 直接返回该样本值）
	var exact: Array = []
	var num := 0.0
	var den := 0.0
	var details := []
	for s: Array in samples:
		var d := _haversine_m(float(s[0]), float(s[1]), tlat, tlon, r)
		if d < 1e-9:
			exact = s
			break
		var w := 1.0 / pow(d, pw)
		num += w * float(s[2])
		den += w
		details.append("d=%.3f m → w=%.9f" % [d, w])
	if not exact.is_empty():
		var value_exact := {
			"value": float(exact[2]),
			"exact_hit": true,
			"n_samples": samples.size(),
		}
		return {"ok": true, "value": value_exact, "steps": [
			{"title": "IDW 插值（精确命中）",
				"formula": "目标点与样本点重合时直接返回该样本值",
				"substitution": "样本 (%.6f, %.6f) 距离为 0" % [float(exact[0]), float(exact[1])],
				"result": "%.6f" % float(exact[2])},
		], "formula": "IDW 反距离加权插值（p=%.1f，精确命中直返）" % pw, "error": ""}
	var value := {
		"value": num / den,
		"exact_hit": false,
		"n_samples": samples.size(),
		"power": pw,
	}
	var steps := [
		{"title": "1. 各样本球面距离与权重",
			"formula": "wᵢ = 1/dᵢ^p，p = %.1f" % pw,
			"substitution": "\n".join(details),
			"result": "Σw = %.9f" % den},
		{"title": "2. 加权平均",
			"formula": "z = Σ(wᵢ·zᵢ)/Σwᵢ",
			"substitution": "Σ(wᵢ·zᵢ) = %.6f，Σwᵢ = %.9f" % [num, den],
			"result": "z = %.6f" % (num / den)},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "IDW 反距离加权插值（球面 Haversine 距离，p=%.1f）" % pw,
			"error": ""}

## 球面多边形面积（§5 协议；Chamberlain–Duquette 公式，环闭合自动处理）
## p: {ring: "lat,lon;lat,lon;..."（≥3 点，逆/顺时针皆可取绝对值）, R_m 可选}
static func spherical_area(p: Dictionary) -> Dictionary:
	var ring: Variant = _parse_samples(String(p.get("ring", "")))
	if ring is String:
		return _err(String(ring).replace("样本", "顶点"))
	if (ring as Array).size() < 3:
		return _err("顶点不足：球面多边形至少需要 3 个顶点（lat,lon;… 分号分隔）")
	var r := float(p.get("R_m", R_MEAN_M))
	if not is_finite(r) or r <= 0.0:
		return _err("球半径 R 非法")
	var total := 0.0
	var n: int = ring.size()
	for i in n:
		var s1: Array = ring[i]
		var s2: Array = ring[(i + 1) % n]
		var chk := _check_ll(float(s1[0]), float(s1[1]), "顶点%d" % (i + 1))
		if chk != "":
			return _err(chk)
		chk = _check_ll(float(s2[0]), float(s2[1]), "顶点%d" % ((i + 1) % n + 1))
		if chk != "":
			return _err(chk)
		var dl := deg_to_rad(float(s2[1]) - float(s1[1]))
		total += dl * (2.0 + sin(deg_to_rad(float(s1[0]))) + sin(deg_to_rad(float(s2[0]))))
	var area := absf(total) * r * r / 2.0
	var value := {
		"area_m2": area,
		"area_km2": area / 1e6,
		"area_ha": area / 10000.0,
		"area_mu": area / 10000.0 * MU_PER_HA,
		"n_vertices": n,
	}
	var steps := [
		{"title": "1. Chamberlain–Duquette 求和",
			"formula": "S = Σ Δλᵢ·(2 + sinφᵢ + sinφᵢ₊₁)（环逐边求和）",
			"substitution": "%d 个顶点，Σ = %.9f" % [n, total],
			"result": "球面过剩量级已含于 S"},
		{"title": "2. 球面面积",
			"formula": "A = R²·|S|/2",
			"substitution": "%.1f²×|%.9f|/2" % [r, total],
			"result": "A = %.4f m² = %.6f km² = %.4f 公顷 = %.2f 亩" % [area, area / 1e6, area / 10000.0, area / 10000.0 * MU_PER_HA]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "球面多边形面积（Chamberlain–Duquette，R₁=%.1f m）；大范围多边形为球面近似" % r,
			"error": ""}

# ---------- 内部工具 ----------

static func _check_ll(lat: float, lon: float, label: String) -> String:
	if is_nan(lat) or absf(lat) > 90.0:
		return "%s纬度非法：|纬度| ≤ 90°" % label
	if is_nan(lon) or lon > 180.0 or lon < -180.0:
		return "%s经度非法：−180° ≤ 经度 ≤ 180°" % label
	return ""

static func _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float, r: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := deg_to_rad(lat2 - lat1)
	var dl := deg_to_rad(lon2 - lon1)
	var a := sin(dp / 2.0) * sin(dp / 2.0) + cos(p1) * cos(p2) * sin(dl / 2.0) * sin(dl / 2.0)
	return 2.0 * r * asin(sqrt(clampf(a, 0.0, 1.0)))

## 解析 "lat,lon[,val];..."（每组 2 或 3 个数，与首组一致）
static func _parse_samples(text: String) -> Variant:
	var t := text.strip_edges().replace("，", ",").replace("；", ";").replace(" ", "").replace("\n", "").replace("\r", "")
	if t.is_empty():
		return "列表为空：格式应为 lat,lon[,val];…"
	var recs := t.split(";", false)
	var per := recs[0].split(",").size()
	if per < 2 or per > 3:
		return "格式错误：每组应为 lat,lon（面积）或 lat,lon,val（IDW）"
	for rec in recs:
		var parts := rec.split(",")
		if parts.size() != per:
			return "每组字段数不一致：%s" % rec
		for s in parts:
			if not s.is_valid_float():
				return "含非数值字段：%s" % rec
	var out := []
	for rec in recs:
		var parts := rec.split(",")
		var row := []
		for s in parts:
			row.append(s.to_float())
		out.append(row)
	return out

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
