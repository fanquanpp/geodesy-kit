# core/transform/bursa.gd —— GK-M4-1（A9）：布尔莎七参数转换（PV/CF 双约定）+ 三参数 + 公共点求参
#
# PV（EPSG:1033）：X2=T+(1+dS)·Rz·Ry·Rx·X1；CF（EPSG:1032）与 PV 同式但旋转角反号
# （实现为输入角取负走同一 PV 路径，双约定互检逐位一致）。权威向量：EPSG GN7-2 §4.2.3 WGS72→WGS84。
# 求参为线性化误差方程最小二乘（小角近似 O(ε²)·X，1″ 级角 1000km 时 <0.01mm）；
# 粗差用标准化残差 w=v/(σ0√q_v)，|w|>3 判定并自动「剔除→重求参→再检核」（入 value.refit，保留提示）。
# 纯 GDScript、零引擎依赖；矩阵走 GKMatrix（Wave 0 冻结 API）；失败 {ok:false,value:{},error:中文}。
class_name GKBursa
extends RefCounted

const AS_TO_RAD: float = PI / (180.0 * 3600.0)        # 1″ = 4.848136811095360e-6 rad
const RAD_TO_AS: float = 180.0 * 3600.0 / PI         # 1 rad = 206264.80624709636″

## 参数 → 坐标（§5 协议入口）。
## p：{src_xyz: [[x,y,z],...], tx_m, ty_m, tz_m, rx_as, ry_as, rz_as, scale_ppm, convention: "PV"|"CF"}
## 返回 value：{points_m: [[x2,y2,z2],...], n, x_m/y_m/z_m（单点时附），convention}
static func transform(p: Dictionary) -> Dictionary:
	var formula := "X2 = T + (1+dS)·R·X1（布尔莎七参数；PV=位置向量 EPSG:1033，CF=坐标框架 EPSG:1032 旋转角反号）"
	var pts := _parse_points(p.get("src_xyz", []), 3)
	if not pts.ok:
		return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": pts.error}
	var pa := _read_params(p)
	if not pa.ok:
		return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": pa.error}
	var ang: Array = pa.angles_rad           # PV 角（CF 已反号）
	var ds: float = pa.ds                    # 尺度因子 dS（无量纲）
	var conv: String = pa.convention
	# 精确旋转矩阵 R = Rz·Ry·Rx（右手正旋转）
	var R := _rot_matrix(ang[0], ang[1], ang[2])
	var out := []
	for q: PackedFloat64Array in pts.points:
		var x2: float = pa.tx + (1.0 + ds) * (R[0][0] * q[0] + R[0][1] * q[1] + R[0][2] * q[2])
		var y2: float = pa.ty + (1.0 + ds) * (R[1][0] * q[0] + R[1][1] * q[1] + R[1][2] * q[2])
		var z2: float = pa.tz + (1.0 + ds) * (R[2][0] * q[0] + R[2][1] * q[1] + R[2][2] * q[2])
		out.append([x2, y2, z2])
	var zero_note := ""
	if pa.has("zero_filled") and not (pa["zero_filled"] as PackedStringArray).is_empty():
		zero_note = "；以下参数输入留空，已按 0 代入：%s" % "、".join(pa["zero_filled"])
	var steps := [
		{
			"title": "1. 参数与旋转约定",
			"formula": "X2 = T + (1+dS)·R·X1；%s" % ("位置向量约定 PV（EPSG:1033）" if conv == "PV" else "坐标框架约定 CF（EPSG:1032，旋转角反号）"),
			"substitution": "T=(%.4f, %.4f, %.4f) m，r=(%.6f, %.6f, %.6f)″，dS=%.6f ppm，共 %d 点%s" % [pa.tx, pa.ty, pa.tz, pa.rx_as, pa.ry_as, pa.rz_as, pa.scale_ppm, out.size(), zero_note],
			"result": "参与旋转的角（弧度）=(%.13f, %.13f, %.13f)" % [ang[0], ang[1], ang[2]],
		},
		{
			"title": "2. 旋转矩阵（精确三角函数，右手正旋转）",
			"formula": "R = Rz(rz)·Ry(ry)·Rx(rx)",
			"substitution": "",
			"result": "R=[[%.12f, %.12f, %.12f],[%.12f, %.12f, %.12f],[%.12f, %.12f, %.12f]]" % [R[0][0], R[0][1], R[0][2], R[1][0], R[1][1], R[1][2], R[2][0], R[2][1], R[2][2]],
		},
	]
	var first: Array = out[0]
	var q0: PackedFloat64Array = pts.points[0]
	steps.append({
		"title": "3. 单点代入",
		"formula": "x2 = tx + (1+dS)·(R11·x + R12·y + R13·z)（y2/z2 类推）",
		"substitution": "x2 = %.4f + (1+%.9f)·(%.10f·%.6f + %.10f·%.6f + %.10f·%.6f)" % [pa.tx, ds, R[0][0], q0[0], R[0][1], q0[1], R[0][2], q0[2]],
		"result": "首点输出 (%.4f, %.4f, %.4f) m" % [first[0], first[1], first[2]],
	})
	if out.size() > 1:
		steps.append({"title": "4. 其余各点同式计算", "formula": "", "substitution": "", "result": "共 %d 点，见结果表" % out.size()})
	var value := {"points_m": out, "n": out.size(), "convention": conv}
	if out.size() == 1:
		value["x_m"] = first[0]
		value["y_m"] = first[1]
		value["z_m"] = first[2]
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 公共点求参（§5 协议入口）。p：{src_xyz, dst_xyz, convention: "PV"|"CF", three_param: bool, k_gross? = 3.0}
## 返回 value：七参数（或三参数）+ 公共点残差表 + 单位权中误差 + 标准化残差粗差中文提示 + refit 剔除迭代。
static func solve(p: Dictionary) -> Dictionary:
	var three: bool = bool(p.get("three_param", false))
	var n_unknown := 3 if three else 7
	var formula := "布尔莎%s求参：线性化误差方程 B·x̂ = l 的最小二乘解（N=BᵀB，Cholesky）" % ("三参数（仅平移）" if three else "七参数")
	var src := _parse_points(p.get("src_xyz", []), 3)
	if not src.ok:
		return _err(formula, src.error)
	var dst := _parse_points(p.get("dst_xyz", []), 3)
	if not dst.ok:
		return _err(formula, dst.error)
	if src.points.size() != dst.points.size():
		return _err(formula, "源系与目标系公共点数量不一致：%d 与 %d" % [src.points.size(), dst.points.size()])
	var n: int = src.points.size()
	var min_n := 1 if three else 3
	if n < min_n:
		return _err(formula, "%s求参至少需要 %d 个公共点（当前 %d 个）" % ["三参数" if three else "七参数", min_n, n])
	var k_gross := 3.0
	if p.has("k_gross") and is_finite(float(p["k_gross"])) and float(p["k_gross"]) > 0.0:
		k_gross = float(p["k_gross"])
	var pa := _read_params_for_solve(p)
	if not pa.ok:
		return _err(formula, pa.error)
	var neg := -1.0 if pa.convention == "CF" else 1.0
	# 组成误差方程 B·x = l：未知量顺序 [tx, ty, tz, rx, ry, rz, dS]（三参数仅前 3 个）
	var B := []
	var l := PackedFloat64Array()
	for i in n:
		var q: PackedFloat64Array = src.points[i]
		var d: PackedFloat64Array = dst.points[i]
		if three:
			B.append(PackedFloat64Array([1.0, 0.0, 0.0]))
			l.append(d[0] - q[0])
			B.append(PackedFloat64Array([0.0, 1.0, 0.0]))
			l.append(d[1] - q[1])
			B.append(PackedFloat64Array([0.0, 0.0, 1.0]))
			l.append(d[2] - q[2])
		else:
			B.append(PackedFloat64Array([1.0, 0.0, 0.0, 0.0, neg * q[2], -neg * q[1], q[0]]))
			l.append(d[0] - q[0])
			B.append(PackedFloat64Array([0.0, 1.0, 0.0, -neg * q[2], 0.0, neg * q[0], q[1]]))
			l.append(d[1] - q[1])
			B.append(PackedFloat64Array([0.0, 0.0, 1.0, neg * q[1], -neg * q[0], 0.0, q[2]]))
			l.append(d[2] - q[2])
	var n_obs := l.size()
	var At := GKMatrix.transpose(B)
	if At.is_empty():
		return _err(formula, "误差方程组成异常（B 矩阵为空）")
	var N := GKMatrix.multiply(At, B)
	var rhs := GKMatrix.mat_vec(At, l)
	if N.is_empty() or rhs.is_empty():
		return _err(formula, "法方程组成异常（维度不匹配）")
	var xhat := GKMatrix.cholesky_solve(N, rhs)
	var xg := GKMatrix.solve(N, rhs)  # 独立路径互检（高斯消元含相对容差零行/奇异检测）
	if xhat.is_empty() or xg.is_empty():
		return _err(formula, "法方程奇异，无法求参——公共点分布退化（如共线/共面、过于集中），请检查点位配置")
	# 双路径一致性：严重病态时两路径解显著分叉（Cholesky 对近奇异 N 因 sqrt 取整可能漏检）
	var max_x := 1.0
	for val in xhat:
		max_x = maxf(max_x, absf(val))
	for k in xhat.size():
		if absf(xhat[k] - xg[k]) > 1e-4 * max_x:
			return _err(formula, "法方程严重病态（双解路径不一致），请检查公共点几何配置")
	# 残差 V = B·x̂ − l（逐观测）
	var v := PackedFloat64Array()
	v.resize(n_obs)
	for i in n_obs:
		var s := 0.0
		var row: PackedFloat64Array = B[i]
		for k in n_unknown:
			s += row[k] * xhat[k]
		v[i] = s - l[i]
	var ss := 0.0
	for val in v:
		ss += val * val
	var redundancy := n_obs - n_unknown
	var sigma0 := sqrt(ss / redundancy) if redundancy > 0 else 0.0
	# 参数解包
	var tx := xhat[0]
	var ty := xhat[1]
	var tz := xhat[2]
	var rx_as := 0.0
	var ry_as := 0.0
	var rz_as := 0.0
	var scale_ppm := 0.0
	if not three:
		rx_as = xhat[3] * RAD_TO_AS
		ry_as = xhat[4] * RAD_TO_AS
		rz_as = xhat[5] * RAD_TO_AS
		scale_ppm = xhat[6] * 1e6
	# 参数中误差（σ0·√Qxx 对角，Qxx=N⁻¹）
	var sig_tx := NAN
	var sig_rx_as := NAN
	var sig_scale_ppm := NAN
	var Ninv := GKMatrix.inverse(N)
	if not Ninv.is_empty() and redundancy > 0 and sigma0 > 0.0:
		sig_tx = sigma0 * sqrt(absf((Ninv[0] as PackedFloat64Array)[0]))
		if not three:
			sig_rx_as = sigma0 * sqrt(absf((Ninv[3] as PackedFloat64Array)[3])) * RAD_TO_AS
			sig_scale_ppm = sigma0 * sqrt(absf((Ninv[6] as PackedFloat64Array)[6])) * 1e6
	# 逐点残差表 + 标准化残差粗差检核：w_i = v_i / (σ0·√q_vi)，q_vi = 1 − b_i·N⁻¹·b_iᵀ（等权）
	var residuals := []
	var warnings := PackedStringArray()
	var outliers := []
	var w := PackedFloat64Array()
	w.resize(n_obs)
	if redundancy > 0 and sigma0 > 0.0 and not Ninv.is_empty():
		for i in n_obs:
			var row: PackedFloat64Array = B[i]
			var bnbt := 0.0
			for j in n_unknown:
				var qrow: PackedFloat64Array = Ninv[j]
				var sj := 0.0
				for k in n_unknown:
					sj += qrow[k] * row[k]
				bnbt += row[j] * sj
			var q_vi := 1.0 - bnbt
			if q_vi <= 1e-12:
				q_vi = 1e-12  # 必要观测位置冗余度≈0：夹到微正防止除零
			w[i] = absf(v[i]) / (sigma0 * sqrt(q_vi))
		for i in n:
			var vx: float = v[i * 3]
			var vy: float = v[i * 3 + 1]
			var vz: float = v[i * 3 + 2]
			residuals.append([i + 1, vx, vy, vz])
			var comps := [[vx, "ΔX", w[i * 3]], [vy, "ΔY", w[i * 3 + 1]], [vz, "ΔZ", w[i * 3 + 2]]]
			for c in comps:
				if c[2] > k_gross:
					outliers.append(i + 1)
					warnings.append("第 %d 点 %s 分量残差 %.4f m，标准化残差 |w|=%.2f 超过限值 k=%.1f（σ0=%.4f m），疑似粗差，建议人工确认后剔除该点重新求参" % [i + 1, c[1], c[0], c[2], k_gross, sigma0])
	else:
		for i in n:
			residuals.append([i + 1, v[i * 3], v[i * 3 + 1], v[i * 3 + 2]])
	# 精度汇总
	var max_res := 0.0
	for i in n:
		var rn: float = sqrt(v[i * 3] * v[i * 3] + v[i * 3 + 1] * v[i * 3 + 1] + v[i * 3 + 2] * v[i * 3 + 2])
		if rn > max_res:
			max_res = rn
	var rms := sqrt(ss / n_obs)
	var value := {
		"convention": pa.convention,
		"n_points": n,
		"n_obs": n_obs,
		"n_unknown": n_unknown,
		"redundancy": redundancy,
		"tx_m": tx, "ty_m": ty, "tz_m": tz,
		"sigma0_m": sigma0, "rms_m": rms, "max_res_m": max_res,
		"residuals_m": residuals,
		"outliers": outliers,
	}
	if three:
		value["model"] = "三参数（仅平移）"
	else:
		value["rx_as"] = rx_as
		value["ry_as"] = ry_as
		value["rz_as"] = rz_as
		value["scale_ppm"] = scale_ppm
		value["basis"] = "线性化模型 LS（小角近似，模型误差 O(ε²)·X）；PV=EPSG:1033，CF=EPSG:1032"
	if not is_nan(sig_tx):
		value["sigma_tx_m"] = sig_tx
	if not is_nan(sig_rx_as):
		value["sigma_rx_as"] = sig_rx_as
		value["sigma_ry_as"] = sigma0 * sqrt(absf((Ninv[4] as PackedFloat64Array)[4])) * RAD_TO_AS
		value["sigma_rz_as"] = sigma0 * sqrt(absf((Ninv[5] as PackedFloat64Array)[5])) * RAD_TO_AS
		value["sigma_scale_ppm"] = sig_scale_ppm
	# —— 剔除 → 重新求参 → 再检核迭代（检出粗差且仍有多余观测时执行；保留人工确认） ——
	if not outliers.is_empty() and redundancy > 0 and sigma0 > 0.0:
		var refit_res := _refit_without_outliers(src.points, dst.points, outliers, three, pa.convention, k_gross)
		if not refit_res.is_empty():
			value["refit"] = refit_res
			warnings.append("已按剔除迭代求得一组不含粗差点的参数（见 refit），请人工确认比对后决定是否采纳；采纳前本页保留全点解")
	# warnings 在剔除迭代 append 之后回写，避免快照缺项
	value["warnings"] = Array(warnings)
	var steps := [
		{
			"title": "1. 线性化误差方程",
			"formula": "ΔX = tx − rz·y + ry·z + dS·x；ΔY = ty − rx·z + rz·x + dS·y；ΔZ = tz + rx·y − ry·x + dS·z" + ("（CF 约定旋转项反号）" if pa.convention == "CF" else "（PV 约定）"),
			"substitution": "公共点 %d 个 → %d 个观测方程，未知数 %d 个" % [n, n_obs, n_unknown],
			"result": "多余观测数（自由度）= %d" % redundancy,
		},
		{
			"title": "2. 法方程组成与求解",
			"formula": "N·x̂ = Bᵀl，N = BᵀB（对称正定，Cholesky 分解求解）",
			"substitution": "N 为 %d×%d 矩阵；l 由源/目标坐标差代入" % [n_unknown, n_unknown],
			"result": _param_text(three, tx, ty, tz, rx_as, ry_as, rz_as, scale_ppm),
		},
		{
			"title": "3. 精度评定",
			"formula": "σ0 = √(VᵀV / (3n − %d))" % n_unknown,
			"substitution": "VᵀV = %.9f m²，自由度 = %d" % [ss, redundancy],
			"result": "σ0 = %.6f m，观测 RMS = %.6f m，最大点残差 = %.6f m" % [sigma0, rms, max_res],
		},
	]
	var w_max := 0.0
	for val in w:
		w_max = maxf(w_max, val)
	if redundancy > 0 and sigma0 > 0.0 and not Ninv.is_empty():
		steps.append({
			"title": "4. 粗差检核（标准化残差准则）",
			"formula": "w = v / (σ0·√q_v)，q_v = 1 − b·N⁻¹·bᵀ（改正数协因数对角元）；|w| > k 判为疑似粗差",
			"substitution": "k = %.1f，σ0 = %.6f m" % [k_gross, sigma0],
			"result": ("无粗差（max|w|=%.2f ≤ k=%.1f）" % [w_max, k_gross]) if warnings.is_empty() else "\n".join(warnings),
		})
		if value.has("refit"):
			var rf: Dictionary = value["refit"]
			steps.append({
				"title": "5. 剔除迭代（剔除 → 重新求参 → 再检核）",
				"formula": "剔除 |w| > k 的公共点后重新组成法方程求解，再用剔除解参数回代全部点检核",
				"substitution": "剔除点号：%s；剔除解：%s" % [str(outliers), _param_text(three, float(rf["tx_m"]), float(rf["ty_m"]), float(rf["tz_m"]), float(rf.get("rx_as", 0.0)), float(rf.get("ry_as", 0.0)), float(rf.get("rz_as", 0.0)), float(rf.get("scale_ppm", 0.0)))],
				"result": "剔除解 σ0 = %.6f m；回代全部点最大残差 = %.6f m；是否采纳由人工确认" % [float(rf["sigma0_m"]), float(rf["max_res_m"])],
			})
	else:
		steps.append({"title": "4. 粗差检核（标准化残差准则）", "formula": "w = v / (σ0·√q_v)", "substitution": "", "result": "无多余观测，不具备残差检核能力（结果无精度信息）"})
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 剔除粗差点 → 重新求参 → 用剔除解参数回代全部公共点检核（bursa 版）。
## 返回 refit 字典；失败返回 {}。
static func _refit_without_outliers(src: Array, dst: Array, outliers: Array, three: bool, conv: String, k_gross: float) -> Dictionary:
	var keep := []
	for i in src.size():
		if not outliers.has(i + 1):
			keep.append(i)
	var n_unknown := 3 if three else 7
	if keep.size() * 3 <= n_unknown + 1:  # 剔除后观测数须仍大于未知数（保持多余观测）
		return {}
	var neg := -1.0 if conv == "CF" else 1.0
	var B := []
	var l := PackedFloat64Array()
	for i in keep:
		var q: PackedFloat64Array = src[i]
		var d: PackedFloat64Array = dst[i]
		if three:
			B.append(PackedFloat64Array([1.0, 0.0, 0.0]))
			l.append(d[0] - q[0])
			B.append(PackedFloat64Array([0.0, 1.0, 0.0]))
			l.append(d[1] - q[1])
			B.append(PackedFloat64Array([0.0, 0.0, 1.0]))
			l.append(d[2] - q[2])
		else:
			B.append(PackedFloat64Array([1.0, 0.0, 0.0, 0.0, neg * q[2], -neg * q[1], q[0]]))
			l.append(d[0] - q[0])
			B.append(PackedFloat64Array([0.0, 1.0, 0.0, -neg * q[2], 0.0, neg * q[0], q[1]]))
			l.append(d[1] - q[1])
			B.append(PackedFloat64Array([0.0, 0.0, 1.0, neg * q[1], -neg * q[0], 0.0, q[2]]))
			l.append(d[2] - q[2])
	var At := GKMatrix.transpose(B)
	var N := GKMatrix.multiply(At, B)
	var rhs := GKMatrix.mat_vec(At, l)
	if N.is_empty() or rhs.is_empty():
		return {}
	var xh := GKMatrix.cholesky_solve(N, rhs)
	if xh.is_empty():
		return {}
	# 残差与 σ0（剔除点集内）
	var v := PackedFloat64Array()
	v.resize(l.size())
	var ss := 0.0
	for i in l.size():
		var s := 0.0
		var row: PackedFloat64Array = B[i]
		for k in n_unknown:
			s += row[k] * xh[k]
		v[i] = s - l[i]
		ss += v[i] * v[i]
	var dof := l.size() - n_unknown
	var s0 := sqrt(ss / dof) if dof > 0 else 0.0
	# 标准化残差再检核：剔除解下不应再有新粗差（有则如实报告）
	var Ninv := GKMatrix.inverse(N)
	var new_outliers := []
	if not Ninv.is_empty() and s0 > 0.0:
		for i in l.size():
			var row: PackedFloat64Array = B[i]
			var bnbt := 0.0
			for j in n_unknown:
				var qrow: PackedFloat64Array = Ninv[j]
				var sj := 0.0
				for k in n_unknown:
					sj += qrow[k] * row[k]
				bnbt += row[j] * sj
			var q_vi := maxf(1.0 - bnbt, 1e-12)
			var wi := absf(v[i]) / (s0 * sqrt(q_vi))
			if wi > k_gross:
				new_outliers.append(keep[i / 3] + 1)
	# 用剔除解参数回代全部公共点（精确三角正算路径，与 transform 同式）
	var tx2 := xh[0]
	var ty2 := xh[1]
	var tz2 := xh[2]
	var rx2 := 0.0
	var ry2 := 0.0
	var rz2 := 0.0
	var ds2 := 0.0
	if not three:
		rx2 = xh[3]
		ry2 = xh[4]
		rz2 = xh[5]
		ds2 = xh[6]
	var ang := [rx2 * neg, ry2 * neg, rz2 * neg]  # CF 约定反号
	var R := _rot_matrix(ang[0], ang[1], ang[2])
	var max_res := 0.0
	for i in src.size():
		var q: PackedFloat64Array = src[i]
		var d: PackedFloat64Array = dst[i]
		var X: float = tx2 + (1.0 + ds2) * (R[0][0] * q[0] + R[0][1] * q[1] + R[0][2] * q[2])
		var Y: float = ty2 + (1.0 + ds2) * (R[1][0] * q[0] + R[1][1] * q[1] + R[1][2] * q[2])
		var Z: float = tz2 + (1.0 + ds2) * (R[2][0] * q[0] + R[2][1] * q[1] + R[2][2] * q[2])
		var rn := sqrt((X - d[0]) * (X - d[0]) + (Y - d[1]) * (Y - d[1]) + (Z - d[2]) * (Z - d[2]))
		if rn > max_res:
			max_res = rn
	var out := {
		"tx_m": tx2, "ty_m": ty2, "tz_m": tz2,
		"sigma0_m": s0, "max_res_m": max_res, "outliers": outliers,
		"new_outliers": new_outliers,
		"n_used": keep.size(),
		"note": "剔除解仅为一组对照参数，是否采纳请人工确认" if new_outliers.is_empty() else "剔除解下仍有新疑似粗差（点号 %s），请人工复核点据" % str(new_outliers),
	}
	if not three:
		out["rx_as"] = rx2 * RAD_TO_AS
		out["ry_as"] = ry2 * RAD_TO_AS
		out["rz_as"] = rz2 * RAD_TO_AS
		out["scale_ppm"] = ds2 * 1e6
	return out

# ---------- 内部工具 ----------

## 解析点集：接受 Array（元素为 Array/PackedFloat64Array，长度 dim，数值有限）
## 返回 {ok: bool, points: Array[PackedFloat64Array], error: String}
static func _parse_points(v: Variant, dim: int) -> Dictionary:
	if not (v is Array) or (v as Array).is_empty():
		return {"ok": false, "points": [], "error": "点集为空：请输入至少 1 个点（每行 x,y,%s）" % ("z" if dim == 3 else "…")}
	var pts := []
	var arr: Array = v
	for i in arr.size():
		var item: Variant = arr[i]
		if not (item is Array or item is PackedFloat64Array):
			return {"ok": false, "points": [], "error": "第 %d 个点不是数组（应为 x,y,z 数值列表）" % (i + 1)}
		var vals := PackedFloat64Array()
		var raw: Array = Array(item) if item is PackedFloat64Array else (item as Array)
		if raw.size() != dim:
			return {"ok": false, "points": [], "error": "第 %d 个点应为 %d 个分量，实际 %d 个" % [i + 1, dim, raw.size()]}
		for j in raw.size():
			var rv: Variant = raw[j]
			if not (rv is float or rv is int or rv is String):
				return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量类型不支持" % [i + 1, j + 1]}
			var f := 0.0
			if rv is String:
				var s := String(rv).strip_edges()
				if s.is_empty():
					return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量为空" % [i + 1, j + 1]}
				if not s.is_valid_float():
					return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量不是有效数字：「%s」" % [i + 1, j + 1, s]}
				f = s.to_float()
			else:
				f = float(rv)
			if not is_finite(f):
				return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量不是有限数值" % [i + 1, j + 1]}
			vals.append(f)
		pts.append(vals)
	return {"ok": true, "points": pts, "error": ""}

## 读取七参数输入并归一到 PV 弧度。返回 {ok, tx,ty,tz, angles_rad(3), ds, rx_as,ry_as,rz_as, scale_ppm, convention, error}
static func _read_params(p: Dictionary) -> Dictionary:
	var conv := String(p.get("convention", "PV")).strip_edges().to_upper()
	if conv != "PV" and conv != "CF":
		return {"ok": false, "error": "旋转约定仅支持 PV（位置向量）或 CF（坐标框架），收到：%s" % conv}
	var names := ["tx_m", "ty_m", "tz_m", "rx_as", "ry_as", "rz_as", "scale_ppm"]
	var zh_names := {"tx_m": "平移 Tx", "ty_m": "平移 Ty", "tz_m": "平移 Tz",
		"rx_as": "旋转 Rx", "ry_as": "旋转 Ry", "rz_as": "旋转 Rz", "scale_ppm": "尺度 dS"}
	var vals := {}
	var zero_filled := PackedStringArray()
	for key in names:
		var zh: String = String(zh_names[key])
		var raw: Variant = p.get(key, 0.0)
		if not (raw is float or raw is int or raw is String):
			return {"ok": false, "error": "参数 %s 类型不支持" % zh}
		var f := 0.0
		if raw is String:
			var s := String(raw).strip_edges()
			if s.is_empty():
				f = 0.0  # 留空按 0（三参数/无旋转场景）
				zero_filled.append(zh)
			elif not s.is_valid_float():
				return {"ok": false, "error": "参数 %s 不是有效数字：「%s」" % [zh, s]}
			else:
				f = s.to_float()
		else:
			f = float(raw)
		if not is_finite(f):
			return {"ok": false, "error": "参数 %s 不是有限数值" % zh}
		vals[key] = f
	var rx: float = vals["rx_as"] * AS_TO_RAD
	var ry: float = vals["ry_as"] * AS_TO_RAD
	var rz: float = vals["rz_as"] * AS_TO_RAD
	if conv == "CF":
		rx = -rx
		ry = -ry
		rz = -rz
	return {
		"ok": true, "tx": vals["tx_m"], "ty": vals["ty_m"], "tz": vals["tz_m"],
		"angles_rad": [rx, ry, rz], "ds": vals["scale_ppm"] * 1e-6,
		"rx_as": vals["rx_as"], "ry_as": vals["ry_as"], "rz_as": vals["rz_as"],
		"scale_ppm": vals["scale_ppm"], "convention": conv,
		"zero_filled": zero_filled, "error": "",
	}

## solve 用：只校验 convention，不要求参数存在
static func _read_params_for_solve(p: Dictionary) -> Dictionary:
	var conv := String(p.get("convention", "PV")).strip_edges().to_upper()
	if conv != "PV" and conv != "CF":
		return {"ok": false, "error": "旋转约定仅支持 PV（位置向量）或 CF（坐标框架），收到：%s" % conv}
	return {"ok": true, "convention": conv, "error": ""}

## 右手系正旋转矩阵 R = Rz·Ry·Rx（精确三角函数），返回 3×3 二维 Array
static func _rot_matrix(rx: float, ry: float, rz: float) -> Array:
	var cx := cos(rx)
	var sx := sin(rx)
	var cy := cos(ry)
	var sy := sin(ry)
	var cz := cos(rz)
	var sz := sin(rz)
	var Rx := [[1.0, 0.0, 0.0], [0.0, cx, -sx], [0.0, sx, cx]]
	var Ry := [[cy, 0.0, sy], [0.0, 1.0, 0.0], [-sy, 0.0, cy]]
	var Rz := [[cz, -sz, 0.0], [sz, cz, 0.0], [0.0, 0.0, 1.0]]
	# M = Rz·Ry
	var M := []
	for i in 3:
		var row := []
		for j in 3:
			var s := 0.0
			for k in 3:
				s += Rz[i][k] * Ry[k][j]
			row.append(s)
		M.append(row)
	# R = M·Rx
	var R := []
	for i in 3:
		var row := []
		for j in 3:
			var s := 0.0
			for k in 3:
				s += M[i][k] * Rx[k][j]
			row.append(s)
		R.append(row)
	return R

static func _param_text(three: bool, tx: float, ty: float, tz: float, rx_as: float, ry_as: float, rz_as: float, scale_ppm: float) -> String:
	if three:
		return "tx = %.4f m，ty = %.4f m，tz = %.4f m" % [tx, ty, tz]
	return "tx = %.4f m，ty = %.4f m，tz = %.4f m；rx = %.6f″，ry = %.6f″，rz = %.6f″；dS = %.6f ppm" % [tx, ty, tz, rx_as, ry_as, rz_as, scale_ppm]

static func _err(formula: String, msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": msg}
