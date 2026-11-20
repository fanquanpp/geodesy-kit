# core/astro/solar.gd —— GK-M8-1（F3）太阳方位角/高度角（NOAA 太阳计算器算法移植，真北定向）
#
# 算法来源：NOAA GML 太阳位置计算器（_scripts/azel.html 留档底本，JS 源逐式移植；
# 与 _scripts/verify_vectors.py §11 的移植完全同源）。方位角自真北起顺时针 [0°,360°)；
# 天顶距输出为几何天顶距（未加大气折光改正，与权威向量口径一致），另附折光改正后
# 视高度角作参考。算法适用 1901-2099 年（NOAA 电子表格口径），页脚与 formula 尾注均标注。
#
# 设计约定（docs/ARCHITECTURE.md §1.1/§4/§5）：
#   - 纯静态、零引擎依赖（extends RefCounted）；纯离线，无任何网络调用；
#   - 输入校验先行：非法输入返回 {ok:false, value:{}, error:中文}，不抛异常；
#   - 返回 §5 协议 {ok, value, steps[{title,formula,substitution,result}], formula, error}；
#   - 数值口径经权威向量复核：本会话 3 例与 pvlib 互差 ≤0.007°（ARCHITECTURE.md §4 GK-M8）。
class_name GKSolar
extends RefCounted

const J2000_JD := 2451545.0
const JULIAN_CENTURY := 36525.0
const MIN_VALID_YEAR := 1901
const MAX_VALID_YEAR := 2099

## 儒略日（格里历，日界 0h UT）：calcJD 算法（NOAA 留档 azel.html 同源）。
static func calc_jd(year: int, month: int, day: int) -> float:
	var y := year
	var m := month
	if m <= 2:
		y -= 1
		m += 12
	var a := int(floor(float(y) / 100.0))
	var b := 2 - a + int(floor(float(a) / 4.0))
	return floor(365.25 * float(y + 4716)) + floor(30.6001 * float(m + 1)) + float(day) + float(b) - 1524.5

## 儒略世纪数 T（自 J2000.0）
static func julian_cent(jd: float) -> float:
	return (jd - J2000_JD) / JULIAN_CENTURY

static func _mean_obliquity(t: float) -> float:
	var sec := 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
	return 23.0 + (26.0 + sec / 60.0) / 60.0

static func _obliquity_corr(t: float) -> float:
	return _mean_obliquity(t) + 0.00256 * cos(deg_to_rad(125.04 - 1934.136 * t))

static func _geom_mean_long(t: float) -> float:
	var l0 := 280.46646 + t * (36000.76983 + 0.0003032 * t)
	return fmod(fmod(l0, 360.0) + 360.0, 360.0)

static func _geom_mean_anom(t: float) -> float:
	return 357.52911 + t * (35999.05029 - 0.0001537 * t)

static func _ecc_orbit(t: float) -> float:
	return 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

static func _eq_center(t: float) -> float:
	var m := deg_to_rad(_geom_mean_anom(t))
	return (sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
			+ sin(2.0 * m) * (0.019993 - 0.000101 * t) + sin(3.0 * m) * 0.000289)

static func _apparent_long(t: float) -> float:
	var o := _geom_mean_long(t) + _eq_center(t)
	return o - 0.00569 - 0.00478 * sin(deg_to_rad(125.04 - 1934.136 * t))

## 太阳赤纬（度）
static func sun_declination(t: float) -> float:
	var sint := sin(deg_to_rad(_obliquity_corr(t))) * sin(deg_to_rad(_apparent_long(t)))
	return rad_to_deg(asin(sint))

## 均时差 EoT（分钟，真太阳时 − 平太阳时口径）
static func equation_of_time(t: float) -> float:
	var eps := deg_to_rad(_obliquity_corr(t))
	var l0 := deg_to_rad(_geom_mean_long(t))
	var e := _ecc_orbit(t)
	var m := deg_to_rad(_geom_mean_anom(t))
	var y := tan(eps / 2.0)
	y = y * y
	var et := (y * sin(2.0 * l0) - 2.0 * e * sin(m)
			+ 4.0 * e * y * sin(m) * cos(2.0 * l0)
			- 0.5 * y * y * sin(4.0 * l0) - 1.25 * e * e * sin(2.0 * m))
	return rad_to_deg(et) * 4.0

## 太阳赤纬 + 均时差一次性求取（供 sun_events 复用）：{decl_deg, eot_min}
static func declination_eot(t: float) -> Dictionary:
	return {"decl_deg": sun_declination(t), "eot_min": equation_of_time(t)}

## 大气折光改正（度）：NOAA 分段经验式（真高度 exoatmElevation 输入）
static func refraction_correction_deg(exoatm_elev_deg: float) -> float:
	if exoatm_elev_deg > 85.0:
		return 0.0
	var te := tan(deg_to_rad(exoatm_elev_deg))
	var rc := 0.0
	if exoatm_elev_deg > 5.0:
		rc = 58.1 / te - 0.07 / (te * te * te) + 0.000086 / (te * te * te * te * te)
	elif exoatm_elev_deg > -0.575:
		rc = 1735.0 + exoatm_elev_deg * (-518.2 + exoatm_elev_deg * (103.4
				+ exoatm_elev_deg * (-12.79 + exoatm_elev_deg * 0.711)))
	else:
		rc = -20.774 / te
	return rc / 3600.0

## 计算入口（§5 协议）
## p: {year, month, day, hour, minute, second（UTC）, lat_deg, lon_deg（东经为正）,
##     with_refraction（可选，默认 false：输出几何天顶距，与权威向量口径一致）}
static func solar_position(p: Dictionary) -> Dictionary:
	var year := int(p.get("year", 0))
	var month := int(p.get("month", 0))
	var day := int(p.get("day", 0))
	var hour := int(p.get("hour", 0))
	var minute := int(p.get("minute", 0))
	var second := float(p.get("second", 0.0))
	var lat := float(p.get("lat_deg", NAN))
	var lon := float(p.get("lon_deg", NAN))
	var with_refr := bool(p.get("with_refraction", false))

	if year < MIN_VALID_YEAR or year > MAX_VALID_YEAR:
		return _err("年份 %d 超出 NOAA 算法适用范围（%d-%d 年）" % [year, MIN_VALID_YEAR, MAX_VALID_YEAR])
	if month < 1 or month > 12:
		return _err("月份 %d 非法（应为 1-12）" % month)
	if day < 1 or day > 31:
		return _err("日 %d 非法（应为 1-31）" % day)
	if hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0.0 or second >= 60.0:
		return _err("时间 %02d:%02d:%06.3f 非法（UTC 24 小时制）" % [hour, minute, second])
	if is_nan(lat) or absf(lat) > 89.8:
		return _err("纬度非法：应在 ±89.8° 内（极点附近太阳方位定义不稳定）")
	if is_nan(lon) or lon > 180.0 or lon <= -180.0:
		return _err("经度非法：应为 −180° < 经度 ≤ 180°（东经为正）")

	var jd := calc_jd(year, month, day) + hour / 24.0 + minute / 1440.0 + second / 86400.0
	var t := julian_cent(jd)
	var decl := sun_declination(t)
	var eot := equation_of_time(t)

	# 真太阳时（分钟）= UTC 分钟 + 均时差 + 4 分钟/度 × 东经（NOAA 口径，时区项取 0）
	var tst := fmod(hour * 60.0 + minute + second / 60.0 + eot + 4.0 * lon + 1440.0 * 2.0, 1440.0)
	var ha := tst / 4.0 - 180.0
	if ha < -180.0:
		ha += 360.0

	var phi := deg_to_rad(lat)
	var csz := sin(phi) * sin(deg_to_rad(decl)) + cos(phi) * cos(deg_to_rad(decl)) * cos(deg_to_rad(ha))
	csz = clampf(csz, -1.0, 1.0)
	var zen := rad_to_deg(acos(csz))

	var az := 0.0
	var az_denom := cos(phi) * sin(deg_to_rad(zen))
	if absf(az_denom) > 0.001:
		var azr := (sin(phi) * cos(deg_to_rad(zen)) - sin(deg_to_rad(decl))) / az_denom
		azr = clampf(azr, -1.0, 1.0)
		az = 180.0 - rad_to_deg(acos(azr))
		if ha > 0.0:
			az = -az
	else:
		az = 180.0 if lat > 0.0 else 0.0
	if az < 0.0:
		az += 360.0

	var elev := 90.0 - zen
	var refr := refraction_correction_deg(elev)

	var value := {
		"az_deg": az,                       # 方位角（真北起顺时针）
		"zen_deg": zen,                     # 几何天顶距（未加折光）
		"elev_deg": elev,                   # 几何高度角
		"decl_deg": decl,                   # 太阳赤纬
		"eot_min": eot,                     # 均时差（分钟）
		"jd_utc": jd,                       # 儒略日
		"hour_angle_deg": ha,               # 时角（正午为 0，午后为正）
	}
	if with_refr:
		value["elev_apparent_deg"] = elev + refr
		value["refr_corr_deg"] = refr

	var steps := [
		{
			"title": "1. 计算儒略日与儒略世纪数",
			"formula": "JD = calcJD(年,月,日) + (h + m/60 + s/3600)/24；T = (JD − 2451545.0)/36525",
			"substitution": "JD = %.6f + %.9f = %.9f；T = %.12f" % [calc_jd(year, month, day), (hour + minute / 60.0 + second / 3600.0) / 24.0, jd, t],
			"result": "T = %.12f" % t,
		},
		{
			"title": "2. 太阳赤纬与均时差",
			"formula": "sinδ = sin(ε修正)·sin(λ视)；EoT = rad_to_deg(y·sin2L₀ − 2e·sinM + …)·4",
			"substitution": "δ = asin(sin(ε)·sin(λ)) ；ε、λ 由 T 的级数求得",
			"result": "δ = %+.6f°，EoT = %.4f min" % [decl, eot],
		},
		{
			"title": "3. 真太阳时与时角",
			"formula": "TST = UTC·60 + EoT + 4·λ（模 1440）；HA = TST/4 − 180",
			"substitution": "TST = %d×60 + %d + %.4f + %.4f = %.4f min" % [hour, minute, second / 60.0, eot + 4.0 * lon, tst],
			"result": "HA = %.6f°" % ha,
		},
		{
			"title": "4. 天顶距与方位角（真北定向）",
			"formula": "cos z = sinφ·sinδ + cosφ·cosδ·cos(HA)；Az 由 acos[(sinφ·cos z − sinδ)/(cosφ·sin z)] 计（午后取反）",
			"substitution": "cos z = %.9f；z = acos(cos z)" % csz,
			"result": "z = %.6f°，Az = %.6f°" % [zen, az],
		},
	]
	var formula := "NOAA 太阳位置算法（真北方位角、几何天顶距）；适用 %d-%d 年，教学演示口径" % [MIN_VALID_YEAR, MAX_VALID_YEAR]
	if with_refr:
		formula += "；elev_apparent_deg 已加大气折光改正（低高度角精度有限）"
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
