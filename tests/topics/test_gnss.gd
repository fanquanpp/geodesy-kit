# tests/topics/test_gnss.gd —— GK-M8-6（I-GNSS）
# 向量来源：ARCHITECTURE.md §4 GK-M8【构造·本会话】I-GNSS DOP：4 星对称单位视线
# (±0.5,±0.3,0.8124)→PDOP=2.0388（3×3 位置口径，z 取精确单位分量 √0.66）。
# 广播星历无实测向量（落地补），按 ARCHITECTURE §0 #5 构造自洽：开普勒迭代收敛 +
# 退化圆轨道解析解对照 + 半周滚转。
extends "res://tests/test_case_base.gd"

const G := preload("res://core/topics/gnss.gd")

func test_dop_authority_vector() -> void:
	var z := sqrt(0.66)
	var los := [
		[0.5, 0.3, z], [0.5, -0.3, z], [-0.5, 0.3, z], [-0.5, -0.3, z],
	]
	var r := G.dop({"los": los})
	assert_true(r["ok"], "DOP 权威构造向量应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		# 解析真值：GᵀG = diag(1, 0.36, 2.64) → PDOP = √(1 + 1/0.36 + 1/2.64)
		var pdop_exact := sqrt(1.0 + 1.0 / 0.36 + 1.0 / 2.64)
		assert_almost_eq(float(v["pdop"]), pdop_exact, 1e-9, "PDOP 解析值（构造自洽）")
		assert_almost_eq(float(v["pdop"]), 2.0388, 1e-4, "PDOP 权威向量 2.0388")
		assert_almost_eq(float(v["hdop"]), sqrt(1.0 + 1.0 / 0.36), 1e-9, "HDOP 解析值")
		assert_almost_eq(float(v["vdop"]), sqrt(1.0 / 2.64), 1e-9, "VDOP 解析值")

func test_dop_with_clock_singular() -> void:
	# 全等高度角对称星座：4×4 含钟差列奇异（第 3、4 列平行）→ 中文报错而非崩溃
	var z := sqrt(0.66)
	var los := [[0.5, 0.3, z], [0.5, -0.3, z], [-0.5, 0.3, z], [-0.5, -0.3, z]]
	var r := G.dop({"los": los, "with_clock": true})
	assert_false(bool(r["ok"]), "4×4 应报告几何退化")
	assert_true(String(r["error"]).contains("钟差") or String(r["error"]).contains("退化"), "中文退化提示")
	# 非对称 4 星的 4×4 正常路径
	var los2 := [[0.5, 0.3, z], [0.5, -0.3, z], [-0.6, 0.2, 0.75], [0.1, -0.4, 0.9]]
	var r2 := G.dop({"los": los2, "with_clock": true})
	assert_true(r2["ok"], "一般星座 4×4 应成功")
	if bool(r2["ok"]):
		var v: Dictionary = r2["value"]
		assert_true(float(v["gdop"]) >= float(v["pdop"]), "GDOP ≥ PDOP")
		assert_true(float(v["tdop"]) > 0.0, "TDOP > 0")

func test_dop_invalid() -> void:
	var r1 := G.dop({"los": [[0.5, 0.3, 0.8], [0.5, -0.3, 0.8], [-0.5, 0.3, 0.8]]})
	assert_false(bool(r1["ok"]), "少于 4 星应拒绝")
	var r2 := G.dop({"los": [[0.0, 0.0, 0.0], [0.5, 0.3, 0.8], [0.5, -0.3, 0.8], [-0.5, 0.3, 0.8]]})
	assert_false(bool(r2["ok"]), "零向量应拒绝")
	var r3 := G.dop({"los": "bad"})
	assert_false(bool(r3["ok"]), "非法输入应拒绝")

func test_kepler_solver() -> void:
	# e=0：E = M（解析解）
	assert_almost_eq(G.kepler_solve(1.5, 0.0), 1.5, 1e-12, "圆轨道 E=M")
	# 一般情形：残差 E − e·sinE − M 应小于 1e-12
	for e: float in [0.01, 0.3, 0.7, 0.99]:
		var m := 2.4
		var ec := G.kepler_solve(m, e)
		assert_true(is_finite(ec), "e=%.2f 应收敛" % e)
		if is_finite(ec):
			var resid := absf(ec - e * sin(ec) - m)
			# GDScript format 不支持 %e/%g（地基实测教训），科学计数值用 str() 拼接
			assert_true(resid < 1e-12, "e=%.2f 开普勒残差 <1e-12（实际 %s）" % [e, str(resid)])
	# 高偏心小 M（初值敏感性边界）
	var ec2 := G.kepler_solve(0.001, 0.9)
	assert_true(is_finite(ec2) and ec2 > 0.0, "e=0.9, M≈0 应收敛且 E>0")
	assert_true(is_nan(G.kepler_solve(1.0, 1.0)), "e≥1 应返回 NAN")

func test_tk_adjust() -> void:
	assert_almost_eq(G.tk_adjust(5000.0, 600000.0), 9800.0, 1e-9, "负向半周滚转 +604800")
	assert_almost_eq(G.tk_adjust(100000.0, 400000.0), -300000.0, 1e-9, "界内不滚动")
	assert_almost_eq(G.tk_adjust(400000.0, 100000.0), 300000.0, 1e-9, "界内正向")
	assert_almost_eq(G.tk_adjust(200000.0, 200000.0), 0.0, 1e-9, "t=toe")

func test_circular_orbit_analytic() -> void:
	# 退化圆轨道：e=0、C 系数全 0、ω=0、Ω̇=0、İ=0 → 与解析式逐项对照
	var a := 26560000.0
	var p := {
		"sqrt_a": sqrt(a), "e": 0.0,
		"i0": 0.9, "omega": 0.0, "omega0": 0.5, "omega_dot": 0.0,
		"m0": 0.3, "delta_n": 0.0,
		"cuc": 0.0, "cus": 0.0, "crc": 0.0, "crs": 0.0, "cic": 0.0, "cis": 0.0, "idot": 0.0,
		"toe": 100000.0, "t_gps": 150000.0,
	}
	var r := G.ephemeris_to_ecef(p)
	assert_true(r["ok"], "圆轨道星历应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		var n := sqrt(G.MU / (a * a * a))
		var tk := 50000.0
		var m := 0.3 + n * tk
		var om := 0.5 - G.OMEGA_E_DOT * 150000.0
		var xo := a * cos(m)
		var yo := a * sin(m)
		var x_ref := xo * cos(om) - yo * sin(om) * cos(0.9)
		var y_ref := xo * sin(om) + yo * cos(om) * cos(0.9)
		var z_ref := yo * sin(0.9)
		assert_almost_eq(float(v["x_m"]), x_ref, 1e-6, "圆轨道 ECEF x（解析对照）")
		assert_almost_eq(float(v["y_m"]), y_ref, 1e-6, "圆轨道 ECEF y（解析对照）")
		assert_almost_eq(float(v["z_m"]), z_ref, 1e-6, "圆轨道 ECEF z（解析对照）")
		assert_almost_eq(float(v["r_orb_m"]), a, 1e-6, "圆轨道半径 = a")
		assert_almost_eq(float(v["tk_s"]), tk, 1e-9, "tk")

func test_realistic_ephemeris_sanity() -> void:
	# 构造"合理"GPS 星历：轨道半径介于 a(1±e)，位置随 t 单调推进
	var p := {
		"sqrt_a": 5153.793876, "e": 0.005,
		"i0": 0.9599310859, "omega": 1.2, "omega0": -0.5, "omega_dot": -5.2e-9,
		"m0": 1.5, "delta_n": 4.5e-9,
		"cuc": -8.7e-7, "cus": 1.1e-6, "crc": 180.0, "crs": -45.0,
		"cic": 5.8e-8, "cis": 1.2e-7, "idot": 3.2e-11,
		"toe": 400000.0, "t_gps": 400000.0,
	}
	var r := G.ephemeris_to_ecef(p)
	assert_true(r["ok"], "合理星历应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		var x0: float = float(v["x_m"])
		var y0: float = float(v["y_m"])
		var z0: float = float(v["z_m"])
		var norm := sqrt(x0 * x0 + y0 * y0 + z0 * z0)
		assert_between(norm, 26000000.0, 27200000.0, "轨道半径量级（GPS ≈ 26560 km）")
		# t+100 s 后位置实质变化：ECEF 中除卫星运动（≈3.87 km/s）外还含地球自转
		# （Ωₑ·Δt ≈ 0.42° → 位移量级 ~10⁵ m），故只断言"显著移动"与"仍在轨道带内"
		var p2 := p.duplicate()
		p2["t_gps"] = 400100.0
		var r2 := G.ephemeris_to_ecef(p2)
		assert_true(r2["ok"], "t+100s 应成功")
		if bool(r2["ok"]):
			var v2: Dictionary = r2["value"]
			var dx: float = float(v2["x_m"]) - x0
			var dy: float = float(v2["y_m"]) - y0
			var moved := sqrt(dx * dx + dy * dy)
			assert_true(moved > 1000.0, "100 秒位置实质变化（含地球自转项，实际 %.0f m）" % moved)
			var norm2 := sqrt(float(v2["x_m"]) ** 2 + float(v2["y_m"]) ** 2 + float(v2["z_m"]) ** 2)
			assert_between(norm2, 26000000.0, 27200000.0, "t+100s 轨道半径仍在带内")

func test_invalid_ephemeris() -> void:
	var r1 := G.ephemeris_to_ecef({"sqrt_a": 5153.0})
	assert_false(bool(r1["ok"]), "参数缺失应拒绝")
	var p2 := {"sqrt_a": 5153.79, "e": 1.0, "i0": 0.9, "omega": 0.0, "omega0": 0.0, "omega_dot": 0.0,
		"m0": 0.0, "delta_n": 0.0, "cuc": 0.0, "cus": 0.0, "crc": 0.0, "crs": 0.0, "cic": 0.0, "cis": 0.0,
		"toe": 0.0, "t_gps": 0.0}
	var r2 := G.ephemeris_to_ecef(p2)
	assert_false(bool(r2["ok"]), "e≥1 应拒绝")
	var p3 := p2.duplicate()
	p3["e"] = 0.01
	p3["sqrt_a"] = -1.0
	var r3 := G.ephemeris_to_ecef(p3)
	assert_false(bool(r3["ok"]), "√a≤0 应拒绝")
