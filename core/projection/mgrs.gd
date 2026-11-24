# core/projection/mgrs.gd —— GK-M3-6 军用网格参考系统 MGRS（A13，US NGA 标准字母方格方案）
#
# UTM 部分（−80°≤B<84°）：带号 1..60（含 32V/31X/33X/35X/37X 例外）、纬度带字母无 I/O、
# 100km 方格列/行字母按奇偶带查表，数字部分按精度位（1 位=10km … 5 位=1m）截尾。
# UPS 部分（B≥84° 或 B<−80°）：带字母北 Y/Z、南 A/B；列/行字母表与偏移按 NGA 标准查表。
# 方案经 mgrs 1.7.0 权威库逐点复核；验收向量：天安门→50SMK4796917671、北海→31UDV4268262666。
class_name GKMgrs
extends RefCounted
const _GK := preload("res://core/projection/gauss_kruger.gd")
const _UT := preload("res://core/projection/utm.gd")
const _UP := preload("res://core/projection/ups.gd")
const _EL := preload("res://core/ellipsoid/ellipsoid.gd")
const _AN := preload("res://core/math/angles.gd")

const BAND_LETTERS := "CDEFGHJKLMNPQRSTUVWX"     # UTM 纬度带（8° 一带，无 I/O）
const COL_SETS := ["ABCDEFGH", "JKLMNPQR", "STUVWXYZ"]
const ROW_ODD := "ABCDEFGHJKLMNPQRSTUV"
const ROW_EVEN := "FGHJKLMNPQRSTUVABCDE"
const UPS_COL_ALPHABET := "ABCFGHJKLMNPQRSTUXYZ"  # 24 字母表去 I/O/D/E/V/W，共 20 字母（mgrs 1.7.0 逐格核读）
const UPS_ROW_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const MAX_PREC := 5  # 1m 精度（5 位数字）

# ---------- §5 协议 ----------

## 经纬度 → MGRS。p: {lat_deg/lat_dms, lon_deg/lon_dms, precision?（1..5，默认 5=1m）, datum?}
## MGRS 按 WGS84 计算（标准约定）；datum 仅用于显示校验提示。
static func forward(p: Dictionary) -> Dictionary:
	var lat := _num(p, "lat_deg", "lat_dms")
	var lon := _num(p, "lon_deg", "lon_dms")
	if is_nan(lat) or is_nan(lon):
		return _err("纬度/经度不是有效数字（可接受十进制度或度分秒文本）")
	if absf(lat) > 90.0 or absf(lon) > 180.0:
		return _err("输入超出范围（|B|≤90°，|L|≤180°）")
	var prec := int(_f(p, "precision", MAX_PREC))
	if prec < 1 or prec > MAX_PREC:
		return _err("精度位数应为 1..%d（%d 位=1m）" % [MAX_PREC, MAX_PREC])
	var s := to_mgrs(lat, lon, prec)
	if s.is_empty():
		return _err("MGRS 编码失败：输入超出 UTM/UPS 覆盖域")
	var zone := _zone_of(lat, lon)
	var value := {
		"mgrs": s,
		"lat_deg": lat, "lon_deg": lon,
		"precision_m": pow(10.0, 5.0 - prec),
		"zone": zone,
		"band": _band_of(lat, lon),
	}
	var steps := [
		{"title": "1. 判域与带号", "formula": "UTM：-80°≤B<84°，n=int((L+180)/6)+1（含挪威/斯瓦尔巴例外）；UPS：B≥84° 或 B<-80°",
			"substitution": "B=%s°，L=%s°" % [String.num(lat, 6), String.num(lon, 6)],
			"result": ("%d 带，纬度带 %s" % [zone, _band_of(lat, lon)]) if zone > 0 else "UPS %s 区" % _band_of(lat, lon)},
		{"title": "2. 100km 方格与数字", "formula": "列/行字母查表；数字 = E、N 在 100km 方格内的坐标按精度位截尾",
			"substitution": "精度 %d 位（%s m）" % [prec, String.num(pow(10.0, 5.0 - prec), 0)],
			"result": "MGRS = " + s},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "MGRS 编码（US NGA 字母方格方案；与 mgrs 1.7.0 复核一致）",
			"error": ""}

## MGRS → 经纬度。p: {mgrs, datum?}
static func inverse(p: Dictionary) -> Dictionary:
	var s := String(p.get("mgrs", "")).strip_edges().replace(" ", "").to_upper()
	if s.is_empty():
		return _err("缺少 MGRS 字符串")
	var r := from_mgrs(s)
	if r.is_empty():
		return _err("MGRS 格式无法解析（应为 带号/带字母 + 100km 方格两位字母 + 偶数位数字，例：50SMK4796917671）")
	var value := {
		"lat_deg": r["lat_deg"], "lon_deg": r["lon_deg"],
		"lat_dms": _AN.deg_to_dms_str(r["lat_deg"], 3),
		"lon_dms": _AN.deg_to_dms_str(r["lon_deg"], 3),
		"mgrs_center": s,
	}
	var prec := int((s.length() - _prefix_len(s)) / 2)
	var note := "MGRS 网格精度 %s m，结果取方格中心（与 mgrs 1.7.0 一致；SW 角点需减半格 %.3f m）" \
			% [String.num(pow(10.0, 5.0 - prec), 0), pow(10.0, 5.0 - prec) / 2.0]
	var steps := [
		{"title": "1. 解析字母", "formula": "带号/带字母 → E/N 概域；100km 方格字母 → E100/N100",
			"substitution": "输入 = " + s,
			"result": "E≈%.0f m，N≈%.0f m" % [r["e_m"], r["n_m"]]},
		{"title": "2. 恢复经纬度", "formula": "UTM：高斯反算（k0=0.9996）；UPS：极方位反算",
			"substitution": note,
			"result": "B=%.8f°，L=%.8f°" % [r["lat_deg"], r["lon_deg"]]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "MGRS 解码（方格角点口径；与 mgrs 1.7.0 复核一致）",
			"error": ""}

# ---------- 低层编码/解码 ----------

## 经纬度 → MGRS 字符串（precision 位数字）；域外/非法返回 ""。
static func to_mgrs(lat_deg: float, lon_deg: float, prec: int = MAX_PREC) -> String:
	if prec < 1 or prec > MAX_PREC:
		return ""
	if lat_deg >= 84.0 or lat_deg < -80.0:
		# UPS 域
		var north := lat_deg >= 84.0
		if north and lat_deg > 90.0:
			return ""
		if not north and lat_deg < -90.0:
			return ""
		var ell := _EL.params("WGS84")
		var r := _UP.fwd(lat_deg, lon_deg, ell, north)
		if r.is_empty():
			return ""
		var band := ""
		if north:
			band = "Z" if lon_deg >= 0.0 else "Y"
		else:
			band = "B" if lon_deg >= 0.0 else "A"
		var e100 := int(floor(r["e_m"] / 100000.0))
		var n100 := int(floor(r["n_m"] / 100000.0))
		var col := UPS_COL_ALPHABET[(e100 - 20 + 2000) % 20]
		var row_idx := (n100 - 13 + 2400) % 24 if north else (n100 - 8 + 2400) % 24
		var row := UPS_ROW_ALPHABET[row_idx]
		return band + col + row + _digits(r["e_m"], r["n_m"], prec)
	# UTM 域
	var zone := _UT.standard_zone(lat_deg, lon_deg)
	var ell := _EL.params("WGS84")
	var fn := 0.0 if lat_deg >= 0.0 else 10000000.0
	var r := _GK.fwd(lat_deg, lon_deg, _UT.cm(zone), ell, _UT.K0, _UT.FE, fn)
	if r.is_empty():
		return ""
	var band_idx := int(floor((lat_deg + 80.0) / 8.0))
	band_idx = clampi(band_idx, 0, BAND_LETTERS.length() - 1)
	var band := BAND_LETTERS[band_idx]
	var e100 := int(floor(r["y_m"] / 100000.0))
	var n100 := int(floor(r["x_m"] / 100000.0))
	var col_set: String = COL_SETS[(zone - 1) % 3]
	var col := col_set[(e100 - 1 + 800) % 8]
	var row_set := ROW_ODD if zone % 2 == 1 else ROW_EVEN
	var row := row_set[n100 % 20]
	return "%d%s%s%s%s" % [zone, band, col, row, _digits(r["y_m"], r["x_m"], prec)]

## MGRS → {lat_deg, lon_deg, e_m, n_m, zone, north}；失败返回 {}。
static func from_mgrs(s: String) -> Dictionary:
	var t := s.strip_edges().replace(" ", "").replace("-", "").to_upper()
	if t.length() < 4:
		return {}
	# 拆带号（1..60 数字前缀）或 UPS 带字母（A/B/Y/Z）
	var zone := 0
	var north := true
	var rest := ""
	var c0 := t[0]
	var band := ""
	if c0 >= "0" and c0 <= "9":
		var nd := 1
		while nd < t.length() and t[nd] >= "0" and t[nd] <= "9" and nd < 3:
			nd += 1
		zone = int(t.substr(0, nd))
		if zone < 1 or zone > 60:
			return {}
		rest = t.substr(nd)
		# UTM：紧随带号的是纬度带字母（C..X，无 I/O）
		if rest.length() < 4:
			return {}
		band = rest[0]
		if BAND_LETTERS.find(band) < 0:
			return {}
		rest = rest.substr(1)
	else:
		# UPS：首字母 A/B/Y/Z 即带字母
		if not ("ABYZ".contains(c0)):
			return {}
		north = c0 == "Y" or c0 == "Z"
		band = c0
		rest = t.substr(1)
	if rest.length() < 3:
		return {}
	var sq := rest.substr(0, 2)
	var digits := rest.substr(2)
	for ch in sq:
		if not _valid_letter(ch):
			return {}
	if digits.length() % 2 != 0 or digits.length() > 10:
		return {}
	var prec := digits.length() / 2
	var e_off := 0.0
	var n_off := 0.0
	var scale := pow(10.0, 5.0 - prec)
	if digits != "":
		var half := digits.length() / 2
		var e_part := digits.substr(0, half)
		var n_part := digits.substr(half)
		for ch in e_part + n_part:
			if ch < "0" or ch > "9":
				return {}
		e_off = float(int(e_part)) * scale
		n_off = float(int(n_part)) * scale
	# 反算取方格中心（与 mgrs 1.7.0 toLatLon 一致）；SW 角点口径见 to_mgrs 的 floor 截尾
	e_off += scale / 2.0
	n_off += scale / 2.0
	var ell := _EL.params("WGS84")
	var e_m := NAN
	var n_m := NAN
	if zone > 0:
		# UTM：方格列字母 → E100（8 列周期，需结合纬度带与数字区间消歧：取带宽内可行值）
		var col_set: String = COL_SETS[(zone - 1) % 3]
		var ci := col_set.find(sq[0])
		if ci < 0:
			return {}
		var row_set := ROW_ODD if zone % 2 == 1 else ROW_EVEN
		var ri := row_set.find(sq[1])
		if ri < 0:
			return {}
		# E100 ∈ {ci+1+8k}；N100 ∈ {ri+20k}
		# 先由数字初值粗定位，再对候选取带宽/纬度带检验
		var lat_hint := _band_hint_lat(t)
		var best := {}
		for k in range(-1, 8):
			var e100 := ci + 1 + 8 * k
			if e100 < 1 or e100 > 80:
				continue
			for m in range(0, 8):
				var n100 := ri + 20 * m
				if n100 < 0 or n100 > 200:
					continue
				var e_try := e100 * 100000.0 + e_off
				var n_try := n100 * 100000.0 + n_off
				# 北半球 FN=0、南半球 FN=10^7（同一 N 值两半球均可能，逐个尝试由纬度带消歧）
				for fnv: float in [0.0, 10000000.0]:
					var r := _GK.inv(n_try, e_try, _UT.cm(zone), ell, _UT.K0, _UT.FE, fnv)
					if r.is_empty():
						continue
					var lat := float(r["lat_deg"])
					if lat < -80.0 or lat >= 84.0:
						continue
					if not is_nan(lat_hint) and absf(lat - lat_hint) > 8.5:
						continue
					# 用正算回代校验方格字母一致
					if to_mgrs_check(zone, lat, float(r["lon_deg"]), sq):
						best = {"lat_deg": lat, "lon_deg": float(r["lon_deg"]), "e_m": e_try, "n_m": n_try}
						break
				if not best.is_empty():
					break
			if not best.is_empty():
				break
		if best.is_empty():
			return {}
		return {"lat_deg": best["lat_deg"], "lon_deg": best["lon_deg"], "e_m": best["e_m"], "n_m": best["n_m"],
				"zone": zone, "north": true}
	# UPS（band 已在解析处取得）
	north = band == "Y" or band == "Z"
	var ci2 := UPS_COL_ALPHABET.find(sq[0])
	if ci2 < 0:
		return {}
	var ri2 := UPS_ROW_ALPHABET.find(sq[1])
	if ri2 < 0:
		return {}
	var e100 := ci2 + 20  # 列号 = (E100-20)%20 → E100 ∈ [12,31] 域内取模回原
	var n100 := ri2 + 13 if north else ri2 + 8
	# 域内唯一化：UPS 有效 E/N ∈ 约 [1.1M, 3.0M]
	while e100 * 100000.0 < 1000000.0:
		e100 += 20
	while e100 * 100000.0 >= 3000000.0:
		e100 -= 20
	while n100 * 100000.0 < 1000000.0:
		n100 += 24
	while n100 * 100000.0 >= 3000000.0:
		n100 -= 24
	var e_try2 := e100 * 100000.0 + e_off
	var n_try2 := n100 * 100000.0 + n_off
	var r2 := _UP.inv(e_try2, n_try2, ell, north)
	if r2.is_empty():
		return {}
	var lat2 := float(r2["lat_deg"])
	var lon2 := float(r2["lon_deg"])
	if (north and lat2 < 84.0) or (not north and lat2 >= -80.0):
		return {}
	return {"lat_deg": lat2, "lon_deg": lon2, "e_m": e_try2, "n_m": n_try2,
			"zone": 0, "north": north}

# ---------- 内部 ----------

static func _digits(e_m: float, n_m: float, prec: int) -> String:
	var scale := pow(10.0, 5.0 - prec)
	var e_int := int(floor(fmod(e_m, 100000.0) / scale))
	var n_int := int(floor(fmod(n_m, 100000.0) / scale))
	var fmt := "%0" + str(prec) + "d"
	return (fmt % e_int) + (fmt % n_int)

static func _valid_letter(ch: String) -> bool:
	return ch >= "A" and ch <= "Z" and ch != "I" and ch != "O"

static func _prefix_len(s: String) -> int:
	var nd := 0
	while nd < s.length() and s[nd] >= "0" and s[nd] <= "9":
		nd += 1
	return nd + 3  # 带号 + 纬度带字母 + 100km 方格两位（UPS 为 1+2，此处按 UTM 口径）

static func _band_hint_lat(s: String) -> float:
	# 从字符串取纬度带字母（UTM）→ 带中心纬度提示
	var nd := 0
	while nd < s.length() and s[nd] >= "0" and s[nd] <= "9":
		nd += 1
	if nd + 1 >= s.length():
		return NAN
	var band := s[nd]
	var idx := BAND_LETTERS.find(band)
	if idx < 0:
		return NAN
	return -80.0 + 8.0 * idx + 4.0

static func _zone_of(lat_deg: float, lon_deg: float) -> int:
	if lat_deg >= 84.0 or lat_deg < -80.0:
		return 0
	return _UT.standard_zone(lat_deg, lon_deg)

static func _band_of(lat_deg: float, lon_deg: float) -> String:
	if lat_deg >= 84.0:
		return "Z" if lon_deg >= 0.0 else "Y"
	if lat_deg < -80.0:
		return "B" if lon_deg >= 0.0 else "A"
	var idx := clampi(int(floor((lat_deg + 80.0) / 8.0)), 0, BAND_LETTERS.length() - 1)
	return BAND_LETTERS[idx]

static func to_mgrs_check(zone: int, lat: float, lon: float, sq: String) -> bool:
	var ell := _EL.params("WGS84")
	var fn := 0.0 if lat >= 0.0 else 10000000.0
	var r := _GK.fwd(lat, lon, _UT.cm(zone), ell, _UT.K0, _UT.FE, fn)
	if r.is_empty():
		return false
	var e100 := int(floor(r["y_m"] / 100000.0))
	var n100 := int(floor(r["x_m"] / 100000.0))
	var col_set: String = COL_SETS[(zone - 1) % 3]
	var col := col_set[(e100 - 1 + 800) % 8]
	var row_set := ROW_ODD if zone % 2 == 1 else ROW_EVEN
	var row := row_set[n100 % 20]
	return col == sq[0] and row == sq[1]


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
		var t := String(v)
		if t.strip_edges().is_valid_float():
			return t.strip_edges().to_float()
	return NAN

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "MGRS（US NGA 字母方格）", "error": msg}
