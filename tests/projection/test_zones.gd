# tests/projection/test_zones.gd —— M3-2 带号/中央子午线查询与 3°/6° 换带回归
#
# 向量来源【权威·pyproj EPSG 码 + 本会话核读】：
#   - 带号前缀：EPSG:4527（CGCS2000 3° zone39）横坐标 = 39617474.9201 = 39×10⁶+617474.9201；
#     EPSG:4498（6° zone20）= 20617474.9201 = 20×10⁶+617474.9201（对 (32.5,118.25)）；
#   - EPSG 表 192 行经 pyproj 内置官方 EPSG 数据库逐条核读（4527=带前缀、4548=自然 y，
#     与旧 crs_presets.json 的 y_prefix_zone 标志相反，本次已按核读结果修正数据文件）。
# 注意：任务书表述“带号 EPSG:4527”正确；“自然 y 4527”为笔误（4527 的 FE=39500000，
# 自然 y 对应 4548），测试按 EPSG 实测值断言。
extends "res://tests/test_case_base.gd"

const ZN := preload("res://core/projection/zones.gd")
const GK := preload("res://core/projection/gauss_kruger.gd")

func test_zone_and_cm_rules() -> void:
	assert_int_eq(ZN.zone6_from_lon(116.3913), 20, "6° 带 116.39E→20")
	assert_int_eq(ZN.zone6_from_lon(118.25), 20, "6° 带 118.25→20")
	assert_int_eq(ZN.zone6_from_lon(3.0), 1, "6° 带 3E→1")
	assert_int_eq(ZN.zone6_from_lon(-70.252228), -11, "6° 带 70.25W→-11（CM -69）")
	assert_almost_eq(ZN.cm6(-11), -69.0, 1e-12, "6° 带西经 CM=6n-3")
	assert_int_eq(ZN.zone3_from_lon(116.3913), 39, "3° 带 116.39→39")
	assert_int_eq(ZN.zone3_from_lon(118.25), 39, "3° 带 118.25→39")
	assert_int_eq(ZN.zone3_from_lon(118.5), 40, "3° 带边界 118.5 归东带 40")
	assert_int_eq(ZN.zone3_from_lon(117.0), 39, "3° 带 CM 点 117→39")
	assert_int_eq(ZN.zone3_from_lon(90.0), 30, "3° 带 90E→30")
	assert_almost_eq(ZN.cm3(39), 117.0, 1e-12, "3° 带 CM=3n")
	assert_almost_eq(ZN.cm6(20), 117.0, 1e-12, "6° 带 20 CM=117")

func test_y_prefix_vectors() -> void:
	var r := GK.forward({"lat_deg": 32.5, "lon_deg": 118.25, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "前置正算应成功")
	var y_natural := float((r.get("value", {}) as Dictionary).get("y_m", 0.0))
	assert_almost_eq(y_natural, 617474.9201, 0.0005, "自然 y（FE=500000）")
	# EPSG:4527 3° zone39 带前缀 y = 39617474.9201
	assert_almost_eq(ZN.y_with_prefix(y_natural, 39), 39617474.9201, 0.0005, "3° 带 39 前缀 y（EPSG:4527）")
	# EPSG:4498 6° zone20 带前缀 y = 20617474.9201
	assert_almost_eq(ZN.y_with_prefix(y_natural, 20), 20617474.9201, 0.0005, "6° 带 20 前缀 y（EPSG:4498）")
	# 拆分回原
	var sp := ZN.split_prefix_y(39617474.9201)
	assert_int_eq(int(sp["zone"]), 39, "前缀拆出带号")
	assert_almost_eq(float(sp["y_natural"]), 617474.9201, 1e-6, "前缀拆出自然 y")

func test_query() -> void:
	var q := ZN.query(116.3913)
	assert_true(not q.is_empty(), "query 应返回结果")
	assert_int_eq(int(q["zone6"]), 20, "query zone6")
	assert_almost_eq(float(q["l0_6"]), 117.0, 1e-12, "query l0_6")
	assert_int_eq(int(q["zone3"]), 39, "query zone3")
	assert_almost_eq(float(q["l0_3"]), 117.0, 1e-12, "query l0_3")
	assert_true(bool(q["band3_valid"]), "3° 带内")
	assert_true(ZN.query(200.0).is_empty(), "经度越界返回空")

func test_switch_zone_roundtrip() -> void:
	# CM117 → CM120 → 回 CM117：往返闭合
	var r1 := GK.forward({"lat_deg": 32.5, "lon_deg": 118.9, "l0_deg": 117.0, "datum": "CGCS2000"})
	var v1: Dictionary = r1.get("value", {})
	assert_true(bool(r1.get("ok", false)), "原带正算成功")
	var sw := ZN.switch_zone({"x_m": v1["x_m"], "y_m": v1["y_m"], "l0_from_deg": 117.0,
			"datum": "CGCS2000", "to_band": "3"})
	assert_true(bool(sw.get("ok", false)), "换带应成功：" + String(sw.get("error", "")))
	var sv: Dictionary = sw.get("value", {})
	assert_int_eq(int(sv["zone"]), 40, "新带 40（CM120）")
	assert_almost_eq(float(sv["l0_deg"]), 120.0, 1e-12, "新带 L0=120")
	assert_almost_eq(float(sv["lat_deg"]), 32.5, 5e-9, "换带中间 B")
	assert_almost_eq(float(sv["lon_deg"]), 118.9, 5e-9, "换带中间 L")
	# 与直接在新带正算一致
	var r2 := GK.forward({"lat_deg": 32.5, "lon_deg": 118.9, "l0_deg": 120.0, "datum": "CGCS2000"})
	var v2: Dictionary = r2.get("value", {})
	assert_almost_eq(float(sv["x_m"]), float(v2["x_m"]), 1e-6, "换带 x = 直接新带正算")
	assert_almost_eq(float(sv["y_m"]), float(v2["y_m"]), 1e-6, "换带 y = 直接新带正算")
	# 回换往返闭合（显式回 39 带 CM117）
	var sw2 := ZN.switch_zone({"x_m": float(sv["x_m"]), "y_m": float(sv["y_m"]), "l0_from_deg": 120.0,
			"datum": "CGCS2000", "to_band": "3", "to_zone": 39})
	var sv2: Dictionary = sw2.get("value", {})
	assert_almost_eq(float(sv2["x_m"]), float(v1["x_m"]), 1e-6, "回换 x 闭合")
	assert_almost_eq(float(sv2["y_m"]), float(v1["y_m"]), 1e-6, "回换 y 闭合")

func test_switch_band_limit_hint() -> void:
	# 点 (32.5, 113)：所在 3° 带为 38（CM114）；换到 39 带（CM117）距中央子午线 4° > 3.5° 限界
	var r := GK.forward({"lat_deg": 32.5, "lon_deg": 113.0, "l0_deg": 114.0, "datum": "CGCS2000"})
	var v: Dictionary = r.get("value", {})
	assert_true(bool(r.get("ok", false)), "原带（CM114）正算成功")
	var sw := ZN.switch_zone({"x_m": float(v["x_m"]), "y_m": float(v["y_m"]), "l0_from_deg": 114.0,
			"datum": "CGCS2000", "to_band": "3", "to_zone": 39})
	assert_false(bool(sw.get("ok", true)), "距目标 CM>3.5° 应拒绝")
	assert_true(String(sw.get("error", "")).contains("6°"), "超限提示建议改 6° 带：" + String(sw.get("error", "")))
	# 同点换 6° 带（自动 19 带 CM111）：应成功
	var sw6 := ZN.switch_zone({"x_m": float(v["x_m"]), "y_m": float(v["y_m"]), "l0_from_deg": 114.0,
			"datum": "CGCS2000", "to_band": "6"})
	assert_true(bool(sw6.get("ok", false)), "换 6° 带成功：" + String(sw6.get("error", "")))
	var sv6: Dictionary = sw6.get("value", {})
	assert_int_eq(int(sv6["zone"]), 19, "113E 的 6° 带 = 19")
	assert_almost_eq(float(sv6["l0_deg"]), 111.0, 1e-12, "6° 带 CM=111")

func test_epsg_table() -> void:
	# pyproj 官方 EPSG 数据库核读值
	assert_int_eq(ZN.epsg_of("CGCS2000", "3", 39, true), 4527, "CGCS2000 3° zone39 带前缀=4527")
	assert_int_eq(ZN.epsg_of("CGCS2000", "3", 39, false), 4548, "CGCS2000 3° CM117 自然 y=4548")
	assert_int_eq(ZN.epsg_of("CGCS2000", "6", 20, true), 4498, "CGCS2000 6° zone20 带前缀=4498")
	assert_int_eq(ZN.epsg_of("CGCS2000", "6", 20, false), 4509, "CGCS2000 6° CM117 自然 y=4509")
	assert_int_eq(ZN.epsg_of("北京54", "6", 20, false), 21460, "北京54 6° CM117=21460")
	assert_int_eq(ZN.epsg_of("北京54", "3", 39, true), 2415, "北京54 3° zone39=2415")
	assert_int_eq(ZN.epsg_of("北京54", "3", 39, false), 2436, "北京54 3° CM117=2436")
	assert_int_eq(ZN.epsg_of("西安80", "3", 39, false), 2384, "西安80 3° CM117=2384")
	assert_int_eq(ZN.epsg_of("西安80", "6", 20, false), 2345, "西安80 6° CM117=2345")
	assert_int_eq(ZN.epsg_of("CGCS2000", "3", 13, false), 0, "带号不在表中返回 0")
	# 表完整性：192 行、无重复 EPSG
	var rows := ZN.epsg_rows()
	assert_int_eq(rows.size(), 192, "EPSG 表 192 行")
	var seen := {}
	var dup := 0
	for row: Dictionary in rows:
		var code := int(row["epsg"])
		if seen.has(code):
			dup += 1
		seen[code] = true
	assert_int_eq(dup, 0, "EPSG 码无重复")
	# 与 data/crs_presets.json 数据一致性（行数与关键值）
	var f := FileAccess.open("res://data/crs_presets.json", FileAccess.READ)
	assert_true(f != null, "crs_presets.json 可读")
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		assert_true(parsed is Dictionary, "crs_presets.json 为对象")
		if parsed is Dictionary:
			var jrows: Array = parsed.get("rows", [])
			assert_int_eq(jrows.size(), 192, "JSON 行数与 core 表一致")
			var found_4527 := false
			var found_21460 := false
			for jr: Dictionary in jrows:
				if int(jr.get("epsg", 0)) == 4527:
					found_4527 = bool(jr.get("y_prefix_zone", false))
				if int(jr.get("epsg", 0)) == 21460:
					found_21460 = not bool(jr.get("y_prefix_zone", true))
			assert_true(found_4527, "JSON: 4527 为带前缀")
			assert_true(found_21460, "JSON: 21460 为自然 y")

# ---------- P1 追加：带号口径区分（中国 3°/6° 带 vs UTM 1..60） ----------
# 中国 6° 带：L0=6n−3（中国境内 n=13..23）；UTM：L0=6n−183（n=1..60，180°W 起编号）。
# 同一中央子午线 117°E 下中国 6° 带号 20、UTM 带号 50，两口径数值差 12，不可混写。

func test_zone_numbering_convention_distinction() -> void:
	# 中国 6° 带口径：CM117 → n=20（116.39E 在带 20）
	assert_int_eq(ZN.zone6_from_lon(116.3913), 20, "中国 6° 带 CM117=带 20")
	assert_almost_eq(ZN.cm6(20), 117.0, 1e-12, "中国口径 L0=6n−3")
	# 中国 3° 带口径：CM117 → n=39，L0=3n
	assert_int_eq(ZN.zone3_from_lon(117.0), 39, "中国 3° 带 CM117=带 39")
	assert_almost_eq(ZN.cm3(39), 117.0, 1e-12, "中国口径 L0=3n")
	# 同一 CM117 在 UTM 口径为带 50（L0=6×50−183=117）——由换算关系断言，
	# UTM 本体实现与带号在 utm.gd（A7），此处仅钉死口径区分注释所述关系
	assert_almost_eq(6.0 * 50 - 183.0, 117.0, 1e-12, "UTM 口径 CM117=带 50（6n−183）")
	# EPSG 表与口径注释一致：4548 = CGCS2000 3° CM117E 自然 y（"CM xxE" 系列）
	assert_int_eq(ZN.epsg_of("CGCS2000", "3", 39, false), 4548, "EPSG:4548 为 CM117 自然 y 系列")
