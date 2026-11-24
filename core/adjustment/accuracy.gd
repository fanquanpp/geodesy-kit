# core/adjustment/accuracy.gd —— GK-M6-5 点位精度与误差椭圆（C9：Qxx → φE / A² / B²）
#
# x=东、y=北；qxx/qyy 为对应方向协因数。W=√((qxx−qyy)²+4qxy²)；A²=σ0²(qxx+qyy+W)/2、
# B²=σ0²(qxx+qyy−W)/2；主轴方向取最大特征值对应特征向量；φE 自北起顺时针 [0°,180°)；
# 圆退化（A=B）时方向不定，phi_E_deg=0 并给 is_circle 标记；Mp=σ0√(qxx+qyy)=√(A²+B²)。
# 输入可为纯协因数（σ0=1）或方差阵；全部静态、零引擎依赖；非半正定输入 {ok:false, error:中文}。
class_name GKAdjustAccuracy
extends RefCounted

## C9 点位误差椭圆
## p = {qxx, qyy, qxy, sigma0?（默认 1.0）}
## value: {A_m, B_m, phi_E_deg, Mp_m, sigma_x_m, sigma_y_m, is_circle}
static func ellipse_from_q(p: Dictionary) -> Dictionary:
	for k in ["qxx", "qyy", "qxy"]:
		if not p.has(k) or not _finite_num(p.get(k)):
			return _fail("缺少 %s（协因数/方差分量，须为数值）" % k)
	var qxx := float(p["qxx"])
	var qyy := float(p["qyy"])
	var qxy := float(p["qxy"])
	var sigma0 := 1.0
	if p.has("sigma0") and _finite_num(p.get("sigma0")) and float(p["sigma0"]) > 0.0:
		sigma0 = float(p["sigma0"])
	if qxx < 0.0 or qyy < 0.0:
		return _fail("qxx/qyy（方差分量）不能为负")
	# 半正定检查：|qxy| ≤ √(qxx·qyy)（行列式非负）
	var det := qxx * qyy - qxy * qxy
	if det < -1e-12 * maxf(1.0, qxx * qyy):
		return _fail("协因数阵非半正定（|qxy| > √(qxx·qyy)），请检查输入")
	var w := sqrt((qxx - qyy) * (qxx - qyy) + 4.0 * qxy * qxy)
	var a2 := sigma0 * sigma0 * (qxx + qyy + w) / 2.0
	var b2 := sigma0 * sigma0 * (qxx + qyy - w) / 2.0
	var is_circle := w <= 1e-12 * maxf(1.0, qxx + qyy)
	var phi_e := 0.0
	if not is_circle:
		# 最大特征值对应特征向量：λmax 对应 (qxy, λmax−qxx)（qxy≠0 时）；
		# qxy≈0 时轴对齐：qxx≥qyy 主轴沿 x(东)，否则沿 y(北)。
		if absf(qxy) > 1e-15:
			var ux := qxy
			var uy := a2 / (sigma0 * sigma0) - qxx
			phi_e = GKAngles.normalize_deg(rad_to_deg(atan2(ux, uy)))
			if phi_e >= 180.0:
				phi_e -= 180.0
		else:
			phi_e = 90.0 if qxx >= qyy else 0.0
	var a_m := sqrt(a2)
	var b_m := sqrt(maxf(b2, 0.0))
	var mp := sigma0 * sqrt(qxx + qyy)
	var value := {
		"A_m": a_m,
		"B_m": b_m,
		"phi_E_deg": phi_e,
		"Mp_m": mp,
		"sigma_x_m": sigma0 * sqrt(qxx),
		"sigma_y_m": sigma0 * sqrt(qyy),
		"is_circle": is_circle,
		"sigma0": sigma0,
	}
	var steps := [
		{
			"title": "1. 协因数阵特征根",
			"formula": "W = √((qxx−qyy)² + 4qxy²)",
			"substitution": "qxx = %s，qyy = %s，qxy = %s" % [_fmt(qxx), _fmt(qyy), _fmt(qxy)],
			"result": "W = %s" % _fmt(w),
		},
		{
			"title": "2. 误差椭圆半轴",
			"formula": "A² = σ0²(qxx+qyy+W)/2，B² = σ0²(qxx+qyy−W)/2",
			"substitution": "σ0 = %s" % _fmt(sigma0),
			"result": "A = %s m，B = %s m" % [_fmt(a_m), _fmt(b_m)],
		},
		{
			"title": "3. 主轴方位角 φE",
			"formula": "tan2φ_E = 2q_xy/(q_xx−q_yy)（φE 从北起顺时针，象限判别同 q_xy 符号）；等价特征向量法：u = (qxy, λmax−qxx)",
			"substitution": "2q_xy/(q_xx−q_yy) = %s（特征向量方向按解析式计算）" % _fmt(0.0 if absf(qxx - qyy) < 1e-15 else 2.0 * qxy / (qxx - qyy)),
			"result": "φE = %s°%s" % [_fmt(phi_e), "（圆退化，方向不定取 0）" if is_circle else ""],
		},
		{
			"title": "4. 点位中误差",
			"formula": "Mp = σ0·√(qxx+qyy) = √(A²+B²)",
			"substitution": "√(qxx+qyy) = %s" % _fmt(sqrt(qxx + qyy)),
			"result": "Mp = %s m" % _fmt(mp),
		},
	]
	return _ok(value, steps, "点位误差椭圆（φE 从北顺时针；x=东、y=北）")

## C9 快捷：点位中误差（无方向信息）
## p = {qxx, qyy, sigma0?}
static func point_sigma(p: Dictionary) -> Dictionary:
	var e := ellipse_from_q(p)
	if not bool(e.get("ok", false)):
		return e
	var v: Dictionary = e["value"]
	return _ok({
		"Mp_m": v["Mp_m"],
		"sigma_x_m": v["sigma_x_m"],
		"sigma_y_m": v["sigma_y_m"],
	}, e["steps"], "点位中误差 Mp = σ0·√(qxx+qyy)")

# ---------- 内部 ----------

static func _finite_num(v) -> bool:
	if not (v is float or v is int):
		return false
	return is_finite(float(v))

static func _fmt(v: float) -> String:
	if not is_finite(v):
		if v > 0.0:
			return "+∞"
		elif v < 0.0:
			return "−∞"
		return "NaN"
	return "%.6f" % v

static func _ok(value: Dictionary, steps: Array, formula: String) -> Dictionary:
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}
