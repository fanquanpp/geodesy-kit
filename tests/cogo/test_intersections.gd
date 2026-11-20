# tests/cogo/test_intersections.gd —— GK-M5 交会（M5-2，向量来源：ARCHITECTURE.md §4 GK-M5【构造·自洽检核】）
# 权威向量：
#   B1 方位交会 A(1000,1000) az1=30°、B(2000,1200) az2=309.3986°→P=(1400.0000,1692.8203)
#     （az2 为架构表 4 位舍入值；全精度 az2=309.398561155°，舍入使 P 偏 ~5e-4，故该条用 1e-3 容差）
#   B2 距离交会 A(1000,1000) dA=700、B(1800,1050) dB=600→P₊(1512.6058,523.3079)/P₋(1449.2619,1536.8088)
#     （向量 4 位舍入，断言容差 5e-4；另以 dA/dB 反算回收做 1e-9 全精度检核）
extends "res://tests/test_case_base.gd"

const I := preload("res://core/cogo/intersections.gd")

func _az(dx: float, dy: float) -> float:
	return GKAngles.azimuth(dx, dy)

func test_b1_azimuth_authoritative_vector() -> void:
	var py := 1000.0 + 400.0 * sqrt(3.0)
	# 全精度 az2 → P 精确回收
	var az2_exact := _az(1400.0 - 2000.0, py - 1200.0)
	var r := I.b1_azimuth({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "az1_deg": 30.0,
		"x_b_m": 2000.0, "y_b_m": 1200.0, "az2_deg": az2_exact,
	})
	assert_true(bool(r.get("ok", false)), "B1 方位交会成功（全精度 az2）")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_m"]), 1400.0, 1e-9, "B1 x_m = 1400")
		assert_almost_eq(float(v["y_m"]), py, 1e-9, "B1 y_m = 1692.8203…")
		assert_almost_eq(float(v["gamma_deg"]), 80.601438845, 1e-6, "B1 交会角 γ")
		assert_false(bool(v["weak_angle"]), "γ=80.6° 图形强度正常")
	# 架构表舍入向量 az2=309.3986 → 1e-3 容差
	var r2 := I.b1_azimuth({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "az1_deg": 30.0,
		"x_b_m": 2000.0, "y_b_m": 1200.0, "az2_deg": 309.3986,
	})
	assert_true(bool(r2.get("ok", false)), "B1 方位交会成功（舍入 az2）")
	if bool(r2.get("ok", false)):
		var v2: Dictionary = r2["value"]
		assert_almost_eq(float(v2["x_m"]), 1400.0, 1e-3, "B1 舍入向量 x（1400.0000）")
		assert_almost_eq(float(v2["y_m"]), 1692.8203, 1e-3, "B1 舍入向量 y（1692.8203）")

func test_b1_azimuth_parallel_error() -> void:
	var r := I.b1_azimuth({
		"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 45.0,
		"x_b_m": 100.0, "y_b_m": 100.0, "az2_deg": 45.0,
	})
	assert_false(bool(r.get("ok", true)), "平行方位线应失败")
	assert_true(String(r.get("error", "")).contains("平行"), "平行中文错误")

func test_b1_azimuth_weak_angle_hint() -> void:
	# 近平行：A(0,0) az 0°，B(100,10000) az 179° → P=(0, 10000+100/tan1°)，γ=1.0° < 15°
	var r := I.b1_azimuth({
		"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 0.0,
		"x_b_m": 100.0, "y_b_m": 10000.0, "az2_deg": 179.0,
	})
	assert_true(bool(r.get("ok", false)), "弱图形仍给出结果")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_true(bool(v["weak_angle"]), "γ<15° 应置弱精度提示")
		assert_almost_eq(float(v["gamma_deg"]), 1.0, 1e-6, "γ = 1.0°")
		assert_almost_eq(float(v["x_m"]), 0.0, 1e-6, "弱图形 P x")
		assert_almost_eq(float(v["y_m"]), 10000.0 + 100.0 / tan(deg_to_rad(1.0)), 1e-6, "弱图形 P y")

func test_b1_angles_consistent_with_azimuth_vector() -> void:
	var py := 1000.0 + 400.0 * sqrt(3.0)
	var az_ab := _az(1000.0, 200.0)
	var az_ba := GKAngles.normalize_deg(az_ab + 180.0)
	var az_bp := _az(1400.0 - 2000.0, py - 1200.0)
	var beta1 := az_ab - 30.0
	var beta2 := az_bp - az_ba
	var r := I.b1_angles({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "x_b_m": 2000.0, "y_b_m": 1200.0,
		"beta1_deg": beta1, "beta2_deg": beta2, "side": -1,
	})
	assert_true(bool(r.get("ok", false)), "角度式前方交会成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_m"]), 1400.0, 1e-9, "角度式 P x 与方位式一致")
		assert_almost_eq(float(v["y_m"]), py, 1e-9, "角度式 P y 与方位式一致")
		assert_almost_eq(float(v["gamma_deg"]), 180.0 - beta1 - beta2, 1e-12, "γ = 180−β₁−β₂")

func test_forward_by_angles_side_left_right() -> void:
	# A(0,0) B(0,100)：az_AB=0。side=右(+1) → α_AP = +30° → P 在东（x>0）；side=左 → x<0
	var rr := I.forward_by_angles(0.0, 0.0, 0.0, 100.0, 30.0, 40.0, 1)
	assert_false(rr.is_empty(), "side=右 有解")
	assert_true(float(rr["x"]) > 0.0, "右侧交点 x>0")
	var ll := I.forward_by_angles(0.0, 0.0, 0.0, 100.0, 30.0, 40.0, -1)
	assert_false(ll.is_empty(), "side=左 有解")
	assert_true(float(ll["x"]) < 0.0, "左侧交点 x<0")
	# 左右两解关于 AB 线对称（|x| 相等、y 相等）
	assert_almost_eq(absf(float(rr["x"])), absf(float(ll["x"])), 1e-9, "左右解 |x| 对称")
	assert_almost_eq(float(rr["y"]), float(ll["y"]), 1e-9, "左右解 y 相同")

func test_b1_side_consistent() -> void:
	var py := 1000.0 + 400.0 * sqrt(3.0)
	var beta_a := _az(1000.0, 200.0) - 30.0
	var gamma := I.angle_at(1400.0, py, 1000.0, 1000.0, 2000.0, 1200.0)
	var r := I.b1_side({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "x_b_m": 2000.0, "y_b_m": 1200.0,
		"beta_a_deg": beta_a, "gamma_deg": gamma, "side": -1,
	})
	assert_true(bool(r.get("ok", false)), "侧方交会成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_m"]), 1400.0, 1e-9, "侧方交会 P x")
		assert_almost_eq(float(v["y_m"]), py, 1e-9, "侧方交会 P y")
		assert_almost_eq(float(v["beta_b_deg"]), 180.0 - beta_a - gamma, 1e-12, "β_B 内角和推算")
	# 退化：β_A + γ ≥ 180 应失败
	var bad := I.b1_side({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "x_b_m": 2000.0, "y_b_m": 1200.0,
		"beta_a_deg": 100.0, "gamma_deg": 100.0, "side": -1,
	})
	assert_false(bool(bad.get("ok", true)), "β_A+γ≥180 应失败")
	assert_true(String(bad.get("error", "")).contains("三角形"), "退化中文错误")

func test_b1_resection_authoritative_self_consistent() -> void:
	# 构造：已知点顺时针序 F(2000,1200)→S(1000,1000)→T(1500,2000)，P=(1600,1500)
	var fx := 2000.0
	var fy := 1200.0
	var sx := 1000.0
	var sy := 1000.0
	var tx := 1500.0
	var ty := 2000.0
	var px := 1600.0
	var py := 1500.0
	var az_f := _az(fx - px, fy - py)
	var az_s := _az(sx - px, sy - py)
	var az_t := _az(tx - px, ty - py)
	var alpha := GKAngles.normalize_deg(az_s - az_f)
	var beta := GKAngles.normalize_deg(az_t - az_s)
	assert_true(alpha > 0.0 and alpha < 180.0, "α 在 (0,180)")
	assert_true(beta > 0.0 and beta < 180.0, "β 在 (0,180)")
	var r := I.b1_resection({
		"x_a_m": fx, "y_a_m": fy, "x_b_m": sx, "y_b_m": sy,
		"x_c_m": tx, "y_c_m": ty, "alpha_deg": alpha, "beta_deg": beta,
	})
	assert_true(bool(r.get("ok", false)), "后方交会成功")
	if not bool(r.get("ok", false)):
		print("resection error: " + String(r.get("error", "")))
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["x_m"]), px, 1e-6, "后方交会回收 P x")
	assert_almost_eq(float(v["y_m"]), py, 1e-6, "后方交会回收 P y")
	assert_almost_eq(float(v["pa_m"]), I.inv_len(px, py, fx, fy), 1e-9, "PA 距离")
	assert_almost_eq(float(v["pb_m"]), I.inv_len(px, py, sx, sy), 1e-9, "PB 距离")
	assert_almost_eq(float(v["pc_m"]), I.inv_len(px, py, tx, ty), 1e-9, "PC 距离")
	assert_false(bool(v["weak_angle"]), "正常图形无弱精度提示")

func test_b1_resection_danger_circle_chinese_warning() -> void:
	# 危险圆构造：A、B、C、P 四点共圆（圆心原点 R=100，方位 0°/80°/160°/240°）
	# P 在圆上任一点时 ∠APB=∠BPC=40°（弦 80° 圆心角的圆周角），两定位圆重合 → 无数解
	var ax := 0.0
	var ay := 100.0
	var bx := 100.0 * sin(deg_to_rad(80.0))
	var by := 100.0 * cos(deg_to_rad(80.0))
	var cx := 100.0 * sin(deg_to_rad(160.0))
	var cy := 100.0 * cos(deg_to_rad(160.0))
	var r := I.b1_resection({
		"x_a_m": ax, "y_a_m": ay, "x_b_m": bx, "y_b_m": by,
		"x_c_m": cx, "y_c_m": cy, "alpha_deg": 40.0, "beta_deg": 40.0,
	})
	assert_false(bool(r.get("ok", true)), "危险圆应判失败")
	assert_true(String(r.get("error", "")).contains("危险圆"), "危险圆中文警告")
	assert_true(String(r.get("error", "")).contains("共圆"), "警告含成因说明")

func test_b1_resection_collinear_error() -> void:
	var r := I.b1_resection({
		"x_a_m": 0.0, "y_a_m": 0.0, "x_b_m": 100.0, "y_b_m": 100.0,
		"x_c_m": 200.0, "y_c_m": 200.0, "alpha_deg": 50.0, "beta_deg": 50.0,
	})
	assert_false(bool(r.get("ok", true)), "已知点共线应失败")
	assert_true(String(r.get("error", "")).contains("共线"), "共线中文错误")

func test_b1_resection_weak_angle_hint() -> void:
	# 弱图形：P=(100,571.5) 对 A1(200,0)、B1(100,10)、C1(0,0) 的观测角约 9.9° < 15°
	var px := 100.0
	var py := 571.5052
	var ax := 200.0
	var ay := 0.0
	var bx := 100.0
	var by := 10.0
	var cx := 0.0
	var cy := 0.0
	var alpha := GKAngles.normalize_deg(_az(bx - px, by - py) - _az(ax - px, ay - py))
	var beta := GKAngles.normalize_deg(_az(cx - px, cy - py) - _az(bx - px, by - py))
	assert_true(alpha < 15.0 and beta < 15.0, "构造出弱图形观测角")
	var r := I.b1_resection({
		"x_a_m": ax, "y_a_m": ay, "x_b_m": bx, "y_b_m": by,
		"x_c_m": cx, "y_c_m": cy, "alpha_deg": alpha, "beta_deg": beta,
	})
	assert_true(bool(r.get("ok", false)), "弱图形仍给出结果")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_true(bool(v["weak_angle"]), "观测角<15° 置弱精度提示")
		assert_almost_eq(float(v["x_m"]), px, 1e-4, "弱图形 P x 回收")
		assert_almost_eq(float(v["y_m"]), py, 1e-4, "弱图形 P y 回收")

func test_b2_dist_dist_authoritative_vector() -> void:
	var r := I.b2_dist_dist({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "d_a_m": 700.0,
		"x_b_m": 1800.0, "y_b_m": 1050.0, "d_b_m": 600.0, "side": 1,
	})
	assert_true(bool(r.get("ok", false)), "B2 距离交会成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	# 权威向量（4 位舍入）：P₊(1512.6058,523.3079)
	assert_almost_eq(float(v["x_m"]), 1512.6058, 5e-4, "B2 P₊ x（右解，side=+1）")
	assert_almost_eq(float(v["y_m"]), 523.3079, 5e-4, "B2 P₊ y")
	# 另一解 P₋(1449.2619,1536.8088)
	assert_almost_eq(float(v["alt_x_m"]), 1449.2619, 5e-4, "B2 P₋ x（左解）")
	assert_almost_eq(float(v["alt_y_m"]), 1536.8088, 5e-4, "B2 P₋ y")
	# 全精度检核：两解到已知点距离回收
	assert_almost_eq(float(v["d_a_check_m"]), 700.0, 1e-9, "P₊ 回收 D_A=700")
	assert_almost_eq(float(v["d_b_check_m"]), 600.0, 1e-9, "P₊ 回收 D_B=600")
	assert_almost_eq(I.inv_len(float(v["alt_x_m"]), float(v["alt_y_m"]), 1000.0, 1000.0), 700.0, 1e-9, "P₋ 回收 D_A=700")
	assert_almost_eq(I.inv_len(float(v["alt_x_m"]), float(v["alt_y_m"]), 1800.0, 1050.0), 600.0, 1e-9, "P₋ 回收 D_B=600")
	assert_between(float(v["gamma_deg"]), 75.0, 76.0, "B2 交会角约 75.7°")

func test_b2_dist_dist_side_left_selects_other_solution() -> void:
	var r := I.b2_dist_dist({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "d_a_m": 700.0,
		"x_b_m": 1800.0, "y_b_m": 1050.0, "d_b_m": 600.0, "side": -1,
	})
	assert_true(bool(r.get("ok", false)), "side=左 成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_m"]), 1449.2619, 5e-4, "side=左 主解 = P₋")
		assert_almost_eq(float(v["y_m"]), 1536.8088, 5e-4, "side=左 主解")
		assert_almost_eq(float(v["alt_x_m"]), 1512.6058, 5e-4, "side=左 另一解 = P₊")

func test_b2_dist_dist_errors() -> void:
	var r1 := I.b2_dist_dist({
		"x_a_m": 0.0, "y_a_m": 0.0, "d_a_m": 10.0,
		"x_b_m": 1000.0, "y_b_m": 0.0, "d_b_m": 10.0, "side": 1,
	})
	assert_false(bool(r1.get("ok", true)), "两圆外离应失败")
	assert_true(String(r1.get("error", "")).length() > 0, "外离中文错误")
	var r2 := I.b2_dist_dist({
		"x_a_m": 5.0, "y_a_m": 5.0, "d_a_m": 10.0,
		"x_b_m": 5.0, "y_b_m": 5.0, "d_b_m": 10.0, "side": 1,
	})
	assert_false(bool(r2.get("ok", true)), "两已知点重合应失败")

func test_b2_dist_dist_tangent_degenerate() -> void:
	# 外切：A(0,0) dA=30，B(60,0) dB=30 → 切点 (30,0)，唯一解
	var r := I.b2_dist_dist({
		"x_a_m": 0.0, "y_a_m": 0.0, "d_a_m": 30.0,
		"x_b_m": 60.0, "y_b_m": 0.0, "d_b_m": 30.0, "side": 1,
	})
	assert_true(bool(r.get("ok", false)), "外切成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_true(bool(v["tangent"]), "相切标记")
		assert_almost_eq(float(v["x_m"]), 30.0, 1e-9, "切点 x")
		assert_almost_eq(float(v["y_m"]), 0.0, 1e-9, "切点 y")

func test_b2_az_dist_exact_two_branches() -> void:
	# A(0,0) az=90°（正东），B(500,400)，D_B=500 → t=200/800，两解 (200,0)/(800,0)
	var rn := I.b2_az_dist({
		"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 90.0,
		"x_b_m": 500.0, "y_b_m": 400.0, "d_b_m": 500.0, "branch": "near",
	})
	assert_true(bool(rn.get("ok", false)), "方位-距离近端成功")
	if bool(rn.get("ok", false)):
		var vn: Dictionary = rn["value"]
		assert_almost_eq(float(vn["x_m"]), 200.0, 1e-9, "近端 x = 200")
		assert_almost_eq(float(vn["y_m"]), 0.0, 1e-9, "近端 y = 0")
		assert_almost_eq(float(vn["t_m"]), 200.0, 1e-9, "近端 t = 200")
		assert_almost_eq(float(vn["d_b_check_m"]), 500.0, 1e-9, "近端 |PB| = 500")
	var rf := I.b2_az_dist({
		"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 90.0,
		"x_b_m": 500.0, "y_b_m": 400.0, "d_b_m": 500.0, "branch": "far",
	})
	assert_true(bool(rf.get("ok", false)), "方位-距离远端成功")
	if bool(rf.get("ok", false)):
		var vf: Dictionary = rf["value"]
		assert_almost_eq(float(vf["x_m"]), 800.0, 1e-9, "远端 x = 800")
		assert_almost_eq(float(vf["t_m"]), 800.0, 1e-9, "远端 t = 800")

func test_b2_az_dist_tangent_and_reverse() -> void:
	# 相切：D_B=400（B 到射线垂距 400）→ t=500 唯一解 (500,0)
	var rt := I.b2_az_dist({
		"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 90.0,
		"x_b_m": 500.0, "y_b_m": 400.0, "d_b_m": 400.0, "branch": "near",
	})
	assert_true(bool(rt.get("ok", false)), "相切成功")
	if bool(rt.get("ok", false)):
		var vt: Dictionary = rt["value"]
		assert_true(bool(vt["tangent"]), "相切标记")
		assert_almost_eq(float(vt["x_m"]), 500.0, 1e-9, "切点 x = 500")
	# 反方向：az=270°（向西）时两解 t<0 → 无解
	var rb := I.b2_az_dist({
		"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 270.0,
		"x_b_m": 500.0, "y_b_m": 400.0, "d_b_m": 500.0, "branch": "near",
	})
	assert_false(bool(rb.get("ok", true)), "交点在射线反方向应失败")
	assert_true(String(rb.get("error", "")).length() > 0, "反方向中文错误")

func test_protocol_contract_all_envelopes() -> void:
	var py := 1000.0 + 400.0 * sqrt(3.0)
	var cases := [
		I.b1_azimuth({"x_a_m": 1000.0, "y_a_m": 1000.0, "az1_deg": 30.0, "x_b_m": 2000.0, "y_b_m": 1200.0, "az2_deg": 309.3986}),
		I.b1_angles({"x_a_m": 1000.0, "y_a_m": 1000.0, "x_b_m": 2000.0, "y_b_m": 1200.0, "beta1_deg": 48.690068, "beta2_deg": 50.708494, "side": "左"}),
		I.b1_side({"x_a_m": 1000.0, "y_a_m": 1000.0, "x_b_m": 2000.0, "y_b_m": 1200.0, "beta_a_deg": 48.690068, "gamma_deg": 80.601439, "side": "左"}),
		I.b1_resection({"x_a_m": 2000.0, "y_a_m": 1200.0, "x_b_m": 1000.0, "y_b_m": 1000.0, "x_c_m": 1500.0, "y_c_m": 2000.0, "alpha_deg": 103.324531, "beta_deg": 118.495639}),
		I.b2_dist_dist({"x_a_m": 1000.0, "y_a_m": 1000.0, "d_a_m": 700.0, "x_b_m": 1800.0, "y_b_m": 1050.0, "d_b_m": 600.0, "side": 1}),
		I.b2_az_dist({"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 90.0, "x_b_m": 500.0, "y_b_m": 400.0, "d_b_m": 500.0, "branch": "near"}),
	]
	for idx in cases.size():
		var r: Dictionary = cases[idx]
		assert_true(bool(r.get("ok", false)), "协议样例 %d 成功" % idx)
		assert_true(r.has("value") and r.has("steps") and r.has("formula") and r.has("error"), "协议样例 %d 字段齐备" % idx)
		var steps: Array = r.get("steps", [])
		for st: Dictionary in steps:
			assert_true(st.has("title") and st.has("formula") and st.has("substitution") and st.has("result"), "协议样例 %d 步骤四字段" % idx)
	# b2_az_az 与 b1_azimuth 同源
	var a := I.b1_azimuth({"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 0.0, "x_b_m": 100.0, "y_b_m": 100.0, "az2_deg": 315.0})
	var b := I.b2_az_az({"x_a_m": 0.0, "y_a_m": 0.0, "az1_deg": 0.0, "x_b_m": 100.0, "y_b_m": 100.0, "az2_deg": 315.0})
	assert_almost_eq(float(a["value"]["x_m"]), float(b["value"]["x_m"]), 1e-12, "b2_az_az 与 b1_azimuth 同解")
