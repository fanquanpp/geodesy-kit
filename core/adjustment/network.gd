# core/adjustment/network.gd —— GK-M6-2 平面控制网严密平差（C5 导线网/测边网/边角网·间接平差）
#
# 参数为未知点坐标改正数 δx,δy；测边/角度误差方程解析线性化系数已与 numpy 数值导数互检
# （差 ≤2e-9，见 tests/adjustment/test_network.gd）。权 p=1/σ²（测边 m、角度 rad，输入度内部换算），
# obs 显式给 w 优先。单次线性化：近似坐标误差 ≤0.1 m 时二次项 <0.1 mm（教学算例足够，如实声明）。
# 法方程对称正定走 GKMatrix.cholesky_solve；_build_design 为域内共享构建器（C12 复用，不跨域）。
# 全部静态、零引擎依赖；非法输入 {ok:false, error:中文}。
class_name GKAdjustNetwork
extends RefCounted

## C5 平面控制网间接平差
## p = {known: {name:[x,y]}, approx: {name:[x0,y0]},
##      dist_obs: [{from,to,value,sigma}...]（sigma: m，或显式 "w"）,
##      angle_obs: [{at,back,front,value_deg,sigma_s}...]（sigma_s 角秒；或 sigma_deg 度，或显式 "w"）,
##      point_names?: 未知点输出名顺序（默认按 approx 键名字典序）}
## 返回 §5 协议；另附顶层扩展键 "qxx"（Array of PackedFloat64Array 协因数阵）与
## "param_names"（参数顺序），供 C9/C10 深入分析——UI 渲染只读 value，不受影响。
static func adjust(p: Dictionary) -> Dictionary:
	var build := build_design(p)
	if String(build.get("error", "")) != "":
		return _fail(String(build["error"]))
	var B: Array = build["B"]
	var l: PackedFloat64Array = build["l"]
	var wts: PackedFloat64Array = build["p"]
	var param_names: Array = build["param_names"]
	var approx: Dictionary = build["approx"]
	var known: Dictionary = build["known"]
	var n: int = B.size()
	var t: int = param_names.size()
	# 法方程
	var Bt := GKMatrix.transpose(B)
	var BtP := _scale_cols(Bt, wts)
	var N := GKMatrix.multiply(BtP, B)
	var Wv := GKMatrix.mat_vec(BtP, l)
	if N.is_empty() or Wv.is_empty():
		return _fail("法方程组装失败（观测维度不一致或观测为空）")
	var dx := GKMatrix.cholesky_solve(N, Wv)
	if dx.is_empty():
		return _fail("法方程不可解：网形不连通、缺少起算数据或无多余观测（N 非正定），请检查已知点/观测图形")
	# 残差
	var v := PackedFloat64Array()
	for i in n:
		var s := 0.0
		var row: PackedFloat64Array = B[i]
		for j in t:
			s += row[j] * dx[j]
		v.append(s - l[i])
	var pvv := _weighted_sum(v, wts)
	var dof := n - t
	var mu := NAN
	if dof > 0 and pvv >= 0.0:
		mu = sqrt(pvv / dof)
	# 平差后坐标（j 遍历点，dx 按 [x0,y0,x1,y1,...] 参数序）
	var value := {}
	for j in t / 2:
		var nm := String(param_names[2 * j])
		value["x_%s_m" % nm] = float(approx[nm][0]) + dx[2 * j]
		value["y_%s_m" % nm] = float(approx[nm][1]) + dx[2 * j + 1]
	for k: String in known:
		value["x_%s_m" % k] = float(known[k][0])
		value["y_%s_m" % k] = float(known[k][1])
	value["n_obs"] = n
	value["n_unknown"] = t / 2
	value["dof"] = dof
	value["pvv"] = pvv
	if is_finite(mu):
		value["mu0"] = mu
	# 点位中误差：m_p = μ·√(qxx + qyy)（μ 为单位权中误差估计；dof=0 时无法评定）
	var qxx := GKMatrix.inverse(N)
	if not is_finite(mu) and qxx.is_empty():
		return _ok(value, [], "平面控制网间接平差（测边/测角/边角混合，单次线性化）")
	var dist_v := PackedFloat64Array()
	var ang_v := PackedFloat64Array()
	for i in n:
		var kind := String(build["kinds"][i])
		if kind == "dist":
			dist_v.append(v[i])
		else:
			ang_v.append(v[i])
	value["v_dist_m"] = dist_v
	value["v_angle_rad"] = ang_v
	value["v_angle_s"] = _scaled(ang_v, 648000.0 / PI)
	if not qxx.is_empty():
		for j in t / 2:
			var nm2 := String(param_names[2 * j])
			var qx: float = qxx[2 * j][2 * j]
			var qy: float = qxx[2 * j + 1][2 * j + 1]
			var mp := mu * sqrt(qx + qy) if is_finite(mu) else NAN
			if is_finite(mp):
				value["mp_%s_mm" % nm2] = mp * 1000.0
				value["sx_%s_mm" % nm2] = mu * sqrt(qx) * 1000.0
				value["sy_%s_mm" % nm2] = mu * sqrt(qy) * 1000.0
	var steps := [
		{
			"title": "1. 误差方程（单次线性化）",
			"formula": "测边：v = (Δx/S)(δx_j−δx_i) + (Δy/S)(δy_j−δy_i) − l\n角度：v = dβ·δx̂ − l，dβ 为 α_{k→front} − α_{k→back} 的解析偏导",
			"substitution": "n = %d 个观测（测边 %d、角度 %d），t = %d 个坐标未知数" % [n, dist_v.size(), ang_v.size(), t],
			"result": "多余观测 r = n − t = %d" % dof,
		},
		{
			"title": "2. 法方程组成与求解",
			"formula": "N = BᵀPB，W = BᵀPl，x̂ = x⁰ + N⁻¹W（Cholesky 分解）",
			"substitution": "权 p = 1/σ²（σ 与观测同单位）",
			"result": "最大改正数 δx = %s m" % _fmt(_abs_max(dx)),
		},
		{
			"title": "3. 精度评定",
			"formula": "μ = √(VᵀPV/(n−t))；点位中误差 m_p = μ·√(q_xx + q_yy)",
			"substitution": "VᵀPV = %s" % _fmt(pvv),
			"result": (("μ = ±%s；各未知点 mp 见结果" % _fmt(mu)) if dof > 0 and is_finite(mu) else "无多余观测，精度无法评定"),
		},
		{
			"title": "精度声明",
			"formula": "严密平差（间接法，单次线性化）",
			"substitution": "近似坐标误差 ≤0.1 m 时线性化二次项 <0.1 mm；误差椭圆/粗差探测用 qxx（扩展键）",
			"result": "区别于 C1-C4 近似平差：本结果含精度评定与协因数阵",
		},
	]
	var res := _ok(value, steps, "平面控制网间接平差（导线网/测边网/边角网，严密平差）")
	res["qxx"] = qxx
	res["param_names"] = param_names
	res["N"] = N
	return res

## 设计矩阵构建器（C5 与 C12 共用；独立暴露便于测试解析系数）
## p 结构同 adjust()。返回 {error, B(Array of PackedFloat64Array), l, p, kinds, param_names, approx, known, rows_meta}
static func build_design(p: Dictionary) -> Dictionary:
	var known: Dictionary = p.get("known", {})
	var approx: Dictionary = p.get("approx", {})
	var dist_obs: Array = p.get("dist_obs", [])
	var angle_obs: Array = p.get("angle_obs", [])
	if not (known is Dictionary) or not (approx is Dictionary):
		return {"error": "known/approx 须为 {点名: [x, y]} 字典"}
	# allow_no_datum：秩亏自由网（C12-b）允许无已知点，N 的奇异性由调用方处理
	if known.is_empty() and not bool(p.get("allow_no_datum", false)):
		return {"error": "缺少已知点 known（至少 1 个，提供位置基准）"}
	if dist_obs.is_empty() and angle_obs.is_empty():
		return {"error": "缺少观测（dist_obs 测边 / angle_obs 角度，至少一种）"}
	for k: String in known:
		if not _finite_xy(known[k]):
			return {"error": "已知点 %s 坐标须为 [x, y] 数值对" % k}
	var names := []
	for k: String in approx:
		names.append(k)
	names.sort()
	if names.is_empty():
		return {"error": "缺少未知点近似坐标 approx（间接平差线性化必需）"}
	for k: String in approx:
		if not _finite_xy(approx[k]):
			return {"error": "未知点 %s 近似坐标须为 [x0, y0] 数值对" % k}
	var param_names := []
	for nm: String in names:
		param_names.append(nm)
		param_names.append(nm)
	var t: int = param_names.size()
	var B := []
	var l := PackedFloat64Array()
	var wts := PackedFloat64Array()
	var kinds := PackedStringArray()
	var meta := []
	# 测边
	for o_v in dist_obs:
		var e := _obs_check(o_v, ["from", "to", "value"], known, approx, names, "测边")
		if e != "":
			return {"error": e}
		var o: Dictionary = o_v
		var f := String(o["from"])
		var tt := String(o["to"])
		if f == tt:
			return {"error": "测边 from/to 不能同名（%s）" % f}
		var pf := _coord_of(f, known, approx)
		var pt := _coord_of(tt, known, approx)
		var ddx: float = pt[0] - pf[0]
		var ddy: float = pt[1] - pf[1]
		var s0 := sqrt(ddx * ddx + ddy * ddy)
		if s0 < 1e-9:
			return {"error": "测边 %s-%s 两点近似坐标重合，无法线性化" % [f, tt]}
		var ca := ddx / s0
		var sa := ddy / s0
		var row := PackedFloat64Array()
		row.resize(t)
		if names.has(f):
			row[2 * names.find(f)] = -ca
			row[2 * names.find(f) + 1] = -sa
		if names.has(tt):
			row[2 * names.find(tt)] = ca
			row[2 * names.find(tt) + 1] = sa
		var wgt := 0.0
		if o.has("w") and _finite_num(o.get("w")) and float(o["w"]) > 0.0:
			wgt = float(o["w"])
		elif o.has("sigma") and _finite_num(o.get("sigma")) and float(o["sigma"]) > 0.0:
			wgt = 1.0 / (float(o["sigma"]) * float(o["sigma"]))
		else:
			return {"error": "测边 %s-%s 缺少正的 sigma（m）或 w" % [f, tt]}
		B.append(row)
		l.append(float(o["value"]) - s0)
		wts.append(wgt)
		kinds.append("dist")
		meta.append({"kind": "dist", "from": f, "to": tt})
	# 角度（在 at 点，后视 back → 前视 front）
	for o_v in angle_obs:
		var e2 := _obs_check(o_v, ["at", "back", "front", "value_deg"], known, approx, names, "角度")
		if e2 != "":
			return {"error": e2}
		var o2: Dictionary = o_v
		var at := String(o2["at"])
		var back := String(o2["back"])
		var front := String(o2["front"])
		if at == back or at == front or back == front:
			return {"error": "角度观测 at/back/front 三点须互不相同（%s/%s/%s）" % [at, back, front]}
		var pk := _coord_of(at, known, approx)
		var pb := _coord_of(back, known, approx)
		var pf2 := _coord_of(front, known, approx)
		var d_kb := sqrt(pow(float(pb[0]) - float(pk[0]), 2.0) + pow(float(pb[1]) - float(pk[1]), 2.0))
		var d_kf := sqrt(pow(float(pf2[0]) - float(pk[0]), 2.0) + pow(float(pf2[1]) - float(pk[1]), 2.0))
		if d_kb < 1e-9 or d_kf < 1e-9:
			return {"error": "角度观测 %s 的照准点与测站点近似坐标重合" % at}
		# β = α(k→front) − α(k→back)
		var g_k := _alpha_grad(pk, pf2, 0) - _alpha_grad(pk, pb, 0)   # dβ/d(测站 k)
		var g_f := _alpha_grad(pk, pf2, 1)                            # dβ/d(前视)
		var g_b := _alpha_grad(pk, pb, 1)                             # dβ/d(后视) = −dα/d(back)
		var row2 := PackedFloat64Array()
		row2.resize(t)
		# ⚠ PackedFloat64Array 为值类型：直接对 row2 索引累加（row2 为本函数局部变量，可写）
		if names.has(at):
			var i_at := 2 * names.find(at)
			row2[i_at] += g_k.x
			row2[i_at + 1] += g_k.y
		if names.has(front):
			var i_f := 2 * names.find(front)
			row2[i_f] += g_f.x
			row2[i_f + 1] += g_f.y
		if names.has(back):
			var i_b := 2 * names.find(back)
			row2[i_b] += -g_b.x
			row2[i_b + 1] += -g_b.y
		# l = β_obs − β_comp（弧度；观测给度）
		var b_comp := _az_rad(pk, pf2) - _az_rad(pk, pb)
		b_comp = _wrap_pi(b_comp)
		var b_obs := deg_to_rad(float(o2["value_deg"]))
		var wgt2 := 0.0
		if o2.has("w") and _finite_num(o2.get("w")) and float(o2["w"]) > 0.0:
			wgt2 = float(o2["w"])
		elif o2.has("sigma_s") and _finite_num(o2.get("sigma_s")) and float(o2["sigma_s"]) > 0.0:
			# 测角中误差以角秒为单位（测量口径，如 2″）→ 弧度
			var sig_rad_s := deg_to_rad(float(o2["sigma_s"]) / 3600.0)
			wgt2 = 1.0 / (sig_rad_s * sig_rad_s)
		elif o2.has("sigma_deg") and _finite_num(o2.get("sigma_deg")) and float(o2["sigma_deg"]) > 0.0:
			var sig_rad := deg_to_rad(float(o2["sigma_deg"]))
			wgt2 = 1.0 / (sig_rad * sig_rad)
		else:
			return {"error": "角度观测 %s 缺少正的 sigma_s（角秒）或 sigma_deg（度）或 w" % at}
		B.append(row2)
		l.append(b_obs - b_comp)
		wts.append(wgt2)
		kinds.append("angle")
		meta.append({"kind": "angle", "at": at, "back": back, "front": front})
	return {"error": "", "B": B, "l": l, "p": wts, "kinds": kinds, "meta": meta,
			"param_names": param_names, "approx": approx, "known": known}

# ---------- 内部 ----------

## 方位角 α(从 p 指向 q) 对端点坐标的解析偏导（x=东、y=北；α 从北顺时针）
## which=0 → 对 from 点 p；which=1 → 对 to 点 q。
## dα/∂Δx = Δy/S²，dα/∂Δy = −Δx/S²；Δ = q − p。
static func _alpha_grad(p: Array, q: Array, which: int) -> Vector2:
	var dx: float = q[0] - p[0]
	var dy: float = q[1] - p[1]
	var s2 := dx * dx + dy * dy
	if which == 0:
		return Vector2(-dy / s2, dx / s2)
	return Vector2(dy / s2, -dx / s2)

static func _az_rad(p: Array, q: Array) -> float:
	return atan2(q[0] - p[0], q[1] - p[1])

static func _wrap_pi(a: float) -> float:
	var d := fmod(a + PI, 2.0 * PI)
	if d < 0.0:
		d += 2.0 * PI
	return d - PI

static func _coord_of(nm: String, known: Dictionary, approx: Dictionary) -> Array:
	if known.has(nm):
		return known[nm]
	return approx[nm]

static func _obs_check(o_v, fields: Array, known: Dictionary, approx: Dictionary, names: Array, kind: String) -> String:
	if not (o_v is Dictionary):
		return "%s 观测条目须为对象" % kind
	var o: Dictionary = o_v
	for f: String in fields:
		if not o.has(f):
			return "%s 观测缺少字段 %s" % [kind, f]
	var pts := {"from": ["from"], "to": ["to"], "at": ["at"], "back": ["back"], "front": ["front"]}
	for f2: String in fields:
		if pts.has(f2):
			var nm := String(o[f2])
			if not known.has(nm) and not names.has(nm):
				return "%s 观测点名 %s 未在 known/approx 中定义" % [kind, nm]
	for fk in ["value", "value_deg", "sigma", "sigma_deg", "sigma_s", "w"]:
		if o.has(fk) and not _finite_num(o[fk]):
			return "%s 观测字段 %s 含非法数值" % [kind, fk]
	if fields.has("value") and not _finite_num(o["value"]):
		return "测边边长 value 含非法数值"
	if fields.has("value_deg") and not _finite_num(o["value_deg"]):
		return "角度 value_deg 含非法数值"
	return ""

## 按列缩放（Bᵀ·P：P 为对角权，缩放观测轴 = Bt 的列轴）
static func _scale_cols(Bt: Array, diag: PackedFloat64Array) -> Array:
	var out := []
	for i in Bt.size():
		var src: PackedFloat64Array = Bt[i]
		var row := PackedFloat64Array()
		row.resize(src.size())
		for j in src.size():
			row[j] = src[j] * diag[j]
		out.append(row)
	return out

static func _weighted_sum(v: PackedFloat64Array, diag: PackedFloat64Array) -> float:
	var s := 0.0
	for i in v.size():
		s += v[i] * v[i] * diag[i]
	return s

static func _scaled(v: PackedFloat64Array, f: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for x in v:
		out.append(x * f)
	return out

static func _abs_max(v: PackedFloat64Array) -> float:
	var m := 0.0
	for x in v:
		m = maxf(m, absf(x))
	return m

static func _finite_num(v) -> bool:
	if not (v is float or v is int):
		return false
	return is_finite(float(v))

static func _finite_xy(arr) -> bool:
	if not (arr is Array) or (arr as Array).size() != 2:
		return false
	return _finite_num(arr[0]) and _finite_num(arr[1])

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
