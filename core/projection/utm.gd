# core/projection/utm.gd —— GK-M3-3 通用横轴墨卡托 UTM（A7，DMA TM 8358.2 / EPSG 9807 族，k0=0.9996）
#
# 约定：k0=0.9996，FE=500000，北半球 FN=0、南半球 FN=10,000,000；带号 n = int((L+180)/6)+1（1..60）。
# 自动选带含 DMA 标准例外：挪威（56°≤B<64°，3°≤L<12° → 32 带）、斯瓦尔巴
# （72°≤B<84°：0-9°→31，9-21°→33，21-33°→35，33-42°→37）。
# 计算引擎复用 GKGaussKruger（本会话与 pyproj 全精度复核一致）。
# 本会话核对：19N (43.642556,-70.252228)→(399002.5708,4832935.3412)；56S 悉尼→(334181.6857,6251056.0164)；
# 38N International (73,45)→(500000.0000,8100702.8967)（DMA 表 2-11 ID1 = 8100702.90）。
class_name GKUtm
extends RefCounted
const _GK := preload("res://core/projection/gauss_kruger.gd")
const _EL := preload("res://core/ellipsoid/ellipsoid.gd")
const _AN := preload("res://core/math/angles.gd")

const K0 := 0.9996
const FE := 500000.0
const FN_NORTH := 0.0
const FN_SOUTH := 10000000.0

## UTM 带号（不考虑挪威/斯瓦尔巴例外）：n = int((L+180)/6)+1，限 1..60
static func zone_from_lon(lon_deg: float) -> int:
	# 归一到 [-180, 180]：-180 归 1 带（[-180,-174)），+180 归 60 带（[174,180]）
	var l := fmod(lon_deg, 360.0)
	if l > 180.0:
		l -= 360.0
	elif l < -180.0:
		l += 360.0
	var n := int(floor((l + 180.0) / 6.0)) + 1
	return clampi(n, 1, 60)

## DMA 标准自动选带（含挪威/斯瓦尔巴例外）
static func standard_zone(lat_deg: float, lon_deg: float) -> int:
	var l := fmod(lon_deg, 360.0)
	if l <= -180.0:
		l += 360.0
	elif l > 180.0:
		l -= 360.0
	# 挪威：56°≤B<64°，3°≤L<12° → 32 带
	if lat_deg >= 56.0 and lat_deg < 64.0 and l >= 3.0 and l < 12.0:
		return 32
	# 斯瓦尔巴：72°≤B<84°
	if lat_deg >= 72.0 and lat_deg < 84.0:
		if l >= 0.0 and l < 9.0:
			return 31
		elif l >= 9.0 and l < 21.0:
			return 33
		elif l >= 21.0 and l < 33.0:
			return 35
		elif l >= 33.0 and l < 42.0:
			return 37
	return zone_from_lon(l)

## 带号中央子午线 L0 = 6n - 183
static func cm(zone: int) -> float:
	return 6.0 * zone - 183.0

## §5 协议正算。p: {lat_deg/lat_dms, lon_deg/lon_dms, zone?（空则自动）, datum?, force_standard_zone?}
## value: {e_m, n_m, zone, l0_deg, hemisphere, datum}
static func forward(p: Dictionary) -> Dictionary:
	var lat := _num(p, "lat_deg", "lat_dms")
	var lon := _num(p, "lon_deg", "lon_dms")
	if is_nan(lat):
		if is_nan(lon):
			return _err("纬度/经度不是有效数字（可接受十进制度或度分秒文本）")
		return _err("纬度不是有效数字")
	if is_nan(lon):
		return _err("经度不是有效数字")
	if absf(lat) >= 90.0:
		return _err("纬度超出 ±90°")
	if lat >= 84.0 or lat < -80.0:
		return _err("纬度 %s 超出 UTM 域（-80° ≤ B < 84°），极区请改用 UPS 投影" % String.num(lat, 4))
	var ell := _resolve_ell(p)
	if ell.is_empty():
		return _ell_error(String(p.get("datum", "WGS84")))
	var zone := 0
	var auto := true
	if p.has("zone") and not String(_sv(p, "zone")).strip_edges().is_empty():
		var z := _f(p, "zone", NAN)
		if is_nan(z) or int(z) != z or z < 1 or z > 60:
			return _err("带号应为 1..60 的整数（留空则自动选带）")
		zone = int(z)
		auto = false
	else:
		zone = standard_zone(lat, lon)
	var l0 := cm(zone)
	var fn := FN_NORTH if lat >= 0.0 else FN_SOUTH
	var r := _GK.fwd(lat, lon, l0, ell, K0, FE, fn)
	if r.is_empty():
		return _err("正算失败：点距中央子午线 %.1f° 过远" % (absf(lon - l0)))
	var value := {
		"e_m": r["y_m"], "n_m": r["x_m"],
		"zone": zone, "l0_deg": l0,
		"hemisphere": "N" if lat >= 0.0 else "S",
		"fn_m": fn,
		"datum": String(p.get("datum", "WGS84")),
		"zone_auto": auto,
	}
	var steps := [
		{"title": "1. 选带与参数", "formula": "带号 n=int((L+180)/6)+1（含挪威/斯瓦尔巴例外），L0=6n-183，k0=0.9996，FE=500km",
			"substitution": "B=%s°，L=%s°" % [String.num(lat, 6), String.num(lon, 6)],
			"result": "带号=%d%s，L0=%.1f°，半球=%s（FN=%.0f m）" % [zone, "（自动）" if auto else "（指定）", l0, "北" if lat >= 0.0 else "南", fn]},
		{"title": "2. 横轴墨卡托正算（复用高斯级数）", "formula": "E = FE + k0·[N·cosB·l + N/6·cos³B·(1-t²+η²)·l³ + …]，N = FN + k0·[X + N/2·t·cos²B·l² + …]",
			"substitution": "l=%.8f°，datum=%s" % [rad_to_deg(r["l_rad"]), String(p.get("datum", "WGS84"))],
			"result": "E=%.4f m，N=%.4f m" % [r["y_m"], r["x_m"]]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "UTM 正算（k0=0.9996，FE=500km，南半球 FN=10,000km；DMA TM 8358.2）",
			"error": ""}

## §5 协议反算。p: {zone, hemisphere ("N"/"S"/"北"/"南"), e_m, n_m, datum?}
static func inverse(p: Dictionary) -> Dictionary:
	var zone := _f(p, "zone", NAN)
	if is_nan(zone) or int(zone) != zone or zone < 1 or zone > 60:
		return _err("带号应为 1..60 的整数")
	var h := String(_sv(p, "hemisphere")).strip_edges().to_lower()
	if h.is_empty():
		return _err("缺少半球（N/S 或 北/南）")
	var north := false
	if h == "n" or h == "北" or h == "north":
		north = true
	elif h == "s" or h == "南" or h == "south":
		north = false
	else:
		return _err("半球应填 N/S（或 北/南）")
	var e := _f(p, "e_m", NAN)
	var n := _f(p, "n_m", NAN)
	if is_nan(e) or is_nan(n):
		return _err("E/N 不是有效数字")
	var ell := _resolve_ell(p)
	if ell.is_empty():
		return _ell_error(String(p.get("datum", "WGS84")))
	var l0 := cm(int(zone))
	var fn := FN_NORTH if north else FN_SOUTH
	var r := _GK.inv(n, e, l0, ell, K0, FE, fn)
	if r.is_empty():
		return _err("反算失败：坐标超出该带适用范围或参数非法")
	var lat: float = r["lat_deg"]
	var value := {
		"lat_deg": lat, "lon_deg": r["lon_deg"],
		"lat_dms": _AN.deg_to_dms_str(lat, 3),
		"lon_dms": _AN.deg_to_dms_str(r["lon_deg"], 3),
		"zone": int(zone), "l0_deg": l0,
		"hemisphere": "N" if north else "S",
		"datum": String(p.get("datum", "WGS84")),
	}
	var steps := [
		{"title": "1. 去假坐标", "formula": "x=(N-FN)/k0，y=(E-FE)/k0",
			"substitution": "带号=%d，L0=%.1f°，半球=%s" % [int(zone), l0, "北" if north else "南"],
			"result": "x=%.4f m，y=%.4f m" % [(n - fn) / K0, (e - FE) / K0]},
		{"title": "2. 横轴墨卡托反算", "formula": "μ1 迭代底点纬度 → 级数求 B、l → Newton 精化",
			"substitution": "x=%.4f m，y=%.4f m" % [(n - fn) / K0, (e - FE) / K0],
			"result": "B=%.8f°，L=%.8f°" % [r["lat_deg"], r["lon_deg"]]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "UTM 反算（k0=0.9996，引擎与 pyproj 全精度复核一致）",
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

static func _sv(p: Dictionary, key: String) -> String:
	return str(p.get(key, "")) if p.has(key) else ""

static func _resolve_ell(p: Dictionary) -> Dictionary:
	var datum := _GK.resolve_datum(String(p.get("datum", "WGS84")))
	return _EL.params(datum)

static func _ell_error(datum: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "UTM 投影",
			"error": "未知的椭球/基准「%s」。可用：%s" % [datum, ", ".join(_EL.list_builtin())]}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "UTM 投影（k0=0.9996）", "error": msg}
