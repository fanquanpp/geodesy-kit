# tests/adjustment/test_accuracy.gd —— GK-M6-5 点位精度与误差椭圆回归（C9）
#
# 向量来源（【构造·判据明确】+ 本会话 numpy 独立复核）：
#   - 往返构造：已知 A=0.030、B=0.012、φE=37.5°（从北顺时针）→ 由测试侧用
#     Q = A²·uuᵀ + B²·vvᵀ 构造协因数阵 → 模块应精确恢复 A/B/φE 与 Mp=√(A²+B²)=0.0323109888431；
#     判据：椭圆半轴非负、往返闭合。
#   - 轴对齐/圆退化/非正定等边界：numpy 复核口径（qxy≈0 → φE=90° 或 0°；A=B 圆退化）。
extends "res://tests/test_case_base.gd"

const AC := preload("res://core/adjustment/accuracy.gd")

## 测试侧构造：由半轴与主轴方位（从北顺时针）生成 2×2 协因数阵 {qxx, qyy, qxy}
## u = (sinφ, cosφ)（方位 φ 方向），v = (cosφ, −sinφ)（方位 φ+90，与 u 正交）
func _make_q(a: float, b: float, phi_e_deg: float) -> Dictionary:
	var pr := deg_to_rad(phi_e_deg)
	var ux := sin(pr)   # 方位角方向单位向量（x=东）
	var uy := cos(pr)   # （y=北）
	var vx := cos(pr)
	var vy := -sin(pr)
	var qxx := a * a * ux * ux + b * b * vx * vx
	var qyy := a * a * uy * uy + b * b * vy * vy
	var qxy := a * a * ux * uy + b * b * vx * vy
	return {"qxx": qxx, "qyy": qyy, "qxy": qxy}

func test_c9_ellipse_roundtrip() -> void:
	var q := _make_q(0.030, 0.012, 37.5)
	var res := AC.ellipse_from_q(q)
	assert_true(bool(res.get("ok", false)), "椭圆计算应成功")
	if not bool(res.get("ok", false)):
		print("       C9 error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["A_m"]), 0.030, 1e-12, "长半轴 A 往返恢复")
	assert_almost_eq(float(v["B_m"]), 0.012, 1e-12, "短半轴 B 往返恢复")
	assert_almost_eq(float(v["phi_E_deg"]), 37.5, 1e-9, "主轴方位 φE 往返恢复（从北顺时针）")
	assert_almost_eq(float(v["Mp_m"]), 0.0323109888431, 1e-12, "Mp=√(A²+B²)=0.0323109888431")
	assert_false(bool(v["is_circle"]), "非圆")
	# 半轴非负判据
	assert_true(float(v["A_m"]) >= 0.0 and float(v["B_m"]) >= 0.0, "椭圆半轴非负")

func test_c9_sigma0_scaling() -> void:
	var q := _make_q(0.030, 0.012, 37.5)
	q["sigma0"] = 2.0
	var res := AC.ellipse_from_q(q)
	assert_true(bool(res.get("ok", false)), "σ0=2 应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["A_m"]), 0.060, 1e-12, "A 随 σ0 线性放大")
	assert_almost_eq(float(v["Mp_m"]), 0.0646219776862, 1e-12, "Mp 同步放大")

func test_c9_axis_aligned() -> void:
	# qxy=0、qxx>qyy → 主轴沿 x(东) → φE=90°
	var res := AC.ellipse_from_q({"qxx": 8.2e-05, "qyy": 5.61643835616e-05, "qxy": 0.0})
	assert_true(bool(res.get("ok", false)), "轴对齐应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["phi_E_deg"]), 90.0, 1e-12, "主轴沿东方向 φE=90°")
	assert_almost_eq(float(v["A_m"]), sqrt(8.2e-05), 1e-15, "A=σ0·√qxx（σ0=1）")
	# qxy=0、qyy>qxx → 主轴沿 y(北) → φE=0°
	var res2 := AC.ellipse_from_q({"qxx": 4.0e-05, "qyy": 9.0e-05, "qxy": 0.0})
	assert_true(bool(res2.get("ok", false)), "轴对齐 2 应成功")
	assert_almost_eq(float(res2["value"]["phi_E_deg"]), 0.0, 1e-12, "主轴沿北方向 φE=0°")

func test_c9_circle_degenerate() -> void:
	var res := AC.ellipse_from_q({"qxx": 4.0e-05, "qyy": 4.0e-05, "qxy": 0.0})
	assert_true(bool(res.get("ok", false)), "圆退化应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_true(bool(v["is_circle"]), "A=B 应判圆退化")
	assert_almost_eq(float(v["A_m"]), 0.00632455532034, 1e-12, "圆半径 A")
	assert_almost_eq(float(v["B_m"]), 0.00632455532034, 1e-12, "圆半径 B")

func test_c9_invalid_inputs() -> void:
	# 非半正定：|qxy| > √(qxx·qyy)
	var bad := AC.ellipse_from_q({"qxx": 1e-4, "qyy": 1e-4, "qxy": 2e-4})
	assert_false(bool(bad.get("ok", true)), "非半正定应失败")
	assert_true(String(bad.get("error", "")).length() > 0, "失败须中文 error")
	var neg := AC.ellipse_from_q({"qxx": -1e-4, "qyy": 1e-4, "qxy": 0.0})
	assert_false(bool(neg.get("ok", true)), "负方差应失败")
	var missing := AC.ellipse_from_q({"qxx": 1e-4})
	assert_false(bool(missing.get("ok", true)), "缺 qyy/qxy 应失败")

# ---------- P2 补充：φE 步骤并列 tan2φ_E 口径（与既有特征向量断言共存，不改期望值）----------

## P2：步骤 3 公式文本应并列 tan2φ_E = 2q_xy/(q_xx−q_yy) 教材口径
func test_c9_steps_show_tan2phi_formula() -> void:
	var q := _make_q(0.030, 0.012, 37.5)
	var res := AC.ellipse_from_q(q)
	assert_true(bool(res.get("ok", false)), "椭圆计算应成功")
	if not bool(res.get("ok", false)):
		return
	var all_text := ""
	for st: Dictionary in res["steps"]:
		all_text += String(st["formula"])
	assert_true("tan2φ_E = 2q_xy/(q_xx−q_yy)" in all_text, "φE 步骤应含 tan2φ_E 教材公式")
	assert_true("特征向量" in all_text, "φE 步骤应保留特征向量法口径（并列展示）")
	# tan2φ_E 数值应出现在 substitution（0.030/0.012/37.5° 构造的 q 阵）
	var qxx := float(q["qxx"])
	var qyy := float(q["qyy"])
	var qxy := float(q["qxy"])
	var expected_ratio := 2.0 * qxy / (qxx - qyy)
	var found_num := false
	for st2: Dictionary in res["steps"]:
		if "2q_xy" in String(st2["formula"]) and String(st2["substitution"]).contains("%.6f" % expected_ratio):
			found_num = true
	assert_true(found_num, "substitution 应含 tan2φ_E 的数值代入")
