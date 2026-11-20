# tests/adjustment/test_gnss_net.gd —— GK-M6-7 GNSS 向量网平差回归（C11）
#
# 向量来源（【构造·判据明确】+ 本会话 numpy 独立复核）：
#   - 已知 G1(0,0,0)；未知 G2(1000,0,0)、G3(1000,1500,50)；3 条基线加 mm 级噪声（σ=0.01m）：
#     G1→G2=(1000.004,−0.003,0.002)、G1→G3=(1000.002,1500.004,49.997)、G2→G3=(−0.003,0.002,0.004)。
#     近似 G2=(999.95,0.02,0.01)、G3=(1000.02,1499.97,50.03) → 恢复
#     G2=(1000.00433333, −0.00133333, −0.001)、G3=(1000.00166667, 1500.00233333, 50)、
#     μ0=0.344802681092、dof=3；判据：已知基线+噪声恢复坐标差（残差即恢复差，逐位断言）。
#   - 自由网（datum=free）：无已知点，ΣδX=ΣδY=ΣδZ=0 最小范数解，基线恢复在噪声量级内。
extends "res://tests/test_case_base.gd"

const GN := preload("res://core/adjustment/gnss_net.gd")

const KNOWN_G1 := {"G1": [0.0, 0.0, 0.0]}
const APPROX_G := {"G2": [999.95, 0.02, 0.01], "G3": [1000.02, 1499.97, 50.03]}
const BASELINES := [
	{"from": "G1", "to": "G2", "dx": 1000.004, "dy": -0.003, "dz": 0.002, "sigma": 0.01},
	{"from": "G1", "to": "G3", "dx": 1000.002, "dy": 1500.004, "dz": 49.997, "sigma": 0.01},
	{"from": "G2", "to": "G3", "dx": -0.003, "dy": 1500.002, "dz": 50.004, "sigma": 0.01},
]

func test_c11_fixed_datum_authoritative() -> void:
	var res := GN.adjust({"known": KNOWN_G1, "approx": APPROX_G, "baselines": BASELINES, "datum": "fixed"})
	assert_true(bool(res.get("ok", false)), "C11 固定基准应成功")
	if not bool(res.get("ok", false)):
		print("       C11 error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	# 恢复坐标（本会话 numpy 独立复核值）
	assert_almost_eq(float(v["X_G2_m"]), 1000.00433333, 1e-6, "恢复 G2.X")
	assert_almost_eq(float(v["Y_G2_m"]), -0.00133333333334, 1e-6, "恢复 G2.Y")
	assert_almost_eq(float(v["Z_G2_m"]), -0.001, 1e-6, "恢复 G2.Z")
	assert_almost_eq(float(v["X_G3_m"]), 1000.00166667, 1e-6, "恢复 G3.X")
	assert_almost_eq(float(v["Y_G3_m"]), 1500.00233333, 1e-6, "恢复 G3.Y")
	assert_almost_eq(float(v["Z_G3_m"]), 50.0, 1e-6, "恢复 G3.Z")
	assert_eq(int(v["dof"]), 3, "r = 9−6 = 3")
	assert_almost_eq(float(v["mu0"]), 0.344802681092, 1e-9, "μ0（单位权估计）")
	# 判据：已知基线+噪声恢复坐标差——残差逐位断言（v = 恢复差 − 观测基线）
	assert_vector_almost_eq(Array(v["v_m"]), [
		0.000333333333311, 0.00166666666666, -0.003,
		-0.000333333333311, -0.00166666666666, 0.003,
		0.000333333333311, 0.00166666666666, -0.003], 1e-9, "基线分量残差")
	# 恢复坐标差与真值差在噪声量级内
	assert_between(float(v["X_G2_m"]) - 1000.0, -0.01, 0.01, "G2.X 与真值差 ≤1cm")
	assert_between(float(v["Y_G3_m"]) - 1500.0, -0.01, 0.01, "G3.Y 与真值差 ≤1cm")

func test_c11_free_datum_minimum_norm() -> void:
	# 无已知点：全部点入 approx（含 G1），ΣδX=ΣδY=ΣδZ=0（最小范数解），基线差恢复在噪声量级内
	var approx_all := {"G1": [0.001, -0.002, 0.001], "G2": [999.95, 0.02, 0.01], "G3": [1000.02, 1499.97, 50.03]}
	var res := GN.adjust({"approx": approx_all, "baselines": BASELINES, "datum": "free"})
	assert_true(bool(res.get("ok", false)), "C11 自由网应成功")
	if not bool(res.get("ok", false)):
		print("       C11 free error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	# 重心基准：ΣδX = 0 → 各点平差后坐标之和 = 近似坐标之和
	assert_almost_eq(float(v["X_G1_m"]) + float(v["X_G2_m"]) + float(v["X_G3_m"]),
			0.001 + 999.95 + 1000.02, 1e-9, "ΣδX=0（重心基准）")
	assert_almost_eq(float(v["Y_G1_m"]) + float(v["Y_G2_m"]) + float(v["Y_G3_m"]),
			-0.002 + 0.02 + 1499.97, 1e-9, "ΣδY=0")
	assert_almost_eq(float(v["Z_G1_m"]) + float(v["Z_G2_m"]) + float(v["Z_G3_m"]),
			0.001 + 0.01 + 50.03, 1e-9, "ΣδZ=0")
	# 基线差恢复（真值：G2→G3 = (0, 1500, 50)）
	assert_between(float(v["X_G3_m"]) - float(v["X_G2_m"]), -0.01, 0.01, "G2→G3 基线 dx 恢复在噪声量级（真值 0）")
	assert_almost_eq(float(v["Y_G3_m"]) - float(v["Y_G2_m"]), 1500.0, 0.02, "G2→G3 基线 dy 恢复≈1500（噪声量级）")
	assert_almost_eq(float(v["Z_G3_m"]) - float(v["Z_G2_m"]), 50.0, 0.02, "G2→G3 基线 dz 恢复≈50（噪声量级）")
	assert_eq(int(v["dof"]), 3, "自由网 r = 9−9+3 = 3")

func test_c11_error_paths() -> void:
	var r1 := GN.adjust({"approx": APPROX_G, "baselines": BASELINES, "datum": "fixed"})
	assert_false(bool(r1.get("ok", true)), "固定基准缺已知点应失败")
	var r2 := GN.adjust({"known": KNOWN_G1, "approx": APPROX_G, "baselines": BASELINES, "datum": "xyz"})
	assert_false(bool(r2.get("ok", true)), "未知 datum 应失败")
	var r3 := GN.adjust({"known": KNOWN_G1, "approx": {"G2": [1.0, 2.0, 3.0], "G9": [4.0, 5.0, 6.0]},
		"baselines": BASELINES, "datum": "fixed"})
	assert_false(bool(r3.get("ok", true)), "孤立未知点（无基线）应失败")
	var r4 := GN.adjust({"known": KNOWN_G1, "approx": APPROX_G, "baselines": []})
	assert_false(bool(r4.get("ok", true)), "无基线应失败")
	var r5 := GN.adjust({"known": KNOWN_G1, "approx": APPROX_G,
		"baselines": [{"from": "G1", "to": "G2", "dx": 1.0, "dy": 0.0, "dz": 0.0, "sigma": 0.0}]})
	assert_false(bool(r5.get("ok", true)), "非正 sigma 应失败")
