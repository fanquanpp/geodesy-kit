# core/astro/time_sys.gd —— GK-M8-4（F6）时间系统：UTC↔儒略日↔GPS 时↔年积日
#
# 口径（ARCHITECTURE.md §4 GK-M8 F6）：
#   - 儒略日 JD：格里历算法（与 GKSolar.calc_jd 同源），权威常数 JD(2000-01-01 12:00 UT)=2451545.0；
#   - GPS 周起点 1980-01-06 00:00 UTC（JD = 2444244.5），周号自该日起连续计数
#     （1024 周滚转只是接收机 10bit 表示问题，本模块输出连续周号）；
#   - 周内秒 SOW 按纯 UTC 连续秒对齐周起点（与权威构造向量口径一致：2024-06-21 00:00
#     UTC → 周 2319、SOW 432000 s）；另附 GPS−UTC 秒差（累计闰秒，GPS 时 = UTC + 闰秒）
#     供需要 GPS 时标度的场景换算；
#   - 闰秒表为 IERS Bulletin C 公开数据（1981-07-01 起至 2017-01-01 共 18 秒，
#     其后 IERS 公告未新增；如遇新增需更新表——不静默假定）；
#   - 年积日 DOY：1 月 1 日 = 1，闰年 2 月 29 天。
class_name GKTimeSys
extends RefCounted

const GPS_EPOCH_JD := 2444244.5          # 1980-01-06 00:00 UTC
const GPS_EPOCH_YMD := [1980, 1, 6]
const MJD_OFFSET := 2400000.5
const WEEK_SECONDS := 604800.0
const GPS_LEAP_OFFSET := 19.0            # GPS 时 = TAI − 19 s

# 闰秒表：[生效儒略日（UTC 当日 0h）, 该时刻起 TAI−UTC 累计秒]
# （JD 值由格里历算法程序化生成，与 GKSolar.calc_jd 同一公式，非手抄）
const LEAP_TABLE := [
	[2444786.5, 1.0],   # 1981-07-01
	[2445151.5, 2.0],   # 1982-07-01
	[2445516.5, 3.0],   # 1983-07-01
	[2446247.5, 4.0],   # 1985-07-01
	[2447161.5, 5.0],   # 1988-01-01
	[2447892.5, 6.0],   # 1990-01-01
	[2448257.5, 7.0],   # 1991-01-01
	[2448804.5, 8.0],   # 1992-07-01
	[2449169.5, 9.0],   # 1993-07-01
	[2449534.5, 10.0],  # 1994-07-01
	[2450083.5, 11.0],  # 1996-01-01
	[2450630.5, 12.0],  # 1997-07-01
	[2451179.5, 13.0],  # 1999-01-01
	[2453736.5, 14.0],  # 2006-01-01
	[2454832.5, 15.0],  # 2009-01-01
	[2456109.5, 16.0],  # 2012-07-01
	[2457204.5, 17.0],  # 2015-07-01
	[2457754.5, 18.0],  # 2017-01-01
]

## 儒略日（格里历）：JD(y,m,d) + 当日小时小数
static func utc_to_jd(year: int, month: int, day: int, hour: int, minute: int, second: float) -> float:
	return GKSolar.calc_jd(year, month, day) + hour / 24.0 + minute / 1440.0 + second / 86400.0

## 儒略日 → UTC 日历（NOAA calcDateFromJD 移植）
## 返回 {ok, year, month, day, hour, minute, second}；非法返回 {ok:false}
static func jd_to_utc(jd: float) -> Dictionary:
	if not is_finite(jd) or jd < 0.0 or jd > 5373484.5:  # 1901-01-01 至 9999-12-31 量级内
		return {"ok": false, "error": "儒略日超出可换算范围（0 ~ 5373484.5）"}
	var z := floorf(jd + 0.5)
	var f := jd + 0.5 - z
	var alpha := 0.0
	if z >= 2299161.0:
		alpha = floorf((z - 1867216.25) / 36524.25)
	var a := z
	if z >= 2299161.0:
		a = z + 1.0 + alpha - floorf(alpha / 4.0)
	var b := a + 1524.0
	var c := floorf((b - 122.1) / 365.25)
	var d := floorf(365.25 * c)
	var e := floorf((b - d) / 30.6001)
	var day_frac := b - d - floorf(30.6001 * e) + f
	var day := int(floorf(day_frac))
	var month := int(e) - 1 if int(e) < 14 else int(e) - 13
	var year := int(c) - 4716 if month > 2 else int(c) - 4715
	var frac := day_frac - float(day)
	var total_sec := roundf(frac * 86400.0)
	if total_sec >= 86400.0:  # 舍入进位到次日
		total_sec -= 86400.0
		day += 1
	var hour := int(floorf(total_sec / 3600.0))
	var minute := int(floorf(fmod(total_sec, 3600.0) / 60.0))
	var second := fmod(total_sec, 60.0)
	return {"ok": true, "year": year, "month": month, "day": day,
			"hour": hour, "minute": minute, "second": second}

## 年积日（1 月 1 日 = 1，闰年含 2 月 29 日）
static func day_of_year(year: int, month: int, day: int) -> int:
	var leap := _is_leap(year)
	var dims := [31, 28 + (1 if leap else 0), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month < 1 or month > 12 or day < 1 or day > int(dims[month - 1]):
		return 0
	var doy := day
	for i in range(month - 1):
		doy += int(dims[i])
	return doy

## 该年是否闰年（格里历）
static func _is_leap(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0

## UTC 时刻的累计闰秒（TAI−UTC）。1972 前返回 0；表中未收录的过渡期不外推。
static func leap_seconds(jd: float) -> float:
	var s := 0.0
	for row: Array in LEAP_TABLE:
		if jd >= float(row[0]) - 0.5:  # 生效时刻为当日 0h UTC
			s = float(row[1])
	return s

## UTC 时刻的 GPS−UTC 秒差（GPS 时标度比 UTC 快，GPS = UTC + 闰秒）
static func gps_minus_utc(jd: float) -> float:
	return leap_seconds(jd)

## 儒略日 → GPS 周 / 周内秒（周起点 1980-01-06 00:00 UTC，连续周号）
static func gps_week_sow(jd: float) -> Dictionary:
	var dt := jd - GPS_EPOCH_JD
	if dt < 0.0:
		return {}
	var week := int(floor(dt / 7.0))
	var sow := fmod(dt, 7.0) * 86400.0
	return {"week": week, "sow_s": sow}

## 计算入口（§5 协议）：UTC 日历 → JD / MJD / 年积日 / GPS 周-周内秒 / 闰秒
## p: {year, month, day, hour, minute, second}
static func convert(p: Dictionary) -> Dictionary:
	var year := int(p.get("year", 0))
	var month := int(p.get("month", 0))
	var day := int(p.get("day", 0))
	var hour := int(p.get("hour", 0))
	var minute := int(p.get("minute", 0))
	var second := float(p.get("second", 0.0))
	if year < 1901 or year > 2099:
		return _err("年份 %d 超出适用范围（1901-2099）" % year)
	if month < 1 or month > 12:
		return _err("月份 %d 非法（应为 1-12）" % month)
	if hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0.0 or second >= 60.0:
		return _err("时间 %02d:%02d:%06.3f 非法（UTC 24 小时制）" % [hour, minute, second])
	var doy := day_of_year(year, month, day)
	if doy == 0:
		return _err("日期 %d-%02d-%02d 非法（检查闰年与每月天数）" % [year, month, day])
	var jd := utc_to_jd(year, month, day, hour, minute, second)
	var ws := gps_week_sow(jd)
	var leap := leap_seconds(jd)
	var gps_week := int(ws["week"])
	var sow := float(ws["sow_s"])
	var value := {
		"jd": jd,
		"mjd": jd - MJD_OFFSET,
		"doy": doy,
		"days_left": (366 if _is_leap(year) else 365) - doy,
		"leap_s": leap,
		"gps_minus_utc_s": leap,
		"week": gps_week,
		"sow_s": sow,
		"week_day": int(floor(sow / 86400.0)),  # 0=周日（GPS 周起点）
	}
	# GPS 时标度的周内秒（含闰秒偏移；跨周进位）
	var sow_gps := sow + leap
	var week_gps := gps_week
	if sow_gps >= WEEK_SECONDS:
		sow_gps -= WEEK_SECONDS
		week_gps += 1
	value["week_gps_time"] = week_gps
	value["sow_gps_s"] = sow_gps
	var steps := [
		{"title": "1. 儒略日与简化儒略日",
			"formula": "JD = calcJD(年,月,日) + (h+m/60+s/3600)/24；MJD = JD − 2400000.5",
			"substitution": "JD = %.1f + %.9f" % [GKSolar.calc_jd(year, month, day), (hour + minute / 60.0 + second / 60.0) / 24.0],
			"result": "JD = %.9f，MJD = %.9f" % [jd, jd - MJD_OFFSET]},
		{"title": "2. 年积日",
			"formula": "DOY = Σ(1..月−1 每月天数) + 日（闰年 2 月 29 天）",
			"substitution": "闰年规则：4 整除且非百年，或 400 整除",
			"result": "%d 年（%s）DOY = %d，年内还剩 %d 天" % [year, "闰年" if _is_leap(year) else "平年", doy, int(value["days_left"])]},
		{"title": "3. GPS 周 / 周内秒",
			"formula": "周号 = floor((JD − 2444244.5)/7)；SOW = 余数 × 86400（周起点 1980-01-06 00:00 UTC）",
			"substitution": "(JD − 2444244.5)/7 = %.9f" % ((jd - GPS_EPOCH_JD) / 7.0),
			"result": "周 %d，周内秒 %.3f s（第 %d 天，0=周日）" % [gps_week, sow, int(value["week_day"])]},
		{"title": "4. 闰秒与 GPS 时标度",
			"formula": "GPS 时 = UTC + 累计闰秒（GPS = TAI − 19 s）；TAI = UTC + 闰秒",
			"substitution": "查 IERS 闰秒表（当前累计 %.0f s）" % leap,
			"result": "GPS−UTC = %.0f s；GPS 时标度周内秒 %.3f s" % [leap, float(value["sow_gps_s"])]},
	]
	var formula := "UTC↔儒略日（格里历）↔GPS 周/周内秒↔年积日；闰秒表截至 2017-01-01（IERS 公告未再新增，落地后随公告更新）"
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
