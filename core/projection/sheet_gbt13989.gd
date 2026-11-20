# core/projection/sheet_gbt13989.gd —— GK-M3-8 地形图分幅编号（GB/T 13989-2012）
#
# 规则：
#   - 1:100 万：纬差 4°（行 A-V，自赤道向北）、经差 6°（列号 1-60，东经列号 = int(L/6)+31），
#     代码如 J50；
#   - 比例尺代码：B=1:50万 C=1:25万 D=1:10万 E=1:5万 F=1:2.5万 G=1:1万 H=1:5000（代码 B~K 备扩展）；
#   - 各比例尺把 1:100 万图幅按行列等分，行号自西北角（图幅上缘）起算，列号自西向东，
#     行/列各三位数字（GB/T 13989-2012）；
#   - 分割数（纬向 r × 经向 c）：50万 2×2、25万 4×4、10万 12×12、5万 24×24、2.5万 48×48、1万 96×96、5千 192×192。
# 验收向量（天安门 39°54′27.1″N,116°23′28.6″E）：
#   1:5万 J50E001010、1:10万 J50D001005、1:1万 J50G003039、1:50万 J50B001001、1:25万 J50C001002。
class_name GKSheetGbT13989
extends RefCounted

const _AN := preload("res://core/math/angles.gd")

const SCALES := {
	500000: {"code": "B", "name_cn": "1:50万", "rows": 2, "cols": 2},
	250000: {"code": "C", "name_cn": "1:25万", "rows": 4, "cols": 4},
	100000: {"code": "D", "name_cn": "1:10万", "rows": 12, "cols": 12},
	50000: {"code": "E", "name_cn": "1:5万", "rows": 24, "cols": 24},
	25000: {"code": "F", "name_cn": "1:2.5万", "rows": 48, "cols": 48},
	10000: {"code": "G", "name_cn": "1:1万", "rows": 96, "cols": 96},
	5000: {"code": "H", "name_cn": "1:5000", "rows": 192, "cols": 192},
}

## 低层编号：{lat_deg, lon_deg, scale_denom} → 图幅代码；非法返回 ""。
static func sheet_number(lat_deg: float, lon_deg: float, scale_denom: int) -> String:
	if lat_deg < 0.0 or lat_deg >= 88.0:
		return ""
	if lon_deg < -180.0 or lon_deg >= 180.0:
		return ""
	if scale_denom != 1000000 and not SCALES.has(scale_denom):
		return ""
	var row1m := int(floor(lat_deg / 4.0))          # 1:100 万行号（A=0）
	var col1m := int(floor(lon_deg / 6.0)) + 31     # 1:100 万列号（31..90 对应 0..±180）
	var letter := char(65 + row1m)                  # 'A' + row
	if row1m > 21:                                   # 超出 V（88°N 越界已在上方拦截，双保险）
		return ""
	var base := "%s%d" % [letter, col1m]
	if scale_denom == 1000000:
		return base
	var sc: Dictionary = SCALES[scale_denom]
	var r: int = sc["rows"]
	var c: int = sc["cols"]
	var lat0 := row1m * 4.0
	var lon0 := (col1m - 31) * 6.0
	var lat_idx := int(floor((lat_deg - lat0) * r / 4.0))   # 自南起算 0..r-1
	var lon_idx := int(floor((lon_deg - lon0) * c / 6.0))   # 自西起算 0..c-1
	lat_idx = clampi(lat_idx, 0, r - 1)
	lon_idx = clampi(lon_idx, 0, c - 1)
	var row_no := r - lat_idx                               # 行号自西北角起算
	var col_no := lon_idx + 1
	return "%s%s%03d%03d" % [base, sc["code"], row_no, col_no]

## 编号 → 图幅经纬范围 {lon_min, lon_max, lat_min, lat_max, scale_denom, code}；解析失败返回 {}。
static func sheet_range(code: String) -> Dictionary:
	var t := code.strip_edges().to_upper().replace(" ", "")
	# 1:100 万：字母 + 2 位列号（可 1-90）
	if t.length() < 3:
		return {}
	var letter := t[0]
	if letter < "A" or letter > "V":
		return {}
	var col_part := ""
	var i := 1
	while i < t.length() and t[i] >= "0" and t[i] <= "9":
		col_part += t[i]
		i += 1
	if col_part.is_empty():
		return {}
	var col1m := int(col_part)
	if col1m < 1 or col1m > 90:
		return {}
	var row1m := letter.unicode_at(0) - 65
	var rest := t.substr(i)
	var scale_denom := 1000000
	var scale_code := ""
	if rest != "":
		scale_code = rest[0]
		var found := false
		for den: int in SCALES:
			if SCALES[den]["code"] == scale_code:
				scale_denom = den
				found = true
				break
		if not found:
			return {}
	var lon_min := (col1m - 31) * 6.0
	var lon_max := lon_min + 6.0
	var lat_min := row1m * 4.0
	var lat_max := lat_min + 4.0
	if scale_denom == 1000000:
		return {"lon_min": lon_min, "lon_max": lon_max, "lat_min": lat_min, "lat_max": lat_max,
				"scale_denom": 1000000, "code": "%s%d" % [letter, col1m], "name_cn": "1:100万"}
	var nums := rest.substr(1)
	if nums.length() != 6 or not nums.is_valid_int():
		return {}
	var row_no := int(nums.substr(0, 3))
	var col_no := int(nums.substr(3, 3))
	var sc: Dictionary = SCALES[scale_denom]
	var r: int = sc["rows"]
	var c: int = sc["cols"]
	if row_no < 1 or row_no > r or col_no < 1 or col_no > c:
		return {}
	var d_lat := 4.0 / r
	var d_lon := 6.0 / c
	var lat_max2 := lat_max - (row_no - 1) * d_lat
	var lat_min2 := lat_max2 - d_lat
	var lon_min2 := lon_min + (col_no - 1) * d_lon
	var lon_max2 := lon_min2 + d_lon
	return {"lon_min": lon_min2, "lon_max": lon_max2, "lat_min": lat_min2, "lat_max": lat_max2,
			"scale_denom": scale_denom, "code": t, "name_cn": sc["name_cn"]}

## §5 协议：分幅编号计算。p: {lat_deg/lat_dms, lon_deg/lon_dms, scale_denom?（缺省 50000）}
## value 附全部比例尺代码 + 所在 1:100 万图幅信息。
static func forward(p: Dictionary) -> Dictionary:
	var lat := _num(p, "lat_deg", "lat_dms")
	var lon := _num(p, "lon_deg", "lon_dms")
	if is_nan(lat) or is_nan(lon):
		return _err("纬度/经度不是有效数字（可接受十进制度或度分秒文本）")
	if lat < 0.0 or lat >= 88.0:
		return _err("纬度 %s 超出分幅范围（GB/T 13989 行 A-V 覆盖 0°≤B<88°，南半球本标准不适用）" % String.num(lat, 4))
	if lon < -180.0 or lon >= 180.0:
		return _err("经度 %s 超出范围（|L|<180°）" % String.num(lon, 4))
	var scale := int(_f(p, "scale_denom", 50000))
	if scale != 1000000 and not SCALES.has(scale):
		return _err("不支持的比例尺分母 %d（可选：1000000/%s）" % [scale, "/".join(_scale_keys())])
	if scale == 1000000:
		var code1m := sheet_number(lat, lon, 1000000)
		var rng1m := sheet_range(code1m)
		var row1 := int(floor(lat / 4.0))
		var col1 := int(floor(lon / 6.0)) + 31
		return {"ok": true, "value": {
				"sheet_code": code1m, "scale": "1:100万", "scale_denom": 1000000,
				"map_1m": code1m,
				"lat_min_deg": rng1m["lat_min"], "lat_max_deg": rng1m["lat_max"],
				"lon_min_deg": rng1m["lon_min"], "lon_max_deg": rng1m["lon_max"],
			}, "steps": [{
				"title": "1. 1:100 万图幅代码",
				"formula": "行 = A + int(B/4)（每行 4°，A-V 共 22 行），列 = int(L/6) + 31（每列 6°）",
				"substitution": "B=%.6f°，L=%.6f°" % [lat, lon],
				"result": "行 %s（第 %d 行，B∈[%.1f°,%.1f°)），列 %d（L∈[%.1f°,%.1f°)）" % [char(65 + row1), row1, row1 * 4.0, row1 * 4.0 + 4.0, col1, (col1 - 31) * 6.0, (col1 - 30) * 6.0],
			}], "formula": "地形图分幅编号（GB/T 13989-2012；1:100 万 6°×4° 分幅）", "error": ""}

	var code := sheet_number(lat, lon, scale)
	if code.is_empty():
		return _err("分幅编号计算失败")
	var row1m := int(floor(lat / 4.0))
	var col1m := int(floor(lon / 6.0)) + 31
	var rng := sheet_range(code)
	var all_codes := {}
	for den: int in SCALES:
		all_codes[String(SCALES[den]["name_cn"])] = sheet_number(lat, lon, den)
	all_codes["1:100万"] = "%s%d" % [char(65 + row1m), col1m]
	var value := {
		"sheet_code": code,
		"scale": SCALES[scale]["name_cn"],
		"scale_denom": scale,
		"map_1m": "%s%d" % [char(65 + row1m), col1m],
		"lat_min_deg": rng["lat_min"], "lat_max_deg": rng["lat_max"],
		"lon_min_deg": rng["lon_min"], "lon_max_deg": rng["lon_max"],
	}
	for k: String in all_codes.keys():
		value["code_" + k] = all_codes[k]
	var steps := [
		{"title": "1. 1:100 万图幅", "formula": "行 = A + int(B/4)，列 = int(L/6) + 31（自 180°W 起算）",
			"substitution": "B=%.6f°，L=%.6f°" % [lat, lon],
			"result": "行 %s（%d 带，B∈[%.4f°,%.4f°)），列 %d（L∈[%.4f°,%.4f°)）" % [char(65 + row1m), row1m, row1m * 4.0, row1m * 4.0 + 4.0, col1m, (col1m - 31) * 6.0, (col1m - 30) * 6.0]},
		{"title": "2. 比例尺行列号", "formula": "1:100 万图幅按 %d 行 × %d 列等分，行号自西北角（图幅上缘）起算，列号自西向东" % [SCALES[scale]["rows"], SCALES[scale]["cols"]],
			"substitution": "B-%d×4°=%.6f°，L-%d×6°=%.6f°" % [row1m, lat - row1m * 4.0, col1m - 31, lon - (col1m - 31) * 6.0],
			"result": "行 %03d，列 %03d" % [int(code.substr(code.length() - 6, 3)), int(code.substr(code.length() - 3, 3))]},
		{"title": "3. 图幅代码", "formula": "代码 = 1:100 万代码 + 比例尺代码（%s）+ 行列三位序号" % SCALES[scale]["code"],
			"substitution": "比例尺 %s" % SCALES[scale]["name_cn"],
			"result": code + ("（B∈[%.4f°,%.4f°]，L∈[%.4f°,%.4f°]）" % [rng["lat_min"], rng["lat_max"], rng["lon_min"], rng["lon_max"]])},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "地形图分幅编号（GB/T 13989-2012；1:100 万行列分割 + 比例尺代码 B~K）",
			"error": ""}

## §5 协议：由编号反查图幅范围。p: {sheet_code}
static func lookup(p: Dictionary) -> Dictionary:
	var code := String(p.get("sheet_code", ""))
	var rng := sheet_range(code)
	if rng.is_empty():
		return _err("图幅编号无法解析（应为 1:100 万代码 + 可选比例尺代码 + 六位行列号，例：J50E001010）")
	var value := {
		"sheet_code": rng["code"], "scale": rng["name_cn"], "scale_denom": rng["scale_denom"],
		"lat_min_deg": rng["lat_min"], "lat_max_deg": rng["lat_max"],
		"lon_min_deg": rng["lon_min"], "lon_max_deg": rng["lon_max"],
	}
	var steps := [
		{"title": "1. 解析代码", "formula": "字母→1:100 万行，数字列→1:100 万列，比例尺代码→分割数，六位数字→行列序号",
			"substitution": "输入 = %s" % String(rng["code"]),
			"result": "%s（%s）" % [String(rng["code"]), String(rng["name_cn"])]},
		{"title": "2. 图幅范围", "formula": "行列序号换算经纬范围（行自西北角起算）",
			"substitution": "输入 = %s（%s）" % [String(rng["code"]), String(rng["name_cn"])],
			"result": "B∈[%.4f°,%.4f°]，L∈[%.4f°,%.4f°]" % [rng["lat_min"], rng["lat_max"], rng["lon_min"], rng["lon_max"]]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "图幅编号反查（GB/T 13989-2012）", "error": ""}

## 支持的比例尺分母列表
static func list_scales() -> Array:
	return _scale_keys()

static func _scale_keys() -> Array:
	var out := [1000000]
	for den: int in SCALES.keys():
		out.append(den)
	return out

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
	return {"ok": false, "value": {}, "steps": [], "formula": "地形图分幅编号（GB/T 13989-2012）", "error": msg}
