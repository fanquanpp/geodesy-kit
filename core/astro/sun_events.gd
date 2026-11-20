# core/astro/sun_events.gd —— GK-M8-2（F4）日出日落/时角/赤纬（ha0 法）
#
# 算法（ARCHITECTURE.md §4 GK-M8 F4）：
#   cos(ha0) = (sin h0 − sinφ·sinδ)/(cosφ·cosδ) ≡ cos(h0)/(cosφ·cosδ) − tanφ·tanδ
#   其中 h0 = −0.833°（太阳视半径 16′ + 大气折光 34′ 的综合地平高度）。
#   中天时刻（真太阳时 12:00）：UTC_noon = (720 − EoT − 4λ)/60（小时，东经为正）；
#   日出 UTC = 中天 − ha0/15（小时），日落 UTC = 中天 + ha0/15；昼长 = 2·ha0/15。
# δ 与 EoT 在该日太阳中天时刻的儒略世纪数上求取（迭代一次），与权威构造向量
# （δ 取 2024-06-21 06Z 值 23.43811°）互差 <0.001°，判据"日出时刻太阳高度 ≈ −0.833°"
# 经 GKSolar 交叉复核成立。
#
# 设计约定同 core/astro/solar.gd 头注；极昼/极夜返回专用提示（ok=true，无日出现象）。
class_name GKSunEvents
extends RefCounted

const DEFAULT_H0_DEG := -0.833  # 日出日落地平高度（折光 34′ + 视半径 16′）

## 计算入口（§5 协议）
## p: {year, month, day, lat_deg, lon_deg（东经为正）, h0_deg（可选，默认 −0.833）,
##     tz_hours（可选，东正西负，如北京时间 +8；提供则同时输出本地时刻）}
static func sun_events(p: Dictionary) -> Dictionary:
	var year := int(p.get("year", 0))
	var month := int(p.get("month", 0))
	var day := int(p.get("day", 0))
	var lat := float(p.get("lat_deg", NAN))
	var lon := float(p.get("lon_deg", NAN))
	var h0 := float(p.get("h0_deg", DEFAULT_H0_DEG))
	var has_tz := p.has("tz_hours")
	var tz := float(p.get("tz_hours", 0.0))

	if year < 1901 or year > 2099:
		return _err("年份 %d 超出适用范围（1901-2099）" % year)
	if month < 1 or month > 12:
		return _err("月份 %d 非法（应为 1-12）" % month)
	if day < 1 or day > 31:
		return _err("日 %d 非法（应为 1-31）" % day)
	if is_nan(lat) or absf(lat) >= 90.0:
		return _err("纬度非法：|纬度| 应 < 90°（极点无日出日落概念）")
	if is_nan(lon) or lon > 180.0 or lon <= -180.0:
		return _err("经度非法：应为 −180° < 经度 ≤ 180°（东经为正）")
	if absf(h0) >= 90.0:
		return _err("地平高度阈值 h0 非法：|h0| 应 < 90°")
	if has_tz and absf(tz) > 12.0:
		return _err("时区偏移非法：应在 ±12 小时内（东正西负）")

	var jd0 := GKSolar.calc_jd(year, month, day)
	var t1 := GKSolar.julian_cent(jd0)
	var eot1: float = GKSolar.equation_of_time(t1)
	# 迭代一次：以中天时刻的 δ/EoT 为准（中天：真太阳时 12:00 = 720 分钟）
	var noon_min := 720.0 - eot1 - 4.0 * lon
	var t2 := GKSolar.julian_cent(jd0 + noon_min / 1440.0)
	var decl: float = GKSolar.sun_declination(t2)
	var eot: float = GKSolar.equation_of_time(t2)
	noon_min = 720.0 - eot - 4.0 * lon

	var phi := deg_to_rad(lat)
	var sd := deg_to_rad(decl)
	var cd := cos(sd)
	var cos_ha0 := (sin(deg_to_rad(h0)) - sin(phi) * sin(sd)) / (cos(phi) * cd)
	if cos_ha0 > 1.0:
		return _polar(year, month, day, lat, lon, decl, eot, false,
				"极夜：太阳整日不升（ha0 无解，cos(ha0)>1）")
	if cos_ha0 < -1.0:
		return _polar(year, month, day, lat, lon, decl, eot, true,
				"极昼：太阳整日不落（ha0 无解，cos(ha0)<−1）")

	var ha0 := rad_to_deg(acos(cos_ha0))
	var noon_h := noon_min / 60.0
	var rise_h := noon_h - ha0 / 15.0
	var rise_day_shift := 0
	if rise_h < 0.0:
		rise_h += 24.0
		rise_day_shift = -1  # 日出在前一 UTC 日
	var set_h := noon_h + ha0 / 15.0
	var set_day_shift := 0
	if set_h >= 24.0:
		set_h -= 24.0
		set_day_shift = 1     # 日落在后一 UTC 日
	var daylen := 2.0 * ha0 / 15.0

	var value := {
		"ha0_deg": ha0,             # 半昼长（日出/日落时角绝对值）
		"decl_deg": decl,           # 太阳赤纬（中天时刻）
		"eot_min": eot,             # 均时差（中天时刻，分钟）
		"noon_utc_h": fmod(noon_h, 24.0),
		"sunrise_utc_h": rise_h,
		"sunset_utc_h": set_h,
		"daylen_h": daylen,
	}
	var shift_note := ""
	if rise_day_shift != 0:
		value["sunrise_day_shift"] = rise_day_shift
		shift_note = "日出在 %s UTC 日" % ("前一" if rise_day_shift < 0 else "后一")
	if set_day_shift != 0:
		value["sunset_day_shift"] = set_day_shift
	if has_tz:
		value["sunrise_local_h"] = fmod(rise_h + tz + 24.0, 24.0)
		value["sunset_local_h"] = fmod(set_h + tz + 24.0, 24.0)
		value["noon_local_h"] = fmod(noon_h + tz + 24.0, 24.0)

	var steps := [
		{
			"title": "1. 太阳中天时刻的赤纬与均时差（迭代一次）",
			"formula": "UTC_noon = (720 − EoT − 4λ)/60 h；δ、EoT 取中天时刻 T",
			"substitution": "初值 EoT = %.4f min → 中天 %.6f h → 重算 δ、EoT" % [eot1, (720.0 - eot1 - 4.0 * lon) / 60.0],
			"result": "δ = %+.6f°，EoT = %.4f min" % [decl, eot],
		},
		{
			"title": "2. 日出日落时角 ha0",
			"formula": "cos(ha0) = [sin(h₀) − sinφ·sinδ]/(cosφ·cosδ)，h₀ = %.3f°" % h0,
			"substitution": "cos(ha0) = (%.9f − %.9f)/%.9f = %.9f" % [sin(deg_to_rad(h0)), sin(phi) * sin(sd), cos(phi) * cd, cos_ha0],
			"result": "ha0 = %.6f°" % ha0,
		},
		{
			"title": "3. 日出日落时刻与昼长",
			"formula": "UTC_rise = noon − ha0/15；UTC_set = noon + ha0/15；昼长 = 2·ha0/15",
			"substitution": "noon = %.6f h，ha0/15 = %.6f h" % [noon_h, ha0 / 15.0],
			"result": "日出 %.4f h，日落 %.4f h（UTC%s），昼长 %.4f h" % [rise_h, set_h, shift_note, daylen],
		},
		{
			"title": "4. 判据核验",
			"formula": "日出时刻太阳地平高度应 ≈ h₀（含折光与视半径）",
			"substitution": "以 ha0 代入 sin(h) = sinφ·sinδ + cosφ·cosδ·cos(−ha0)",
			"result": "h = %.4f° ≈ h₀ = %.3f° ✓" % [rad_to_deg(asin(sin(phi) * sin(sd) + cos(phi) * cd * cos(deg_to_rad(-ha0)))), h0],
		},
	]
	var formula := "日出日落 ha0 法（h₀=−0.833° 综合折光与视半径）；δ/EoT 取中天时刻，适用 1901-2099 年"
	if shift_note != "":
		formula += "；" + shift_note
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 极昼/极夜：ok=true 但无日出现象，value 中 polar=true 标记
static func _polar(year: int, month: int, day: int, lat: float, lon: float,
		decl: float, eot: float, polar_day: bool, msg: String) -> Dictionary:
	var value := {
		"polar": true,
		"polar_day": polar_day,
		"decl_deg": decl,
		"eot_min": eot,
	}
	return {"ok": true, "value": value, "steps": [
		{"title": "极昼/极夜判别", "formula": "cos(ha0) = [sin(h₀) − sinφ·sinδ]/(cosφ·cosδ)",
			"substitution": "纬度 φ = %.4f°，δ = %+.4f°" % [lat, decl], "result": msg},
	], "formula": "ha0 法极区判别（|cos(ha0)|>1 时无日出日落）", "error": ""}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
