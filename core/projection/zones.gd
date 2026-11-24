# core/projection/zones.gd —— GK-M3-2 投影分带工具（A4 3°/6° 换带 + A5 带号/中央子午线/y 前缀查询）
#
# 约定（中国测量惯例）：
#   - 6° 带：带号 n 从 0° 经线起东向编号，第 n 带跨 [6(n-1), 6n)，中央子午线 L0 = 6n - 3；
#   - 3° 带：中央子午线 L0 = 3n，第 n 带跨 [3n-1.5, 3n+1.5)，边界整 1.5° 归东带；
#   - 横坐标 y 前缀：y_通用 = 带号×10⁶ + (500 km + 自然 y)（自然 y 东正西负）；
#   - EPSG 码表：全部 66 行经 pyproj 3.8.0（内置官方 EPSG 数据库）逐条核读
#     （4491-4554 / 21413-21423+21453-21463 / 2401-2442 / 2327-2390；21424-21452 在 EPSG 中不存在）。
#     注意：EPSG "zone N" 系列为带号前缀（FE=N×10⁶+500000），"CM xx°E" 系列为自然 y（FE=500000）。
# 换带限差（A4）：3° 带换带要求目标点距新中央子午线 ≤3.5°，超限返回中文提示改用 6° 带。
class_name GKZones
extends RefCounted
const _GK := preload("res://core/projection/gauss_kruger.gd")
const _EL := preload("res://core/ellipsoid/ellipsoid.gd")

const BAND_LIMIT_DEG := 3.5  # 3° 带换带限界（距中央子午线）

# 带号口径区分（易混淆点，两套编号体系并存）：
#   中国 3°/6° 带（本文件主口径）：
#     6° 带号 n 自 0° 经线起东向编号（中国境内 13..23），L0 = 6n−3；
#     3° 带号 n 自 1.5°E 起东向编号（中国境内 25..45），L0 = 3n；
#     y 前缀口径 y_通用 = n×10⁶ + (500 km + 自然 y)，n 直接冠于 y 前（如 39617474.9）。
#   UTM 带（UTM 1..60，见 utm.gd）：6° 带号 1..60 自 180°W 起东向编号，
#     L0 = 6n−183，k0=0.9996；南半球 FN=10000000。UTM 带号与中国 6° 带号
#     数值上差 12（如 UTM 50 CM=117°E 对应中国 6° 带 20），两口径不可混写。
#   EPSG 码表两套系列并存："zone N" 系列横坐标含带号前缀（FE=N×10⁶+500000），
#     "CM xx°E" 系列为自然 y（FE=500000），见下方 EPSG_ROWS 的 y_prefix_zone 标志。

# ---------- 带号与中央子午线（A5） ----------

## 经度 → 6° 带号（中国惯例 n=floor(L/6)+1，西经为 0/负带号，数学上自洽）
static func zone6_from_lon(lon_deg: float) -> int:
	var l := _norm_lon(lon_deg)
	return int(floor(l / 6.0)) + 1

## 经度 → 3° 带号（n=floor(L/3+0.5)，边界整 1.5° 归东带）
static func zone3_from_lon(lon_deg: float) -> int:
	var l := _norm_lon(lon_deg)
	return int(floor(l / 3.0 + 0.5))

## 6° 带中央子午线 L0 = 6n - 3
static func cm6(zone: int) -> float:
	return 6.0 * zone - 3.0

## 3° 带中央子午线 L0 = 3n
static func cm3(zone: int) -> float:
	return 3.0 * zone

## 自然 y（含 500 km 假东）→ 加带号前缀：y_通用 = zone×10⁶ + y_自然
static func y_with_prefix(y_natural: float, zone: int) -> float:
	return zone * 1000000.0 + y_natural

## 带号前缀 y → {zone, y_natural}
static func split_prefix_y(y_prefixed: float) -> Dictionary:
	var zone := int(floor(y_prefixed / 1000000.0))
	return {"zone": zone, "y_natural": y_prefixed - zone * 1000000.0}

## 经度所在带的全部查询结果（A5）
## 返回 {zone6, l0_6, zone3, l0_3, l_deg, band3_valid, band6_valid}
static func query(lon_deg: float) -> Dictionary:
	if not is_finite(lon_deg) or absf(lon_deg) > 180.0:
		return {}
	var z6 := zone6_from_lon(lon_deg)
	var z3 := zone3_from_lon(lon_deg)
	var l6 := cm6(z6)
	var l3 := cm3(z3)
	return {
		"zone6": z6, "l0_6": l6,
		"zone3": z3, "l0_3": l3,
		"l_deg": _norm_lon(lon_deg),
		"band3_valid": absf(_norm_lon(lon_deg) - l3) <= BAND_LIMIT_DEG,
		"band6_valid": true,
	}

# ---------- A4 换带（反算 → 经纬度 → 新带正算） ----------

## p: {x_m, y_m, l0_from_deg, datum?, to_band ("3"/"6"), to_zone?（缺省自动）, k0?, fe_m?}
## 返回 §5 协议。value: {x_m, y_m, zone, l0_deg, lat_deg, lon_deg, band}。
static func switch_zone(p: Dictionary) -> Dictionary:
	var x := _f(p, "x_m", NAN)
	var y := _f(p, "y_m", NAN)
	var l0_from := _f(p, "l0_from_deg", NAN)
	if is_nan(x) or is_nan(y) or is_nan(l0_from):
		return _err("x_m/y_m/l0_from_deg 不是有效数字（换带需提供原带坐标与原中央子午线）")
	var datum := String(p.get("datum", "CGCS2000"))
	var ell := _GK.resolve_datum(datum)
	var ellp := _EL.params(ell)
	if ellp.is_empty():
		return _err("未知的椭球/基准「%s」。可用：%s" % [datum, ", ".join(_EL.list_builtin())])
	var k0 := _f(p, "k0", 1.0)
	var fe := _f(p, "fe_m", 500000.0)
	var fn := _f(p, "fn_m", 0.0)
	var inv_r := _GK.inv(x, y, l0_from, ellp, k0, fe, fn)
	if inv_r.is_empty():
		return _err("原坐标反算失败：请检查 x/y 是否为该中央子午线（L0=%.1f°）下的高斯坐标" % l0_from)
	var lat: float = inv_r["lat_deg"]
	var lon: float = inv_r["lon_deg"]
	var band := String(p.get("to_band", "3")).strip_edges()
	var zone := 0
	var l0_to := NAN
	if p.has("to_zone"):
		var tz := _f(p, "to_zone", NAN)
		if is_nan(tz) or int(tz) != tz or tz == 0:
			return _err("to_zone 应为非零整数带号")
		zone = int(tz)
		l0_to = cm3(zone) if band != "6" else cm6(zone)
	else:
		if band == "6":
			zone = zone6_from_lon(lon)
			l0_to = cm6(zone)
		else:
			zone = zone3_from_lon(lon)
			l0_to = cm3(zone)
	var off := absf(_norm_lon(lon) - l0_to)
	var warn := ""
	if off > BAND_LIMIT_DEG and band != "6":
		return _err("目标点距 3° 带中央子午线 %.2f°，超过 %.1f° 换带限界，建议改用 6° 带（L0=%.1f°）" % [off, BAND_LIMIT_DEG, cm6(zone6_from_lon(lon))])
	if off > BAND_LIMIT_DEG and band == "6":
		warn = "距 6° 带中央子午线 %.2f°（>%.1f°），边缘精度渐降，建议就近换带" % [off, BAND_LIMIT_DEG]
	var fwd_r := _GK.fwd(lat, lon, l0_to, ellp, k0, fe, fn)
	if fwd_r.is_empty():
		return _err("新带正算失败：点距新中央子午线过远（%.2f°）" % off)
	var value := {
		"x_m": fwd_r["x_m"], "y_m": fwd_r["y_m"],
		"zone": zone, "l0_deg": l0_to,
		"lat_deg": lat, "lon_deg": lon,
		"l0_from_deg": l0_from,
		"y_prefixed": y_with_prefix(fwd_r["y_m"], zone),
		"datum": datum,
	}
	var steps := [
		{"title": "1. 原带反算", "formula": "（x, y, L0原）→（B, L）",
			"substitution": "x=%.4f m，y=%.4f m，L0=%.1f°，datum=%s" % [x, y, l0_from, datum],
			"result": "B=%.8f°，L=%.8f°" % [lat, lon]},
		{"title": "2. 确定新带", "formula": "3° 带 L0=3n；6° 带 L0=6n-3",
			"substitution": "to_band=%s，L=%.6f°" % [band, lon],
			"result": "新带 n=%d，L0=%.1f°，距中央子午线 %.3f°" % [zone, l0_to, off]},
		{"title": "3. 新带正算", "formula": "（B, L，L0新）→（x, y）",
			"substitution": "B=%.8f°，L=%.8f°，L0=%.1f°" % [lat, lon, l0_to],
			"result": "x=%.4f m，y=%.4f m（带号前缀 y=%.3f）" % [fwd_r["x_m"], fwd_r["y_m"], y_with_prefix(fwd_r["y_m"], zone)]},
	]
	if warn != "":
		steps.append({"title": "4. 精度提示", "formula": "", "substitution": "", "result": warn})
	return {"ok": true, "value": value, "steps": steps,
			"formula": "换带计算：反算 → 经纬度 → 新带正算（%s；换带限界 ±%.1f°）" % ["6° 带" if band == "6" else "3° 带", BAND_LIMIT_DEG],
			"error": ""}

# ---------- EPSG 带号表（pyproj 3.8.0 官方 EPSG 数据库逐条核读，2026-11） ----------
# 行：datum, kind（GK6/GK3）, zone, l0_deg, epsg, y_prefix_zone（EPSG "zone N"=true 带前缀；"CM xxE"=false）

const EPSG_ROWS := [
	{"datum": "CGCS2000", "kind": "GK6", "zone": 13, "l0_deg": 75, "epsg": 4491, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 14, "l0_deg": 81, "epsg": 4492, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 15, "l0_deg": 87, "epsg": 4493, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 16, "l0_deg": 93, "epsg": 4494, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 17, "l0_deg": 99, "epsg": 4495, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 18, "l0_deg": 105, "epsg": 4496, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 19, "l0_deg": 111, "epsg": 4497, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 20, "l0_deg": 117, "epsg": 4498, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 21, "l0_deg": 123, "epsg": 4499, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 22, "l0_deg": 129, "epsg": 4500, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 23, "l0_deg": 135, "epsg": 4501, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 13, "l0_deg": 75, "epsg": 4502, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 14, "l0_deg": 81, "epsg": 4503, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 15, "l0_deg": 87, "epsg": 4504, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 16, "l0_deg": 93, "epsg": 4505, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 17, "l0_deg": 99, "epsg": 4506, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 18, "l0_deg": 105, "epsg": 4507, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 19, "l0_deg": 111, "epsg": 4508, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 20, "l0_deg": 117, "epsg": 4509, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 21, "l0_deg": 123, "epsg": 4510, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 22, "l0_deg": 129, "epsg": 4511, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK6", "zone": 23, "l0_deg": 135, "epsg": 4512, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 25, "l0_deg": 75, "epsg": 4513, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 26, "l0_deg": 78, "epsg": 4514, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 27, "l0_deg": 81, "epsg": 4515, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 28, "l0_deg": 84, "epsg": 4516, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 29, "l0_deg": 87, "epsg": 4517, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 30, "l0_deg": 90, "epsg": 4518, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 31, "l0_deg": 93, "epsg": 4519, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 32, "l0_deg": 96, "epsg": 4520, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 33, "l0_deg": 99, "epsg": 4521, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 34, "l0_deg": 102, "epsg": 4522, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 35, "l0_deg": 105, "epsg": 4523, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 36, "l0_deg": 108, "epsg": 4524, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 37, "l0_deg": 111, "epsg": 4525, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 38, "l0_deg": 114, "epsg": 4526, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 39, "l0_deg": 117, "epsg": 4527, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 40, "l0_deg": 120, "epsg": 4528, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 41, "l0_deg": 123, "epsg": 4529, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 42, "l0_deg": 126, "epsg": 4530, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 43, "l0_deg": 129, "epsg": 4531, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 44, "l0_deg": 132, "epsg": 4532, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 45, "l0_deg": 135, "epsg": 4533, "y_prefix_zone": true},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 25, "l0_deg": 75, "epsg": 4534, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 26, "l0_deg": 78, "epsg": 4535, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 27, "l0_deg": 81, "epsg": 4536, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 28, "l0_deg": 84, "epsg": 4537, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 29, "l0_deg": 87, "epsg": 4538, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 30, "l0_deg": 90, "epsg": 4539, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 31, "l0_deg": 93, "epsg": 4540, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 32, "l0_deg": 96, "epsg": 4541, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 33, "l0_deg": 99, "epsg": 4542, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 34, "l0_deg": 102, "epsg": 4543, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 35, "l0_deg": 105, "epsg": 4544, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 36, "l0_deg": 108, "epsg": 4545, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 37, "l0_deg": 111, "epsg": 4546, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 38, "l0_deg": 114, "epsg": 4547, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 39, "l0_deg": 117, "epsg": 4548, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 40, "l0_deg": 120, "epsg": 4549, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 41, "l0_deg": 123, "epsg": 4550, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 42, "l0_deg": 126, "epsg": 4551, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 43, "l0_deg": 129, "epsg": 4552, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 44, "l0_deg": 132, "epsg": 4553, "y_prefix_zone": false},
	{"datum": "CGCS2000", "kind": "GK3", "zone": 45, "l0_deg": 135, "epsg": 4554, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 13, "l0_deg": 75, "epsg": 21413, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 14, "l0_deg": 81, "epsg": 21414, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 15, "l0_deg": 87, "epsg": 21415, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 16, "l0_deg": 93, "epsg": 21416, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 17, "l0_deg": 99, "epsg": 21417, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 18, "l0_deg": 105, "epsg": 21418, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 19, "l0_deg": 111, "epsg": 21419, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 20, "l0_deg": 117, "epsg": 21420, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 21, "l0_deg": 123, "epsg": 21421, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 22, "l0_deg": 129, "epsg": 21422, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 23, "l0_deg": 135, "epsg": 21423, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK6", "zone": 13, "l0_deg": 75, "epsg": 21453, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 14, "l0_deg": 81, "epsg": 21454, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 15, "l0_deg": 87, "epsg": 21455, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 16, "l0_deg": 93, "epsg": 21456, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 17, "l0_deg": 99, "epsg": 21457, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 18, "l0_deg": 105, "epsg": 21458, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 19, "l0_deg": 111, "epsg": 21459, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 20, "l0_deg": 117, "epsg": 21460, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 21, "l0_deg": 123, "epsg": 21461, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 22, "l0_deg": 129, "epsg": 21462, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK6", "zone": 23, "l0_deg": 135, "epsg": 21463, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 25, "l0_deg": 75, "epsg": 2401, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 26, "l0_deg": 78, "epsg": 2402, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 27, "l0_deg": 81, "epsg": 2403, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 28, "l0_deg": 84, "epsg": 2404, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 29, "l0_deg": 87, "epsg": 2405, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 30, "l0_deg": 90, "epsg": 2406, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 31, "l0_deg": 93, "epsg": 2407, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 32, "l0_deg": 96, "epsg": 2408, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 33, "l0_deg": 99, "epsg": 2409, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 34, "l0_deg": 102, "epsg": 2410, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 35, "l0_deg": 105, "epsg": 2411, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 36, "l0_deg": 108, "epsg": 2412, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 37, "l0_deg": 111, "epsg": 2413, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 38, "l0_deg": 114, "epsg": 2414, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 39, "l0_deg": 117, "epsg": 2415, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 40, "l0_deg": 120, "epsg": 2416, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 41, "l0_deg": 123, "epsg": 2417, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 42, "l0_deg": 126, "epsg": 2418, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 43, "l0_deg": 129, "epsg": 2419, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 44, "l0_deg": 132, "epsg": 2420, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 45, "l0_deg": 135, "epsg": 2421, "y_prefix_zone": true},
	{"datum": "北京54", "kind": "GK3", "zone": 25, "l0_deg": 75, "epsg": 2422, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 26, "l0_deg": 78, "epsg": 2423, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 27, "l0_deg": 81, "epsg": 2424, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 28, "l0_deg": 84, "epsg": 2425, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 29, "l0_deg": 87, "epsg": 2426, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 30, "l0_deg": 90, "epsg": 2427, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 31, "l0_deg": 93, "epsg": 2428, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 32, "l0_deg": 96, "epsg": 2429, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 33, "l0_deg": 99, "epsg": 2430, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 34, "l0_deg": 102, "epsg": 2431, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 35, "l0_deg": 105, "epsg": 2432, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 36, "l0_deg": 108, "epsg": 2433, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 37, "l0_deg": 111, "epsg": 2434, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 38, "l0_deg": 114, "epsg": 2435, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 39, "l0_deg": 117, "epsg": 2436, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 40, "l0_deg": 120, "epsg": 2437, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 41, "l0_deg": 123, "epsg": 2438, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 42, "l0_deg": 126, "epsg": 2439, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 43, "l0_deg": 129, "epsg": 2440, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 44, "l0_deg": 132, "epsg": 2441, "y_prefix_zone": false},
	{"datum": "北京54", "kind": "GK3", "zone": 45, "l0_deg": 135, "epsg": 2442, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 13, "l0_deg": 75, "epsg": 2327, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 14, "l0_deg": 81, "epsg": 2328, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 15, "l0_deg": 87, "epsg": 2329, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 16, "l0_deg": 93, "epsg": 2330, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 17, "l0_deg": 99, "epsg": 2331, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 18, "l0_deg": 105, "epsg": 2332, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 19, "l0_deg": 111, "epsg": 2333, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 20, "l0_deg": 117, "epsg": 2334, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 21, "l0_deg": 123, "epsg": 2335, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 22, "l0_deg": 129, "epsg": 2336, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 23, "l0_deg": 135, "epsg": 2337, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK6", "zone": 13, "l0_deg": 75, "epsg": 2338, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 14, "l0_deg": 81, "epsg": 2339, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 15, "l0_deg": 87, "epsg": 2340, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 16, "l0_deg": 93, "epsg": 2341, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 17, "l0_deg": 99, "epsg": 2342, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 18, "l0_deg": 105, "epsg": 2343, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 19, "l0_deg": 111, "epsg": 2344, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 20, "l0_deg": 117, "epsg": 2345, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 21, "l0_deg": 123, "epsg": 2346, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 22, "l0_deg": 129, "epsg": 2347, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK6", "zone": 23, "l0_deg": 135, "epsg": 2348, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 25, "l0_deg": 75, "epsg": 2349, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 26, "l0_deg": 78, "epsg": 2350, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 27, "l0_deg": 81, "epsg": 2351, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 28, "l0_deg": 84, "epsg": 2352, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 29, "l0_deg": 87, "epsg": 2353, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 30, "l0_deg": 90, "epsg": 2354, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 31, "l0_deg": 93, "epsg": 2355, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 32, "l0_deg": 96, "epsg": 2356, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 33, "l0_deg": 99, "epsg": 2357, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 34, "l0_deg": 102, "epsg": 2358, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 35, "l0_deg": 105, "epsg": 2359, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 36, "l0_deg": 108, "epsg": 2360, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 37, "l0_deg": 111, "epsg": 2361, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 38, "l0_deg": 114, "epsg": 2362, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 39, "l0_deg": 117, "epsg": 2363, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 40, "l0_deg": 120, "epsg": 2364, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 41, "l0_deg": 123, "epsg": 2365, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 42, "l0_deg": 126, "epsg": 2366, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 43, "l0_deg": 129, "epsg": 2367, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 44, "l0_deg": 132, "epsg": 2368, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 45, "l0_deg": 135, "epsg": 2369, "y_prefix_zone": true},
	{"datum": "西安80", "kind": "GK3", "zone": 25, "l0_deg": 75, "epsg": 2370, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 26, "l0_deg": 78, "epsg": 2371, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 27, "l0_deg": 81, "epsg": 2372, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 28, "l0_deg": 84, "epsg": 2373, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 29, "l0_deg": 87, "epsg": 2374, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 30, "l0_deg": 90, "epsg": 2375, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 31, "l0_deg": 93, "epsg": 2376, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 32, "l0_deg": 96, "epsg": 2377, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 33, "l0_deg": 99, "epsg": 2378, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 34, "l0_deg": 102, "epsg": 2379, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 35, "l0_deg": 105, "epsg": 2380, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 36, "l0_deg": 108, "epsg": 2381, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 37, "l0_deg": 111, "epsg": 2382, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 38, "l0_deg": 114, "epsg": 2383, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 39, "l0_deg": 117, "epsg": 2384, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 40, "l0_deg": 120, "epsg": 2385, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 41, "l0_deg": 123, "epsg": 2386, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 42, "l0_deg": 126, "epsg": 2387, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 43, "l0_deg": 129, "epsg": 2388, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 44, "l0_deg": 132, "epsg": 2389, "y_prefix_zone": false},
	{"datum": "西安80", "kind": "GK3", "zone": 45, "l0_deg": 135, "epsg": 2390, "y_prefix_zone": false},
]

## 按条件查 EPSG 码：epsg_of("CGCS2000", "3", 39, true) → 4527；找不到返回 0。
static func epsg_of(datum: String, band: String, zone: int, y_prefixed: bool) -> int:
	var want: String = {"CGCS2000": "CGCS2000", "北京54": "北京54", "西安80": "西安80"}.get(datum, datum)
	for row: Dictionary in EPSG_ROWS:
		if String(row["datum"]) == want and String(row["kind"]) == ("GK6" if band == "6" else "GK3") \
				and int(row["zone"]) == zone and bool(row["y_prefix_zone"]) == y_prefixed:
			return int(row["epsg"])
	return 0

## 全部 EPSG 行（只读副本）
static func epsg_rows() -> Array:
	return EPSG_ROWS.duplicate(true)

# ---------- 内部 ----------

static func _norm_lon(lon_deg: float) -> float:
	var l := fmod(lon_deg, 360.0)
	if l <= -180.0:
		l += 360.0
	elif l > 180.0:
		l -= 360.0
	return l

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
	return {"ok": false, "value": {}, "steps": [], "formula": "高斯投影换带与分带查询", "error": msg}
