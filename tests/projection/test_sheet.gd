# tests/projection/test_sheet.gd —— M3-8 地形图分幅编号（GB/T 13989-2012）回归
#
# 向量来源【权威·GB/T 13989-2012】天安门 (39°54′27.1″N,116°23′28.6″E)：
#   1:5万 J50E001010、1:10万 J50D001005、1:1万 J50G003039、1:50万 J50B001001、1:25万 J50C001002。
# 另核读（同规则推算）：1:100 万 J50；1:2.5万 J50F002020（48×48 分割）。
extends "res://tests/test_case_base.gd"

const SH := preload("res://core/projection/sheet_gbt13989.gd")

func _v(res: Dictionary) -> Dictionary:
	return res.get("value", {}) if res.get("ok", false) else {}

func test_authoritative_sheet_codes() -> void:
	var p := {"lat_dms": "39°54′27.1″", "lon_dms": "116°23′28.6″"}
	var r := SH.forward({"lat_dms": p["lat_dms"], "lon_dms": p["lon_dms"], "scale_denom": 50000})
	assert_true(bool(r.get("ok", false)), "1:5万 分幅：" + String(r.get("error", "")))
	assert_eq(String(_v(r)["sheet_code"]), "J50E001010", "1:5万 J50E001010")
	r = SH.forward({"lat_deg": 39.0 + 54.0 / 60.0 + 27.1 / 3600.0, "lon_deg": 116.0 + 23.0 / 60.0 + 28.6 / 3600.0, "scale_denom": 100000})
	assert_eq(String(_v(r)["sheet_code"]), "J50D001005", "1:10万 J50D001005")
	r = SH.forward({"lat_deg": 39.907527778, "lon_deg": 116.391277778, "scale_denom": 10000})
	assert_eq(String(_v(r)["sheet_code"]), "J50G003039", "1:1万 J50G003039")
	r = SH.forward({"lat_deg": 39.907527778, "lon_deg": 116.391277778, "scale_denom": 500000})
	assert_eq(String(_v(r)["sheet_code"]), "J50B001001", "1:50万 J50B001001")
	r = SH.forward({"lat_deg": 39.907527778, "lon_deg": 116.391277778, "scale_denom": 250000})
	assert_eq(String(_v(r)["sheet_code"]), "J50C001002", "1:25万 J50C001002")

func test_scale_1m_and_25k() -> void:
	var lat := 39.0 + 54.0 / 60.0 + 27.1 / 3600.0
	var lon := 116.0 + 23.0 / 60.0 + 28.6 / 3600.0
	var r := SH.forward({"lat_deg": lat, "lon_deg": lon, "scale_denom": 1000000})
	var v: Dictionary = _v(r)
	assert_eq(String(v["sheet_code"]), "J50", "1:100万 J50")
	assert_eq(String(v["map_1m"]), "J50", "1:100 万图幅")
	assert_almost_eq(float(v["lat_min_deg"]), 36.0, 1e-9, "J50 纬度下界")
	assert_almost_eq(float(v["lat_max_deg"]), 40.0, 1e-9, "J50 纬度上界")
	var r25k := SH.forward({"lat_deg": lat, "lon_deg": lon, "scale_denom": 25000})
	var v25k: Dictionary = _v(r25k)
	assert_eq(String(v25k["sheet_code"]), "J50F002020", "1:2.5万 J50F002020（48×48 分割）")
	# value 附全部比例尺代码
	assert_eq(String(v25k.get("code_1:5万", "")), "J50E001010", "附加 1:5万 代码")
	assert_eq(String(v25k.get("code_1:1万", "")), "J50G003039", "附加 1:1万 代码")

func test_sheet_range_reverse() -> void:
	var rng := SH.sheet_range("J50E001010")
	assert_true(not rng.is_empty(), "J50E001010 可解析")
	assert_almost_eq(float(rng["lat_min"]), 39.0 + 50.0 / 60.0, 1e-9, "1:5万 行1 纬度下界 39°50′")
	assert_almost_eq(float(rng["lat_max"]), 40.0, 1e-9, "纬度上界 40°")
	assert_almost_eq(float(rng["lon_min"]), 116.25, 1e-9, "列10 经度下界 116°15′")
	assert_almost_eq(float(rng["lon_max"]), 116.5, 1e-9, "经度上界 116°30′")
	assert_eq(String(rng["name_cn"]), "1:5万", "比例尺名")
	# 天安门在图幅内 → 编号往返一致
	var code := SH.sheet_number(39.92, 116.3, 50000)
	assert_eq(code, "J50E001010", "图幅内点编号往返")
	# 1:1万 行列范围
	var rng2 := SH.sheet_range("J50G003039")
	assert_almost_eq(float(rng2["lat_max"]), 40.0 - 2.0 * (4.0 / 96.0), 1e-9, "1:1万 行3 上缘")
	assert_almost_eq(float(rng2["lon_min"]), 114.0 + 38.0 * (6.0 / 96.0), 1e-9, "1:1万 列39 下缘")

func test_row_numbering_from_northwest() -> void:
	# 行号自西北角起算：同列不同纬度，纬度越高行号越小
	var c_north := SH.sheet_number(39.95, 116.4, 10000)
	var c_south := SH.sheet_number(39.05, 116.4, 10000)
	assert_eq(c_north.substr(4, 3), "002", "39.95N 行 002（96 行分割，首行 [39°57′30″,40°)）")
	assert_eq(c_south.substr(4, 3), "023", "39.05N 行 023")
	# 列号自西向东
	var c_west := SH.sheet_number(39.5, 114.05, 10000)
	var c_east := SH.sheet_number(39.5, 119.95, 10000)
	assert_eq(c_west.substr(7, 3), "001", "114.05E 列 001")
	assert_eq(c_east.substr(7, 3), "096", "119.95E 列 096（末列）")

func test_boundary_and_errors() -> void:
	# 88°N 以上/南半球不适用
	assert_true(SH.sheet_number(88.5, 116.0, 50000).is_empty(), "B≥88 越界")
	assert_false(bool(SH.forward({"lat_deg": -5.0, "lon_deg": 116.0, "scale_denom": 50000}).get("ok", true)),
			"南半球应给出中文错误")
	assert_true(String(SH.forward({"lat_deg": -5.0, "lon_deg": 116.0, "scale_denom": 50000}).get("error", "")).contains("南半球"),
			"南半球提示")
	# 非法比例尺
	assert_false(bool(SH.forward({"lat_deg": 39.9, "lon_deg": 116.0, "scale_denom": 30000}).get("ok", true)), "非法比例尺")
	# 非法输入
	assert_false(bool(SH.forward({"lat_deg": "abc", "lon_deg": 116.0}).get("ok", true)), "非法数字")
	# 反查非法代码
	assert_true(SH.sheet_range("XXE001010").is_empty(), "行字母越界")
	assert_true(SH.sheet_range("J50Z001010").is_empty(), "比例尺代码越界")
	assert_true(SH.sheet_range("J50E099010").is_empty(), "行号越界")
	var lk := SH.lookup({"sheet_code": "J50D001005"})
	assert_true(bool(lk.get("ok", false)), "lookup 1:10万：" + String(lk.get("error", "")))
	var lv: Dictionary = _v(lk)
	assert_almost_eq(float(lv["lon_min_deg"]), 116.0, 1e-9, "1:10万 列5 下缘 116")
	assert_almost_eq(float(lv["lon_max_deg"]), 116.5, 1e-9, "1:10万 列5 上缘 116.5")
	assert_almost_eq(float(lv["lat_max_deg"]), 40.0, 1e-9, "1:10万 行1 上缘 40")

# ---------- P5 追加：步骤中间量显式计算（不从结果字符串反取） ----------

## forward 步骤含显式中间量：(B−B₀)·r/4、(L−L₀)·c/6 与行号换算
## （1:5万 r=c=24：天安门 ΔB≈0.9075°→序数 5.445→取整 5→行号 24−5=19？——实际行号 001，
##   因为天安门在 1:5万图幅首行（行 1，B∈[39°50′,40°)）——中间量口径按实现验证）
func test_forward_steps_explicit_intermediates() -> void:
	var r := SH.forward({"lat_deg": 39.907527778, "lon_deg": 116.391277778, "scale_denom": 50000})
	assert_true(bool(r.get("ok", false)), "1:5万 forward 成功")
	if bool(r.get("ok", false)):
		var joined := ""
		for s: Dictionary in r["steps"]:
			joined += String(s.get("title", "")) + "|" + String(s.get("substitution", "")) + "|" + String(s.get("result", ""))
		# 步骤含纬向/经向分割序数中间量（ΔB×24/4、ΔL×24/6）
		assert_true(joined.contains("×24/4"), "纬向序数公式含 ×24/4")
		assert_true(joined.contains("×24/6"), "经向序数公式含 ×24/6")
		# 中间量数值：ΔB = 39.907527778−39 = 0.907527778 → ×6 = 5.44516667；ΔL = 116.391277778−114 = 2.391277778 → ×4 = 9.56511111
		assert_true(joined.contains("5.445"), "纬向序数中间量 5.445…")
		assert_true(joined.contains("9.565"), "经向序数中间量 9.565…")
		# 行号换算：行号 = 24 − 5 = 19? 不对——1:5万 24 行，天安门 ΔB×24/4=5.445 → 纬向序数 5 → 行号 = 24−5 = 19?
		# 实测权威向量 J50E001010 行 001：ΔB×24/4 = 5.445 → 取整 5 → 行号 24−5 = 19 ≠ 1。
		# 更正：天安门 B=39°54′27.1″ 在 1:100 万 J50（B∈[36,40)），1:5万 首行 B∈[39°50′,40°)。
		# ΔB 相对图幅南缘 B₀=36°，非行南缘：(39.9075−36)×24/4 = 23.445 → 取整 23 → 行号 24−23 = 1 ✓
		assert_true(joined.contains("23.445"), "ΔB 相对图幅南缘的序数 23.445…")
		assert_true(joined.contains("24 − 23"), "行号换算 24 − 23 = 1")
		assert_true(joined.contains("001"), "行号 001")

## lookup 步骤显式给出每格经纬差（不从结果字符串反取）
func test_lookup_steps_explicit_grid_size() -> void:
	var r := SH.lookup({"sheet_code": "J50G003039"})
	assert_true(bool(r.get("ok", false)), "lookup 1:1万 成功")
	if bool(r.get("ok", false)):
		var joined := ""
		for s: Dictionary in r["steps"]:
			joined += String(s.get("substitution", "")) + "|" + String(s.get("result", ""))
		# 1:1万 96×96：纬差 4/96 = 0.041666…°，经差 6/96 = 0.0625°
		assert_true(joined.contains("0.041667"), "纬差 4/96 中间量")
		assert_true(joined.contains("0.062500") or joined.contains("0.0625"), "经差 6/96 中间量")
		assert_true(joined.contains("行号 003"), "显式行号 003")
		assert_true(joined.contains("列号 039"), "显式列号 039")
