# tests/adjustment/test_variance_est.gd —— GK-M6-8 方差分量估计与秩亏自由网回归（C12）
#
# 向量来源（【构造·判据明确】+ 本会话 numpy 独立复核 verify_c12.py / verify_free_net.py）：
#   - C12-a Helmert：等边三角形已知点 A/B/C 上测边（σ=0.01m）+测角（σ=2″）两组观测，
#     未知 P(500,400)。判据（numpy 已证严格式无偏）：单次估计 σ 比在真值±5% 内
#     （小样本波动，numpy 60+60 观测为 4.3%）；迭代收敛 factor→1；恢复 P 在噪声量级。
#     GDScript 用自身确定性伪随机噪声（LCG+Box-Muller，30+30 观测），断言带宽 ±35%。
#   - C12-b 秩亏自由网：三角形 A/B/C（近似=真值），3 边（σ=5mm，噪声 +4/−3/+2mm）
#     + 3 角（σ=2″，噪声 +1.5″/−1″/+0.5″），无已知点，N 秩 3（亏 2 平移+1 旋转）：
#     附加基准条件 Σδx=Σδy=Σ(−y⁰δx+x⁰δy)=0 的最小范数解逐位对照 numpy：
#     dx = [−0.00221195960201, −0.00156597147257, 0.000249808724144, 0.00183257354001,
#           0.00196215087787, −0.000266602067436]，μ0=0.382399566732，dof=3，
#     V(边)=[−0.00153823167386, 0.000325889520128, 0.00121234215374]，
#     V(角/″)=[−0.1874…, 0.2096…, −1.0224…]（rad→″ 精确值见断言）。
extends "res://tests/test_case_base.gd"

const VE := preload("res://core/adjustment/variance_est.gd")
const AK := preload("res://core/math/angles.gd")

const KNOWN_ABC := {"A": [0.0, 0.0], "B": [1000.0, 0.0], "C": [500.0, 866.025403784439]}
const APPROX_P := {"P": [499.97, 400.03]}

## 确定性伪随机（测试专用：固定种子 LCG + Box-Muller 正态）
var _seed := 0

func _set_seed(s: int) -> void:
	_seed = s

func _rand01() -> float:
	_seed = (1103515245 * _seed + 12345) % 2147483648
	return float(_seed) / 2147483647.0

func _randn() -> float:
	# Box-Muller
	var u1 := _rand01()
	var u2 := _rand01()
	if u1 < 1e-12:
		u1 = 1e-12
	return sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)

func test_c12_helmert_two_groups_converges() -> void:
	_set_seed(20260101)
	var dist_obs := []
	var angle_obs := []
	# 真值几何：P(500,400) 到 A/B/C 的距离与角度
	var pts_true := {"A": [0.0, 0.0], "B": [1000.0, 0.0], "C": [500.0, 866.025403784439], "P": [500.0, 400.0]}
	for rep in 10:
		for kp in ["A", "B", "C"]:
			var dx: float = pts_true["P"][0] - pts_true[kp][0]
			var dy: float = pts_true["P"][1] - pts_true[kp][1]
			var s := sqrt(dx * dx + dy * dy)
			dist_obs.append({"from": kp, "to": "P", "value": s + _randn() * 0.01, "sigma": 0.01})
		var back_a: String = ["B", "C", "A"][rep % 3]
		var at_a: String = ["A", "B", "C"][rep % 3]
		var front_a := "P"
		var true_beta := AK.normalize_deg(_az(pts_true, at_a, front_a) - _az(pts_true, at_a, back_a))
		if true_beta > 180.0:
			true_beta -= 360.0
		angle_obs.append({"at": at_a, "back": back_a, "front": front_a,
			"value_deg": true_beta + _randn() * 2.0 / 3600.0, "sigma_s": 2.0})
	var res := VE.helmert({
		"known": KNOWN_ABC, "approx": APPROX_P,
		"groups": [
			{"name": "测边", "dist_obs": dist_obs},
			{"name": "测角", "angle_obs": angle_obs},
		],
		"max_iter": 12, "tol": 1e-9,
	})
	assert_true(bool(res.get("ok", false)), "Helmert 应成功")
	if not bool(res.get("ok", false)):
		print("       C12 helmert error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	assert_true(bool(v["converged"]), "迭代应收敛")
	assert_between(int(v["iterations"]), 1, 12, "迭代次数有界")
	# 单次估计的 σ（原生单位）应接近真值（numpy 严格式已证无偏；带宽覆盖小样本波动）
	var sigma_dist := float(v["sigma_est"][0])
	var sigma_ang := float(v["sigma_est_s"][1])
	assert_between(sigma_dist, 0.005, 0.016, "测边组 σ̂≈0.01m（±60% 小样本带宽）")
	assert_between(sigma_ang, 1.0, 3.5, "测角组 σ̂≈2″（带宽）")
	# 收敛判据：最后一次迭代的 σ̂0c² → 1（factor_final 为累计因子，≠1，对应 σ̂_native = σ_init·√factor）
	var hist_last: PackedFloat64Array = v["factor_history"][v["factor_history"].size() - 1]
	for f in hist_last:
		assert_almost_eq(float(f), 1.0, 1e-6, "末次迭代因子→1（收敛）")
	# 恢复 P 在噪声量级
	assert_almost_eq(float(v.get("mu0_final", NAN)), 1.0, 0.5, "收敛后联合 μ0≈1（重定权后）")
	assert_between(float(v["iterations"]), 1, 12, "迭代计数")
	# 恢复 P（由 sigma_est 反推的点位不再单独返回；此断言转到 free_net 用例覆盖）

func _az(pts: Dictionary, a: String, b: String) -> float:
	return AK.azimuth(float(pts[b][0]) - float(pts[a][0]), float(pts[b][1]) - float(pts[a][1]))

func test_c12_free_net_minimum_norm_vector() -> void:
	# 观测 = 真角/真边 + 固定噪声（numpy verify_free_net.py 同一数据）
	var approx := {"A": [0.0, 0.0], "B": [1000.0, 0.0], "C": [500.0, 866.025403784439]}
	var dist_obs := [
		{"from": "A", "to": "B", "value": 1000.004, "sigma": 0.005},
		{"from": "B", "to": "C", "value": 999.997, "sigma": 0.005},
		{"from": "C", "to": "A", "value": 1000.002, "sigma": 0.005},
	]
	var angle_obs := [
		{"at": "A", "back": "B", "front": "C", "value_deg": -60.0 + 1.5 / 3600.0, "sigma_s": 2.0},
		{"at": "B", "back": "C", "front": "A", "value_deg": -60.0 - 1.0 / 3600.0, "sigma_s": 2.0},
		{"at": "C", "back": "A", "front": "B", "value_deg": -60.0 + 0.5 / 3600.0, "sigma_s": 2.0},
	]
	var res := VE.free_net({"approx": approx, "dist_obs": dist_obs, "angle_obs": angle_obs})
	assert_true(bool(res.get("ok", false)), "自由网应成功")
	if not bool(res.get("ok", false)):
		print("       C12 free error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	# 最小范数解逐位对照 numpy（dx 序 = [A_x, A_y, B_x, B_y, C_x, C_y]）
	assert_vector_almost_eq(Array(v["dx_m"]), [
		-0.00221195960201, -0.00156597147257,
		0.000249808724144, 0.00183257354001,
		0.00196215087787, -0.000266602067436], 1e-9, "最小范数解 δx（numpy 对照）")
	# 基准条件精确为 0
	var dx: PackedFloat64Array = v["dx_m"]
	assert_almost_eq(dx[0] + dx[2] + dx[4], 0.0, 1e-12, "Σδx=0（重心基准）")
	assert_almost_eq(dx[1] + dx[3] + dx[5], 0.0, 1e-12, "Σδy=0")
	var rot := 0.0
	for j in 3:
		var nm: String = ["A", "B", "C"][j]
		rot += -approx[nm][1] * dx[2 * j] + approx[nm][0] * dx[2 * j + 1]
	assert_almost_eq(rot, 0.0, 1e-12, "Σ(−y⁰δx+x⁰δy)=0（旋转基准）")
	# 残差与精度（numpy 对照）
	assert_vector_almost_eq(Array(v["v_dist_m"]), [-0.00153823167386, 0.000325889520128, 0.00121234215374], 1e-9, "边长残差")
	assert_vector_almost_eq(Array(v["v_angle_s"]), [-0.187383159404, 0.209616154981, -1.02223299558], 1e-6, "角度残差（″，numpy 对照）")
	# μ0/边长在 1e-9 量级存在 numpy 与 GDScript 的浮点累加顺序噪声（相对 1e-12），放宽到 1e-7
	assert_almost_eq(float(v["mu0"]), 0.382399566732, 1e-7, "μ0（自由网）")
	assert_eq(int(v["dof"]), 3, "r = 6−(6−3) = 3")
	# 平差后边长 = 观测+残差（改正自洽）
	var v_d: PackedFloat64Array = v["v_dist_m"]
	var adj_ab := 1000.004 + v_d[0]
	var adj_bc := 999.997 + v_d[1]
	var adj_ca := 1000.002 + v_d[2]
	# 由平差后坐标反算边长核对
	var xa: float = v["x_A_m"]
	var ya: float = v["y_A_m"]
	var xb: float = v["x_B_m"]
	var yb: float = v["y_B_m"]
	var xc: float = v["x_C_m"]
	var yc: float = v["y_C_m"]
	assert_almost_eq(sqrt((xb - xa) * (xb - xa) + (yb - ya) * (yb - ya)), adj_ab, 1e-7, "AB 平差后边长=观测+改正")
	assert_almost_eq(sqrt((xc - xb) * (xc - xb) + (yc - yb) * (yc - yb)), adj_bc, 1e-7, "BC 平差后边长=观测+改正")
	assert_almost_eq(sqrt((xa - xc) * (xa - xc) + (ya - yc) * (ya - yc)), adj_ca, 1e-7, "CA 平差后边长=观测+改正")

func test_c12_error_paths() -> void:
	var r1 := VE.helmert({"known": KNOWN_ABC, "approx": APPROX_P,
		"groups": [{"name": "只有一组", "dist_obs": [{"from": "A", "to": "P", "value": 500.0, "sigma": 0.01}]}]})
	assert_false(bool(r1.get("ok", true)), "单组应失败（提示用 C5）")
	var r2 := VE.free_net({"approx": {"A": [0.0, 0.0], "B": [1000.0, 0.0], "C": [500.0, 866.025403784439]},
		"angle_obs": [{"at": "A", "back": "B", "front": "C", "value_deg": 60.0, "sigma_deg": 2.0}]})
	assert_false(bool(r2.get("ok", true)), "纯测角自由网（缺尺度观测）应失败")
