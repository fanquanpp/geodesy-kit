# core/topics/gnss.gd —— GK-M8-6（I-GNSS）广播星历开普勒→ECEF、时间、DOP
#
# 星历算法：GPS IS-GPS-200 广播星历 16 参数开普勒算法（教科书/RINEX 标准流程），
# 角度参数一律弧度（与 RINEX 广播星历一致）。常数：
#   μ  = 3.9860050e14 m³/s²（IS-GPS-200 表载值）
#   Ω̇e = 7.2921151467e-5 rad/s（WGS84 地球自转角速率）
# 半周滚转：tk = t − toe，|tk|>302400 s 时按 ±604800 s 归算。
# 构造自洽验收口径（ARCHITECTURE.md §0 落地补 #5）：无实测 RINEX 向量前，用
# 开普勒方程迭代收敛性 + 退化圆轨道解析解对照；DOP 用权威构造向量
# （4 星对称单位视线 (±0.5,±0.3,0.8124)→PDOP=2.0388，3×3 位置口径）。
#
# DOP 口径说明：PDOP = √trace((GᵀG)⁻¹)，G 行为视线单位向量（3×3，不含钟差列），
# 与分派向量一致；另提供 with_clock=true 的 4×4（含接收机钟差列 [1…1]），
# 输出 GDOP/TDOP——注意全等高度角对称星座会使 4×4 奇异（钟差不可估），此时报中文错误。
#
# 设计约定同 core/astro/solar.gd 头注。
class_name GKGnss
extends RefCounted

const MU := 3.9860050e14          # WGS84 引力常数（IS-GPS-200）
const OMEGA_E_DOT := 7.2921151467e-5  # 地球自转角速率 rad/s
const WEEK_S := 604800.0
const HALF_WEEK_S := 302400.0

## 开普勒方程求解 E − e·sinE = M（牛顿迭代，弧度）。发散返回 NAN。
static func kepler_solve(m: float, e: float, tol := 1e-14, max_iter := 30) -> float:
	if not is_finite(m) or not is_finite(e) or e < 0.0 or e >= 1.0:
		return NAN
	var ec := m
	for i in max_iter:
		var delta := (ec - e * sin(ec) - m) / (1.0 - e * cos(ec))
		ec -= delta
		if absf(delta) < tol:
			return ec
	return NAN

## 半周滚转归算：tk = t − toe（|tk| ≤ 302400）
static func tk_adjust(t: float, toe: float) -> float:
	var tk := t - toe
	if tk > HALF_WEEK_S:
		tk -= WEEK_S
	elif tk < -HALF_WEEK_S:
		tk += WEEK_S
	return tk

## 广播星历 → 卫星 ECEF（§5 协议）
## p: {sqrt_a, e, i0, omega(近地点角距), omega0(升交点赤经), omega_dot, m0, delta_n,
##     cuc, cus, crc, crs, cic, cis, idot(可默认0), toe, t_gps}
## 角度一律弧度；toe/t_gps 为 GPS 周内秒
static func ephemeris_to_ecef(p: Dictionary) -> Dictionary:
	for key in ["sqrt_a", "e", "i0", "omega", "omega0", "omega_dot", "m0",
			"delta_n", "cuc", "cus", "crc", "crs", "cic", "cis", "toe", "t_gps"]:
		var v: Variant = p.get(key, NAN)
		if not is_finite(float(v)):
			return _err("星历参数缺失或非法：%s" % key)
	var sqrt_a := float(p["sqrt_a"])
	var e := float(p["e"])
	var idot := float(p.get("idot", 0.0))
	if sqrt_a <= 0.0:
		return _err("半长轴平方根 √a 非法：应为正（GPS 约 5153.79 m^0.5）")
	if e < 0.0 or e >= 1.0:
		return _err("偏心率 e 非法：应在 [0, 1)（广播星历典型 <0.02）")
	var a := sqrt_a * sqrt_a
	var n0 := sqrt(MU / (a * a * a))
	var n := n0 + float(p["delta_n"])
	var tk := tk_adjust(float(p["t_gps"]), float(p["toe"]))
	var m := float(p["m0"]) + n * tk
	var ecc := kepler_solve(m, e)
	if is_nan(ecc):
		return _err("开普勒方程迭代不收敛（检查 m0/delta_n/e 参数）")
	var nu := atan2(sqrt(1.0 - e * e) * sin(ecc), cos(ecc) - e)
	var phi_u := nu + float(p["omega"])
	var sin2u := sin(2.0 * phi_u)
	var cos2u := cos(2.0 * phi_u)
	var du := float(p["cus"]) * sin2u + float(p["cuc"]) * cos2u
	var dr := float(p["crs"]) * sin2u + float(p["crc"]) * cos2u
	var di := float(p["cis"]) * sin2u + float(p["cic"]) * cos2u
	var u := phi_u + du
	var r_orb := a * (1.0 - e * cos(ecc)) + dr
	var inc := float(p["i0"]) + di + idot * tk
	var om := float(p["omega0"]) + float(p["omega_dot"]) * tk - OMEGA_E_DOT * float(p["t_gps"])
	var xo := r_orb * cos(u)
	var yo := r_orb * sin(u)
	var x := xo * cos(om) - yo * sin(om) * cos(inc)
	var y := xo * sin(om) + yo * cos(om) * cos(inc)
	var z := yo * sin(inc)
	var value := {
		"x_m": x, "y_m": y, "z_m": z,
		"r_orb_m": r_orb,
		"tk_s": tk,
		"ecc_anom": ecc,
		"true_anom": nu,
		"incl_rad": inc,
		"omega_rad": om,
		"n_rad_s": n,
	}
	var steps := [
		{"title": "1. 平均角速度与时间归算",
			"formula": "n = √(μ/a³) + Δn；tk = t − toe（半周滚转 ±302400 s）",
			"substitution": "a = (√a)² = %.3f m，n₀ = %.9f rad/s，tk = %.3f s" % [a, n0, tk],
			"result": "n = %.9f rad/s，tk = %.3f s" % [n, tk]},
		{"title": "2. 开普勒方程迭代解偏近点角",
			"formula": "E − e·sinE = M = M₀ + n·tk（牛顿迭代）",
			"substitution": "M = %.9f rad，e = %.9f" % [m, e],
			"result": "E = %.9f rad（残差 <1e-14）" % ecc},
		{"title": "3. 真近点角与摄动改正",
			"formula": "ν = atan2(√(1−e²)·sinE, cosE−e)；u = ν+ω+δu，r = a(1−e·cosE)+δr，i = i₀+δi+İ·tk",
			"substitution": "Φ = ν+ω = %.9f rad" % phi_u,
			"result": "u = %.9f rad，r = %.3f m，i = %.9f rad" % [u, r_orb, inc]},
		{"title": "4. 轨道面 → ECEF（含地球自转修正 Ω̇e·t）",
			"formula": "Ω = Ω₀+Ω̇·tk−Ωₑ·t；x = x'cosΩ − y'sinΩ·cos i；y = x'sinΩ + y'cosΩ·cos i；z = y'·sin i",
			"substitution": "Ω = %.9f rad，i = %.9f rad" % [om, inc],
			"result": "ECEF = (%.4f, %.4f, %.4f) m" % [x, y, z]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "IS-GPS-200 广播星历开普勒算法（μ=3.9860050e14，Ω̇e=7.2921151467e-5），角度参数为弧度",
			"error": ""}

## DOP 计算（§5 协议）
## p: {los: Array[Array[ex,ey,ez]] 视线单位向量（内部归一化，≥4 星）,
##     with_clock: bool 可选（true → 4×4 含钟差列，输出 GDOP/TDOP）}
static func dop(p: Dictionary) -> Dictionary:
	var los: Variant = p.get("los", [])
	var with_clock := bool(p.get("with_clock", false))
	if not (los is Array) or (los as Array).size() < 4:
		return _err("视线向量不足：DOP 计算至少需要 4 颗卫星的视线单位向量")
	var rows: Array = los
	var n := (rows as Array).size()
	var g := []
	for row: Variant in rows:
		var arr: Array = row
		if not (arr is Array) or (arr as Array).size() < 3:
			return _err("视线向量格式非法：每行应为 [ex, ey, ez]")
		var ex := float(arr[0])
		var ey := float(arr[1])
		var ez := float(arr[2])
		if not (is_finite(ex) and is_finite(ey) and is_finite(ez)):
			return _err("视线向量含非数值")
		var norm := sqrt(ex * ex + ey * ey + ez * ez)
		if norm < 1e-12:
			return _err("视线向量为零向量，无法归一化")
		if with_clock:
			g.append(PackedFloat64Array([-ex / norm, -ey / norm, -ez / norm, 1.0]))
		else:
			g.append(PackedFloat64Array([ex / norm, ey / norm, ez / norm]))
	var gt := GKMatrix.transpose(g)
	var gtg := GKMatrix.multiply(gt, g)
	if gtg.is_empty():
		return _err("GᵀG 维度不符（内部错误）")
	var q := GKMatrix.inverse(gtg)
	if q.is_empty():
		var msg := "卫星几何退化（GᵀG 奇异）"
		if with_clock:
			msg = "卫星几何退化：全部视线近于同一锥面（如等高度角对称星座），钟差列不可估，4×4 DOP 无解"
		else:
			msg = "卫星几何退化：视线近于共面/共线，位置 DOP 无解"
		return _err(msg)
	var q11: float = (q[0] as PackedFloat64Array)[0]
	var q22: float = (q[1] as PackedFloat64Array)[1]
	var q33: float = (q[2] as PackedFloat64Array)[2]
	# 近奇异防线：浮点上"恰好奇异"的几何（行列式≈1e-15）会让逆矩阵出现天文数字，须判退化
	var q_diag_max := maxf(q11, maxf(q22, q33))
	if not is_finite(q_diag_max) or q_diag_max > 1e6:
		var msg2 := "卫星几何退化（GᵀG 近奇异）"
		if with_clock:
			msg2 = "卫星几何退化：全部视线近于同一锥面（如等高度角对称星座），钟差列不可估，4×4 DOP 无解"
		else:
			msg2 = "卫星几何退化：视线近于共面/共线，位置 DOP 无解"
		return _err(msg2)
	var value := {
		"pdop": sqrt(q11 + q22 + q33),
		"hdop": sqrt(q11 + q22),
		"vdop": sqrt(q33),
		"n_sats": n,
		"with_clock": with_clock,
	}
	var steps := [
		{"title": "1. 构建设计矩阵 G（行 = 视线单位向量%s）" % ("（含钟差列 1）" if with_clock else ""),
			"formula": "GᵀG 与其逆 Q = (GᵀG)⁻¹（部分主元高斯消元，GKMatrix）",
			"substitution": "%d 颗卫星，视线向量已归一化" % n,
			"result": "Q 为 %d×%d" % [g[0].size(), g[0].size()]},
		{"title": "2. DOP 要素",
			"formula": "PDOP=√(q₁₁+q₂₂+q₃₃)；HDOP=√(q₁₁+q₂₂)；VDOP=√(q₃₃)%s" % ("；GDOP=√trace(Q)；TDOP=√q₄₄" if with_clock else ""),
			"substitution": "q₁₁=%.9f，q₂₂=%.9f，q₃₃=%.9f" % [q11, q22, q33],
			"result": "PDOP=%.6f，HDOP=%.6f，VDOP=%.6f" % [float(value["pdop"]), float(value["hdop"]), float(value["vdop"])]},
	]
	if with_clock:
		var q44: float = (q[3] as PackedFloat64Array)[3]
		value["gdop"] = sqrt(q11 + q22 + q33 + q44)
		value["tdop"] = sqrt(q44)
	var formula := "DOP = √trace((GᵀG)⁻¹)%s；PDOP 为位置精度衰减因子（越小越好，<3 优）" % ("（4×4 含钟差）" if with_clock else "（3×3 位置口径）")
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
