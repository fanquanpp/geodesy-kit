# tests/adjustment/test_network.gd —— GK-M6-2 平面控制网间接平差回归（C5 测边网/边角网）
#
# 向量来源（docs/ARCHITECTURE.md §4 GK-M6【构造·判据明确】+ 本会话 numpy 独立复核）：
#   - 测边网：已知等边三角形 A(0,0)、B(1000,0)、C(500,866.025403784439)，未知 P(500,400)，
#     近似 (499.97,400.03)，3 条边长观测（真值+噪声 +8/−6/+4mm，σ=0.01m）→ 恢复
#     P=(500.008965371, 399.998454973)、V、μ0=0.371017784079、Qxx 对角 8.20048002923e-5 /
#     5.61621320769e-5、mp=4.36110742854mm；判据：BᵀPV≈0（加权残差正交）、Qxx 正定。
#     （设计矩阵在近似坐标处线性化——标准间接平差口径；numpy 参考取同一口径）
#   - 边角网：已知 A、B，未知 P(500,400)，2 测边 + 2 角度（含 +2″/−1.5″ 噪声，σ_deg=2）→
#     恢复 P=(500.002941595, 399.994578343)，角度残差 −0.0441838913888″/+0.728335410824″；
#     判据：BᵀPV≈0、恢复坐标差在噪声量级内。
#   - 解析线性化系数互检：本会话 numpy 数值导数 vs 解析式差 ≤2e-9（test_c5_angle_coefficients）。
extends "res://tests/test_case_base.gd"

const NW := preload("res://core/adjustment/network.gd")
const AK := preload("res://core/math/angles.gd")

const KNOWN_ABC := {"A": [0.0, 0.0], "B": [1000.0, 0.0], "C": [500.0, 866.025403784439]}
const APPROX_P := {"P": [499.97, 400.03]}
const DIST_OBS := [
	{"from": "A", "to": "P", "value": 640.320423743, "sigma": 0.01},
	{"from": "B", "to": "P", "value": 640.306423743, "sigma": 0.01},
	{"from": "C", "to": "P", "value": 466.029403784, "sigma": 0.01},
]
const KNOWN_AB := {"A": [0.0, 0.0], "B": [1000.0, 0.0]}
const ANG_DIST_OBS := [
	{"from": "A", "to": "P", "value": 640.317423743, "sigma": 0.01},
	{"from": "B", "to": "P", "value": 640.308423743, "sigma": 0.01},
]
const ANG_OBS := [
	{"at": "A", "back": "B", "front": "P", "value_deg": -38.6592526985, "sigma_s": 2.0},
	{"at": "B", "back": "A", "front": "P", "value_deg": 38.6593915874, "sigma_s": 2.0},
]

func test_c5_distance_network() -> void:
	var res := NW.adjust({"known": KNOWN_ABC, "approx": APPROX_P, "dist_obs": DIST_OBS})
	assert_true(bool(res.get("ok", false)), "C5 测边网应成功")
	if not bool(res.get("ok", false)):
		print("       C5 error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["x_P_m"]), 500.008965371, 1e-6, "恢复 P.x（真值 500）")
	assert_almost_eq(float(v["y_P_m"]), 399.998454973, 1e-6, "恢复 P.y（真值 400）")
	assert_vector_almost_eq(Array(v["v_dist_m"]), [-0.00196622882075, -0.00196593421015, -0.0024565151162], 1e-9, "边长残差 V")
	assert_almost_eq(float(v["mu0"]), 0.371017784079, 1e-9, "单位权中误差估计 μ0")
	assert_eq(int(v["dof"]), 1, "r = 3−2 = 1")
	assert_almost_eq(float(v["mp_P_mm"]), 4.36110742854, 1e-6, "点位中误差 4.361mm")
	# Qxx（顶层扩展键）与残差正交判据
	assert_true(res.has("qxx"), "应返回协因数阵扩展键")
	var qxx: Array = res["qxx"]
	assert_almost_eq(float((qxx[0] as PackedFloat64Array)[0]), 8.20048002923e-05, 1e-12, "Qxx[0][0]")
	assert_almost_eq(float((qxx[1] as PackedFloat64Array)[1]), 5.61621320769e-05, 1e-12, "Qxx[1][1]")
	assert_almost_eq(absf(float((qxx[0] as PackedFloat64Array)[1])), 0.0, 1e-8, "Qxx 非对角≈0（对称图形）")
	var ortho := _bt_pv(KNOWN_ABC, APPROX_P, DIST_OBS, [], Array(v["v_dist_m"]))
	assert_vector_almost_eq(ortho, [0.0, 0.0], 1e-9, "BᵀPV≈0（加权残差正交）")

func test_c5_angle_distance_network() -> void:
	var res := NW.adjust({"known": KNOWN_AB, "approx": APPROX_P, "dist_obs": ANG_DIST_OBS, "angle_obs": ANG_OBS})
	assert_true(bool(res.get("ok", false)), "C5 边角网应成功")
	if not bool(res.get("ok", false)):
		print("       C5 angle error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["x_P_m"]), 500.002941595, 1e-6, "边角网恢复 P.x")
	assert_almost_eq(float(v["y_P_m"]), 399.994578343, 1e-6, "边角网恢复 P.y")
	assert_eq(int(v["dof"]), 2, "r = 4−2 = 2")
	assert_vector_almost_eq(Array(v["v_angle_s"]), [-0.0441838913888, 0.728335410824], 1e-6, "角度残差（″）")
	# 判据：已知位置+噪声恢复坐标差在噪声量级内
	assert_between(float(v["x_P_m"]), 499.99, 500.02, "P.x 与真值差 ≤2cm")
	assert_between(float(v["y_P_m"]), 399.98, 400.02, "P.y 与真值差 ≤2cm")
	var ortho := _bt_pv(KNOWN_AB, APPROX_P, ANG_DIST_OBS, ANG_OBS,
			Array(v["v_dist_m"]) + Array(v["v_angle_rad"]))
	assert_vector_almost_eq(ortho, [0.0, 0.0], 1e-9, "边角网 BᵀPV≈0")

func test_c5_angle_coefficients_match_numeric_derivative() -> void:
	# 解析角度系数 vs 数值导数（本会话 numpy 互检口径的 GDScript 复现）
	var build := NW.build_design({
		"known": KNOWN_AB, "approx": APPROX_P,
		"angle_obs": [{"at": "A", "back": "B", "front": "P", "value_deg": 0.0, "sigma_s": 1.0}],
	})
	assert_eq(String(build.get("error", "")), "", "构建应成功")
	if String(build.get("error", "")) != "":
		return
	var row: PackedFloat64Array = build["B"][0]
	var eps := 1e-7
	var x0 := 499.97
	var y0 := 400.03
	var beta0 := _beta_at(x0, y0)
	var dx := (_beta_at(x0 + eps, y0) - beta0) / eps
	var dy := (_beta_at(x0, y0 + eps) - beta0) / eps
	assert_almost_eq(float(row[0]), dx, 5e-9, "∂β/∂x 解析=数值")
	assert_almost_eq(float(row[1]), dy, 5e-9, "∂β/∂y 解析=数值")

func _beta_at(px: float, py: float) -> float:
	# β = α(A→P) − α(A→B)（弧度，绕回 (−π,π]）
	var ap := atan2(px - 0.0, py - 0.0)
	var d := ap - PI / 2.0
	while d > PI:
		d -= 2.0 * PI
	while d < -PI:
		d += 2.0 * PI
	return d

func test_c5_error_paths() -> void:
	var r1 := NW.adjust({
		"known": {"A": [0.0, 0.0]}, "approx": {"P": [1.0, 1.0]},
		"dist_obs": [{"from": "A", "to": "Q", "value": 10.0, "sigma": 0.1}],
	})
	assert_false(bool(r1.get("ok", true)), "观测引用未定义点应失败")
	var r2 := NW.adjust({
		"known": {"A": [0.0, 0.0]}, "approx": {"P": [1.0, 1.0]},
		"angle_obs": [{"at": "A", "back": "A", "front": "P", "value_deg": 30.0, "sigma_deg": 2.0}],
	})
	assert_false(bool(r2.get("ok", true)), "at/back/front 同名应失败")
	var r3 := NW.adjust({
		"approx": {"P": [1.0, 1.0]},
		"dist_obs": [{"from": "A", "to": "P", "value": 10.0, "sigma": 0.1}],
	})
	assert_false(bool(r3.get("ok", true)), "缺已知点应失败（C5 固定基准）")
	var r4 := NW.adjust({
		"known": {"A": [0.0, 0.0], "B": [10.0, 0.0]}, "approx": {"P": [1.0, 1.0]},
		"dist_obs": [{"from": "A", "to": "P", "value": 10.0, "sigma": 0.0}],
	})
	assert_false(bool(r4.get("ok", true)), "sigma 非正应失败")

## 判据工具：BᵀPV（加权残差正交性，v 为与观测同序的残差向量）
func _bt_pv(known: Dictionary, approx: Dictionary, dist_obs: Array, angle_obs: Array, v: Array) -> Array:
	var build := NW.build_design({"known": known, "approx": approx, "dist_obs": dist_obs, "angle_obs": angle_obs})
	if String(build.get("error", "")) != "":
		return [NAN, NAN]
	var B: Array = build["B"]
	var p: PackedFloat64Array = build["p"]
	var t: int = (B[0] as PackedFloat64Array).size()
	var out := PackedFloat64Array()
	out.resize(t)
	for i in B.size():
		var bi: PackedFloat64Array = B[i]
		for j in t:
			out[j] += p[i] * bi[j] * float(v[i])
	return Array(out)
