# core/transform/four_param.gd —— GK-M4-2（A8）：平面四参数相似变换（求参 + 正算 + 反算）
#
# 正算 X=dx+m(x·cosα−y·sinα)、Y=dy+m(x·sinα+y·cosα)；反算由 m=√(a²+b²)、α=atan2(b,a) 还原。
# 求参未知量 [dx,dy,a,b]，法方程经 GKMatrix.cholesky_solve（Wave 0 冻结 API）；
# 粗差用标准化残差 w=v/(σ0√q_v)，|w|>3 判定并自动「剔除→重求参→再检核」（入 value.refit，保留提示）。
# 纯 GDScript、零引擎依赖；失败一律 {ok:false,value:{},error:中文}。
class_name GKFourParam
extends RefCounted

const RAD_TO_AS: float = 180.0 * 3600.0 / PI  # 1 rad = 206264.80624709636″

## 求参（§5 协议入口）。p：{src_xy: [[x,y],...], dst_xy: [[x,y],...], k_gross? = 3.0}
## value：{dx_m, dy_m, scale, alpha_deg, alpha_dms, sigma0_m, rms_m, residuals_m, outliers, warnings,
##          refit（剔除迭代结果，检出粗差时）, ...}
static func solve(p: Dictionary) -> Dictionary:
	var formula := "平面四参数求参：X = dx + a·x − b·y，Y = dy + b·x + a·y（a=m·cosα，b=m·sinα），最小二乘 N=BᵀB"
	var src := _parse_points(p.get("src_xy", []), 2)
	if not src.ok:
		return _err(formula, src.error)
	var dst := _parse_points(p.get("dst_xy", []), 2)
	if not dst.ok:
		return _err(formula, dst.error)
	if src.points.size() != dst.points.size():
		return _err(formula, "源系与目标系公共点数量不一致：%d 与 %d" % [src.points.size(), dst.points.size()])
	var n: int = src.points.size()
	if n < 2:
		return _err(formula, "四参数求参至少需要 2 个公共点（当前 %d 个）" % n)
	var k_gross := 3.0
	if p.has("k_gross") and is_finite(float(p["k_gross"])) and float(p["k_gross"]) > 0.0:
		k_gross = float(p["k_gross"])
	# 组成误差方程：未知量 [dx, dy, a, b]
	var B := []
	var l := PackedFloat64Array()
	for i in n:
		var q: PackedFloat64Array = src.points[i]
		var d: PackedFloat64Array = dst.points[i]
		B.append(PackedFloat64Array([1.0, 0.0, q[0], -q[1]]))
		l.append(d[0])
		B.append(PackedFloat64Array([0.0, 1.0, q[1], q[0]]))
		l.append(d[1])
	var n_obs := l.size()
	var At := GKMatrix.transpose(B)
	var N := GKMatrix.multiply(At, B)
	var rhs := GKMatrix.mat_vec(At, l)
	if N.is_empty() or rhs.is_empty():
		return _err(formula, "法方程组成异常（维度不匹配）")
	var xhat := GKMatrix.cholesky_solve(N, rhs)
	var xg := GKMatrix.solve(N, rhs)  # 独立路径互检（高斯消元含相对容差零行/奇异检测）
	if xhat.is_empty() or xg.is_empty():
		return _err(formula, "法方程奇异，无法求参——公共点几何退化（如两点重合、所有点共线），请检查点位配置")
	# 双路径一致性：严重病态时两路径解显著分叉（Cholesky 对近奇异 N 因 sqrt 取整可能漏检）
	var max_x := 1.0
	for val in xhat:
		max_x = maxf(max_x, absf(val))
	for k in xhat.size():
		if absf(xhat[k] - xg[k]) > 1e-4 * max_x:
			return _err(formula, "法方程严重病态（双解路径不一致），请检查公共点几何配置")
	var dx := xhat[0]
	var dy := xhat[1]
	var a := xhat[2]
	var b := xhat[3]
	var m := sqrt(a * a + b * b)
	if m < 1e-15:
		return _err(formula, "尺度解算异常（m≈0），公共点配置无效")
	var alpha_rad := atan2(b, a)
	var alpha_deg := rad_to_deg(alpha_rad)
	# 残差
	var v := PackedFloat64Array()
	v.resize(n_obs)
	for i in n_obs:
		var s := 0.0
		var row: PackedFloat64Array = B[i]
		for k in 4:
			s += row[k] * xhat[k]
		v[i] = s - l[i]
	var ss := 0.0
	for val in v:
		ss += val * val
	var redundancy := n_obs - 4
	var sigma0 := sqrt(ss / redundancy) if redundancy > 0 else 0.0
	# 标准化残差粗差检核：w_i = v_i / (σ0·√q_vi)，q_vi = 1 − b_i·N⁻¹·b_iᵀ（等权）
	var Ninv := GKMatrix.inverse(N)
	var w := PackedFloat64Array()
	w.resize(n_obs)
	var residuals := []
	var warnings := PackedStringArray()
	var outliers := []
	if redundancy > 0 and sigma0 > 0.0 and not Ninv.is_empty():
		for i in n_obs:
			var row: PackedFloat64Array = B[i]
			var bnbt := 0.0
			for j in 4:
				var qrow: PackedFloat64Array = Ninv[j]
				var sj := 0.0
				for k in 4:
					sj += qrow[k] * row[k]
				bnbt += row[j] * sj
			var q_vi := 1.0 - bnbt
			if q_vi <= 1e-12:
				q_vi = 1e-12  # 必要观测位置冗余度≈0：夹到微正防止除零
			w[i] = absf(v[i]) / (sigma0 * sqrt(q_vi))
		var limit := k_gross * sigma0
		for i in n:
			var vx: float = v[i * 2]
			var vy: float = v[i * 2 + 1]
			residuals.append([i + 1, vx, vy])
			var comps := [[vx, "ΔX", w[i * 2]], [vy, "ΔY", w[i * 2 + 1]]]
			for c in comps:
				if c[2] > k_gross:
					outliers.append(i + 1)
					warnings.append("第 %d 点 %s 分量残差 %.4f m，标准化残差 |w|=%.2f 超过限值 k=%.1f（σ0=%.4f m），疑似粗差，建议人工确认后剔除该点重新求参" % [i + 1, c[1], c[0], c[2], k_gross, sigma0])
	else:
		for i in n:
			residuals.append([i + 1, v[i * 2], v[i * 2 + 1]])
	var rms := sqrt(ss / n_obs)
	# 参数中误差：σ0·√Qxx 对角元；m/α 的 σ 由 a、b 的协方差阵（σ0²·Qxx）经雅可比传播
	var sigma_dx := NAN
	var sigma_alpha_as := NAN
	var sigma_scale := NAN
	if not Ninv.is_empty() and redundancy > 0 and sigma0 > 0.0:
		var q22: float = (Ninv[2] as PackedFloat64Array)[2]
		var q33: float = (Ninv[3] as PackedFloat64Array)[3]
		var q23: float = (Ninv[2] as PackedFloat64Array)[3]
		sigma_dx = sigma0 * sqrt(absf((Ninv[0] as PackedFloat64Array)[0]))
		# m = √(a²+b²)：∂m/∂a = a/m，∂m/∂b = b/m → σ_m² = (σ0²/m²)·(a²·q22 + 2ab·q23 + b²·q33)
		# α = atan2(b, a)：∂α/∂a = −b/m²，∂α/∂b = a/m² → σ_α² = (σ0²/m⁴)·(b²·q22 − 2ab·q23 + a²·q33)
		# 注：本参数化下 q23 = Σ(−x_i·y_i + x_i·y_i) ≡ 0，交叉项数值上恒为 0，符号按雅可比传播如实书写
		var sm2 := (a * a * q22 + 2.0 * a * b * q23 + b * b * q33)
		var sa2 := (b * b * q22 - 2.0 * a * b * q23 + a * a * q33) / (m * m * m * m)
		if sm2 >= 0.0:
			sigma_scale = sigma0 * sqrt(sm2) / m
		if sa2 >= 0.0:
			sigma_alpha_as = sigma0 * sqrt(sa2) * RAD_TO_AS
	var dms := _deg_to_dms_text(alpha_deg)
	var value := {
		"dx_m": dx, "dy_m": dy,
		"scale": m,
		"alpha_deg": alpha_deg,
		"alpha_dms": dms,
		"n_points": n, "n_obs": n_obs, "n_unknown": 4, "redundancy": redundancy,
		"sigma0_m": sigma0, "rms_m": rms,
		"residuals_m": residuals,
		"outliers": outliers,
		"basis": "线性化 LS（a=m·cosα, b=m·sinα）；σ_m/σ_α 由 a、b 协方差阵经雅可比传播（含协方差项）",
	}
	if not is_nan(sigma_dx):
		value["sigma_dx_m"] = sigma_dx
		value["sigma_dy_m"] = sigma0 * sqrt(absf((Ninv[1] as PackedFloat64Array)[1]))
		value["sigma_alpha_s"] = sigma_alpha_as
		value["sigma_scale"] = sigma_scale
	var max_res := 0.0
	for i in n:
		var rn: float = sqrt(v[i * 2] * v[i * 2] + v[i * 2 + 1] * v[i * 2 + 1])
		if rn > max_res:
			max_res = rn
	value["max_res_m"] = max_res
	# —— 剔除 → 重新求参 → 再检核迭代（检出粗差且仍有多余观测时执行；保留人工确认） ——
	if not outliers.is_empty() and redundancy > 0 and sigma0 > 0.0:
		var refit_res := _refit_without_outliers(src.points, dst.points, outliers, k_gross)
		if not refit_res.is_empty():
			value["refit"] = refit_res
			warnings.append("已按剔除迭代求得一组不含粗差点的参数（见 refit），请人工确认比对后决定是否采纳；采纳前本页保留全点解")
	# warnings 在剔除迭代 append 之后回写，避免快照缺项
	value["warnings"] = Array(warnings)
	var steps := [
		{
			"title": "1. 线性化误差方程",
			"formula": "X = dx + a·x − b·y；Y = dy + b·x + a·y（未知量 [dx, dy, a, b]，a=m·cosα，b=m·sinα）",
			"substitution": "公共点 %d 个 → %d 个观测方程（每点 2 条）" % [n, n_obs],
			"result": "多余观测数（自由度）= %d" % redundancy,
		},
		{
			"title": "2. 法方程组成与求解",
			"formula": "N·x̂ = Bᵀl，N = BᵀB（Cholesky 分解求解）",
			"substitution": "N 为 4×4 矩阵；l 为目标系公共点坐标代入",
			"result": "dx = %.4f m，dy = %.4f m，a = m·cosα = %.9f，b = m·sinα = %.9f" % [dx, dy, a, b],
		},
		{
			"title": "3. 尺度与旋转角还原",
			"formula": "m = √(a² + b²)；α = atan2(b, a)",
			"substitution": "m = √(%.9f² + %.9f²)；α = atan2(%.9f, %.9f)" % [a, b, b, a],
			"result": "m = %.9f，α = %.9f°（%s）" % [m, alpha_deg, dms],
		},
		{
			"title": "4. 精度评定",
			"formula": "σ0 = √(VᵀV / (2n − 4))；σ_α = σ0·√(b²·q22 − 2ab·q23 + a²·q33)/m²；σ_m = σ0·√(a²·q22 + 2ab·q23 + b²·q33)/m",
			"substitution": "VᵀV = %.9f m²，自由度 = %d" % [ss, redundancy],
			"result": "σ0 = %.6f m，观测 RMS = %.6f m，最大点残差 = %.6f m" % [sigma0, rms, max_res],
		},
	]
	if redundancy > 0 and sigma0 > 0.0 and not Ninv.is_empty():
		var step_res := "无粗差（max|w|=%.2f ≤ k=%.1f）" % [_max_abs_w(w), k_gross]
		if not warnings.is_empty():
			step_res = "\n".join(warnings)
		steps.append({
			"title": "5. 粗差检核（标准化残差准则）",
			"formula": "w = v / (σ0·√q_v)，q_v = 1 − b·N⁻¹·bᵀ（改正数协因数阵对角元）；|w| > k 判为疑似粗差",
			"substitution": "k = %.1f，σ0 = %.6f m" % [k_gross, sigma0],
			"result": step_res,
		})
		if value.has("refit"):
			var rf: Dictionary = value["refit"]
			steps.append({
				"title": "6. 剔除迭代（剔除 → 重新求参 → 再检核）",
				"formula": "剔除 |w| > k 的公共点后重新组成法方程求解，再用剔除解参数回代全部点检核",
				"substitution": "剔除点号：%s；剔除解：dx = %.4f m，dy = %.4f m，m = %.9f，α = %.9f°" % [str(outliers), float(rf["dx_m"]), float(rf["dy_m"]), float(rf["scale"]), float(rf["alpha_deg"])],
				"result": "剔除解 σ0 = %.6f m；回代全部点最大残差 = %.6f m；是否采纳由人工确认" % [float(rf["sigma0_m"]), float(rf["max_res_m"])],
			})
	else:
		steps.append({"title": "5. 粗差检核（标准化残差准则）", "formula": "w = v / (σ0·√q_v)", "substitution": "", "result": "两点求参无多余观测，不具备残差检核能力（结果无精度信息）"})
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 剔除粗差点 → 重新求参 → 用剔除解参数回代全部公共点检核。
## 返回 refit 字典 {dx_m, dy_m, scale, alpha_deg, sigma0_m, max_res_m, outliers}；失败返回 {}。
static func _refit_without_outliers(src: Array, dst: Array, outliers: Array, k_gross: float) -> Dictionary:
	var keep := []
	for i in src.size():
		if not outliers.has(i + 1):
			keep.append(i)
	if keep.size() < 2 or (keep.size() * 2 - 4) <= 0:
		return {}
	var B := []
	var l := PackedFloat64Array()
	for i in keep:
		var q: PackedFloat64Array = src[i]
		var d: PackedFloat64Array = dst[i]
		B.append(PackedFloat64Array([1.0, 0.0, q[0], -q[1]]))
		l.append(d[0])
		B.append(PackedFloat64Array([0.0, 1.0, q[1], q[0]]))
		l.append(d[1])
	var At := GKMatrix.transpose(B)
	var N := GKMatrix.multiply(At, B)
	var rhs := GKMatrix.mat_vec(At, l)
	if N.is_empty() or rhs.is_empty():
		return {}
	var xh := GKMatrix.cholesky_solve(N, rhs)
	if xh.is_empty():
		return {}
	# 残差（剔除点集内）与 σ0
	var v := PackedFloat64Array()
	v.resize(l.size())
	var ss := 0.0
	for i in l.size():
		var s := 0.0
		var row: PackedFloat64Array = B[i]
		for k in 4:
			s += row[k] * xh[k]
		v[i] = s - l[i]
		ss += v[i] * v[i]
	var dof := l.size() - 4
	var s0 := sqrt(ss / dof) if dof > 0 else 0.0
	# 标准化残差再检核：剔除解下不应再有新粗差（有则如实报告）
	var Ninv := GKMatrix.inverse(N)
	var new_outliers := []
	if not Ninv.is_empty() and s0 > 0.0:
		for i in l.size():
			var row: PackedFloat64Array = B[i]
			var bnbt := 0.0
			for j in 4:
				var qrow: PackedFloat64Array = Ninv[j]
				var sj := 0.0
				for k in 4:
					sj += qrow[k] * row[k]
				bnbt += row[j] * sj
			var q_vi := maxf(1.0 - bnbt, 1e-12)
			var wi := absf(v[i]) / (s0 * sqrt(q_vi))
			if wi > k_gross:
				new_outliers.append(keep[i / 2] + 1)
	# 用剔除解参数回代全部公共点
	var m2 := sqrt(xh[2] * xh[2] + xh[3] * xh[3])
	var al := atan2(xh[3], xh[2])
	var ca := cos(al)
	var sa := sin(al)
	var max_res := 0.0
	for i in src.size():
		var q: PackedFloat64Array = src[i]
		var d: PackedFloat64Array = dst[i]
		var X := xh[0] + m2 * (q[0] * ca - q[1] * sa)
		var Y := xh[1] + m2 * (q[0] * sa + q[1] * ca)
		var rn := sqrt((X - d[0]) * (X - d[0]) + (Y - d[1]) * (Y - d[1]))
		if rn > max_res:
			max_res = rn
	return {
		"dx_m": xh[0], "dy_m": xh[1], "scale": m2, "alpha_deg": rad_to_deg(al),
		"sigma0_m": s0, "max_res_m": max_res, "outliers": outliers,
		"new_outliers": new_outliers,
		"n_used": keep.size(),
		"note": "剔除解仅为一组对照参数，是否采纳请人工确认" if new_outliers.is_empty() else "剔除解下仍有新疑似粗差（点号 %s），请人工复核点据" % str(new_outliers),
	}

static func _max_abs_w(w: PackedFloat64Array) -> float:
	var mx := 0.0
	for val in w:
		mx = maxf(mx, val)
	return mx

## 正算 / 反算（§5 协议入口）。p：{mode: "fwd"|"inv", dx_m, dy_m, scale, alpha_deg, src_xy / dst_xy}
static func apply(p: Dictionary) -> Dictionary:
	var mode := String(p.get("mode", "fwd")).strip_edges().to_lower()
	if mode != "fwd" and mode != "inv":
		return _err("", "模式仅支持 fwd（正算）或 inv（反算），收到：%s" % mode)
	var fwd := mode == "fwd"
	var formula := "正算：X = dx + m·(x·cosα − y·sinα)，Y = dy + m·(x·sinα + y·cosα)" if fwd else "反算：x = [(X−dx)·cosα + (Y−dy)·sinα]/m，y = [−(X−dx)·sinα + (Y−dy)·cosα]/m"
	var pts_in := _parse_points(p.get("src_xy" if fwd else "dst_xy", []), 2)
	if not pts_in.ok:
		return _err(formula, pts_in.error)
	var mres := _read_params(p)
	if not mres.ok:
		return _err(formula, mres.error)
	var dx: float = mres.dx
	var dy: float = mres.dy
	var m: float = mres.scale
	var al: float = deg_to_rad(mres.alpha_deg)
	var ca := cos(al)
	var sa := sin(al)
	var out := []
	for q: PackedFloat64Array in pts_in.points:
		if fwd:
			out.append([
				dx + m * (q[0] * ca - q[1] * sa),
				dy + m * (q[0] * sa + q[1] * ca),
			])
		else:
			var ddx := q[0] - dx
			var ddy := q[1] - dy
			out.append([
				(ddx * ca + ddy * sa) / m,
				(-ddx * sa + ddy * ca) / m,
			])
	var q0: PackedFloat64Array = pts_in.points[0]
	var r0: Array = out[0]
	var steps := [
		{
			"title": "1. 变换参数",
			"formula": formula,
			"substitution": "dx=%.4f m，dy=%.4f m，m=%.9f，α=%.6f°，共 %d 点" % [dx, dy, m, mres.alpha_deg, out.size()],
			"result": "%s" % ("源坐标系 → 目标坐标系" if fwd else "目标坐标系 → 源坐标系"),
		},
		{
			"title": "2. 单点代入",
			"formula": "以首点代入变换公式",
			"substitution": "输入点 (%.4f, %.4f)" % [q0[0], q0[1]],
			"result": "输出点 (%.6f, %.6f)" % [r0[0], r0[1]],
		},
	]
	if out.size() > 1:
		steps.append({"title": "3. 其余各点同式计算", "formula": "", "substitution": "", "result": "共 %d 点，见结果表" % out.size()})
	var value := {"points_m": out, "n": out.size(), "mode": "fwd" if fwd else "inv"}
	if out.size() == 1:
		value["x_m"] = r0[0]
		value["y_m"] = r0[1]
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

# ---------- 内部工具 ----------

static func _read_params(p: Dictionary) -> Dictionary:
	var zh_names := {"dx_m": "平移 dx", "dy_m": "平移 dy", "scale": "尺度 m", "alpha_deg": "旋转角 α"}
	var out := {}
	for key in ["dx_m", "dy_m", "scale", "alpha_deg"]:
		var zh: String = String(zh_names[key])
		var raw: Variant = p.get(key, 0.0)
		if not (raw is float or raw is int or raw is String):
			return {"ok": false, "error": "参数 %s 类型不支持" % zh}
		var f := 0.0
		if raw is String:
			var s := String(raw).strip_edges()
			if s.is_empty():
				return {"ok": false, "error": "参数 %s 为空，请填写四参数（dx、dy、m、α）" % zh}
			if not s.is_valid_float():
				return {"ok": false, "error": "参数 %s 不是有效数字：「%s」" % [zh, s]}
			f = s.to_float()
		else:
			f = float(raw)
		if not is_finite(f):
			return {"ok": false, "error": "参数 %s 不是有限数值" % zh}
		out[key] = f
	if absf(out["scale"]) < 1e-15:
		return {"ok": false, "error": "尺度参数 m 不能为 0"}
	return {"ok": true, "dx": out["dx_m"], "dy": out["dy_m"], "scale": out["scale"], "alpha_deg": out["alpha_deg"], "error": ""}

static func _parse_points(v: Variant, dim: int) -> Dictionary:
	if not (v is Array) or (v as Array).is_empty():
		return {"ok": false, "points": [], "error": "点集为空：请输入至少 1 个点（每行 x,y）"}
	var pts := []
	var arr: Array = v
	for i in arr.size():
		var item: Variant = arr[i]
		if not (item is Array or item is PackedFloat64Array):
			return {"ok": false, "points": [], "error": "第 %d 个点不是数组（应为 x,y 数值列表）" % (i + 1)}
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

static func _deg_to_dms_text(deg: float) -> String:
	var sign := "-" if deg < 0.0 else ""
	var ad := absf(deg)
	var d := floorf(ad)
	var m_f := (ad - d) * 60.0
	var mi := floorf(m_f)
	var s := (m_f - mi) * 60.0
	# 秒 60 的浮点残余进位
	if s >= 59.9995:
		s = 0.0
		mi += 1.0
	if mi >= 60.0:
		mi = 0.0
		d += 1.0
	return "%s%d°%02d′%05.2f″" % [sign, int(d), int(mi), s]

static func _err(formula: String, msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": msg}
