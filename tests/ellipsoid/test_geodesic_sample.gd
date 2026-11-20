# tests/ellipsoid/test_geodesic_sample.gd —— GeodTest.dat 抽样回归（前 200 行）
#
# 数据：tests/ellipsoid/data/GeodTest_sample.dat，自 _research/GeodTest.dat
# （86,558,916 B，500,000 行，geographiclib C++ Geod 生成）截取前 200 行。
# 前 200 行含近对跖/赤道/子午线等最难例。文件每行 10 列：
#   lat1 lon1 azi1 lat2 lon2 azi2 s12 a12 m12 S12
# 断言：反解 azi1/azi2/a12（1e-8°）、s12/m12/S12（相对 1e-9，短边取绝对下限 1e-6）；
# 正解回收 lat2/lon2/azi2（1e-8°）。方位差经 ±180° 回绕比较。
# GDScript 格式化不支持 %.3e（实测），偏差输出一律用 str()。
extends "res://tests/test_case_base.gd"

const GEO := preload("res://core/ellipsoid/geodesic.gd")

const DATA_PATH := "res://tests/ellipsoid/data/GeodTest_sample.dat"
const ROWS := 200
const TOL_AZI := 1e-8
const TOL_REL := 1e-9

func _ang_delta(a: float, b: float) -> float:
	var d := GKAngles.normalize_deg(a - b)
	if d > 180.0:
		d -= 360.0
	return d

func _num(tok: String) -> float:
	var t := tok.strip_edges()
	if t.is_empty():
		return NAN
	if t.begins_with("."):
		t = "0" + t
	if not t.is_valid_float():
		return NAN
	return t.to_float()

func test_sample_200_rows() -> void:
	assert_true(FileAccess.file_exists(DATA_PATH), "样例数据文件应存在")
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	assert_true(f != null, "样例数据应可读")
	if f == null:
		return
	var g := GEO.wgs84()
	var rows := 0
	var worst_s12_rel := 0.0
	var worst_azi := 0.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges().is_empty():
			continue
		var toks := line.strip_edges().split(" ", false)
		if toks.size() < 10:
			_fail("第 " + str(rows + 1) + " 行列数不足（" + str(toks.size()) + "）")
			continue
		rows += 1
		var lat1 := _num(toks[0])
		var lon1 := _num(toks[1])
		var azi1 := _num(toks[2])
		var lat2 := _num(toks[3])
		var lon2 := _num(toks[4])
		var azi2 := _num(toks[5])
		var s12 := _num(toks[6])
		var a12 := _num(toks[7])
		var m12 := _num(toks[8])
		var S12 := _num(toks[9])
		if is_nan(lat1) or is_nan(lon1) or is_nan(lat2) or is_nan(lon2):
			_fail("第 " + str(rows) + " 行含无法解析的数值")
			continue
		# ---- 反解 ----
		var v := g.inverse_v(lat1, lon1, lat2, lon2)
		if v.is_empty():
			_fail("第 " + str(rows) + " 行反解返回空")
			continue
		var d_azi1: float = absf(_ang_delta(float(v["azi1"]), azi1))
		var d_azi2: float = absf(_ang_delta(float(v["azi2"]), azi2))
		var d_a12: float = absf(_ang_delta(float(v["a12"]), a12))
		worst_azi = maxf(worst_azi, maxf(d_azi1, maxf(d_azi2, d_a12)))
		if d_azi1 > TOL_AZI:
			_fail("第 " + str(rows) + " 行 azi1 偏差 " + str(d_azi1) + "°")
		if d_azi2 > TOL_AZI:
			_fail("第 " + str(rows) + " 行 azi2 偏差 " + str(d_azi2) + "°")
		if d_a12 > TOL_AZI:
			_fail("第 " + str(rows) + " 行 a12 偏差 " + str(d_a12) + "°")
		var d_s12: float = absf(float(v["s12"]) - s12) / maxf(absf(s12), 1.0)
		var d_m12: float = absf(float(v["m12"]) - m12) / maxf(absf(m12), 1.0)
		worst_s12_rel = maxf(worst_s12_rel, d_s12)
		if d_s12 > TOL_REL:
			_fail("第 " + str(rows) + " 行 s12 相对偏差 " + str(d_s12))
		if d_m12 > TOL_REL:
			_fail("第 " + str(rows) + " 行 m12 相对偏差 " + str(d_m12))
		var d_S12: float = absf(float(v["S12"]) - S12) / maxf(absf(S12), 1.0)
		if d_S12 > TOL_REL:
			_fail("第 " + str(rows) + " 行 S12 相对偏差 " + str(d_S12))
		# ---- 正解回收 ----
		var d := g.direct_v(lat1, lon1, azi1, s12)
		if d.is_empty():
			_fail("第 " + str(rows) + " 行正解返回空")
			continue
		var d_lat2: float = absf(float(d["lat2"]) - lat2)
		var d_lon2: float = absf(_ang_delta(float(d["lon2"]), lon2))
		var d_azi2b: float = absf(_ang_delta(float(d["azi2"]), azi2))
		worst_azi = maxf(worst_azi, maxf(d_lat2, maxf(d_lon2, d_azi2b)))
		if d_lat2 > TOL_AZI:
			_fail("第 " + str(rows) + " 行正解 lat2 偏差 " + str(d_lat2) + "°")
		if d_lon2 > TOL_AZI:
			_fail("第 " + str(rows) + " 行正解 lon2 偏差 " + str(d_lon2) + "°")
		if d_azi2b > TOL_AZI:
			_fail("第 " + str(rows) + " 行正解 azi2 偏差 " + str(d_azi2b) + "°")
	f.close()
	assert_eq(rows, ROWS, "应恰好回归 200 行")
	# 汇总指标（达标时无失败，日志留痕；GDScript 不支持 %.3e，用 str()）
	print("GeodTest 抽样：worst s12 相对偏差 = " + str(worst_s12_rel) + "，worst 角度量偏差(°) = " + str(worst_azi))
