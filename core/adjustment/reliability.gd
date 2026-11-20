# core/adjustment/reliability.gd —— GK-M6-6 粗差探测与可靠性（C10：数据探测法·学生化残差/多余观测分量）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M6 / §5 协议）：
#   - 数据探测法（Baarda data snooping）：
#       改正数协因数 q_v = Qll − B·Qxx·Bᵀ，其中 Qll = P⁻¹（对角权）；
#       多余观测分量 r_i = (Qvv·P)_ii = p_i·q_v_i，满足 Σr_i = n − t（可靠性总量）；
#       学生化残差 w_i = v_i / (σ0·√q_v_i)，|w| > k 判定粗差（默认 k_warn=2 可疑、k_gross=3 粗差，
#       教学口径；严格分布临界值依自由度而异，此处不做分布查表）；
#   - 只需 Qvv 的对角元：q_v_i = 1/p_i − b_i·Qxx·b_iᵀ（O(n·t²)，无需组全 n×n 阵）；
#   - 输入 B/v/Qxx/σ0 来自间接平差（C5 network.gd 的返回扩展键 qxx 可直接传入）；
#   - 全部静态函数、零引擎依赖；输入非法返回 {"ok":false,"error":中文}。
class_name GKAdjustReliability
extends RefCounted

## C10 数据探测法粗差定位
## p = {B: Array of PackedFloat64Array（设计矩阵）, v: PackedFloat64Array（改正数）,
##      p_w: PackedFloat64Array（对角权）, qxx: Array（法方程逆 N⁻¹, t×t）,
##      sigma0, k_warn? = 2.0, k_gross? = 3.0}
## value: {r, q_v, sigma_v, w, flags, sum_r, n, t, gross_count, ...}（数组均与观测同序）
static func data_snooping(p: Dictionary) -> Dictionary:
	var B: Variant = p.get("B")
	var v_v: Variant = p.get("v")
	var pw_v: Variant = p.get("p_w")
	var qxx: Variant = p.get("qxx")
	if not (B is Array) or (B as Array).is_empty():
		return _fail("缺少设计矩阵 B（间接平差误差方程系数，Array of PackedFloat64Array）")
	if not (v_v is PackedFloat64Array):
		return _fail("缺少改正数 v（PackedFloat64Array，与观测同序）")
	if not (pw_v is PackedFloat64Array):
		return _fail("缺少对角权 p_w（PackedFloat64Array）")
	if not (qxx is Array) or (qxx as Array).is_empty():
		return _fail("缺少协因数阵 qxx（法方程逆 N⁻¹，t×t）")
	var Bm: Array = B
	var v: PackedFloat64Array = v_v
	var pw: PackedFloat64Array = pw_v
	var n := Bm.size()
	var t: int = (qxx as Array).size()
	if v.size() != n or pw.size() != n:
		return _fail("v/p_w 长度（%d/%d）与 B 行数（%d）不一致" % [v.size(), pw.size(), n])
	if t != (Bm[0] as PackedFloat64Array).size():
		return _fail("qxx 阶数（%d）与 B 列数不一致" % t)
	for i in n:
		if not is_finite(v[i]) or not is_finite(pw[i]) or pw[i] <= 0.0:
			return _fail("v/p_w 含非法数值或非正权（观测 %d）" % (i + 1))
	var sigma0 := float(p.get("sigma0", NAN))
	if not is_finite(sigma0) or sigma0 <= 0.0:
		return _fail("缺少正的 sigma0（单位权中误差）")
	var k_warn := 2.0
	var k_gross := 3.0
	if p.has("k_warn") and is_finite(float(p["k_warn"])) and float(p["k_warn"]) > 0.0:
		k_warn = float(p["k_warn"])
	if p.has("k_gross") and is_finite(float(p["k_gross"])) and float(p["k_gross"]) > 0.0:
		k_gross = float(p["k_gross"])
	# q_v_i = 1/p_i − b_i·Qxx·b_iᵀ（只取对角）
	var q_v := PackedFloat64Array()
	var r := PackedFloat64Array()
	var w := PackedFloat64Array()
	var flags := PackedStringArray()
	var sum_r := 0.0
	var gross_idx := []
	var warn_idx := []
	var arg_max := 0
	var max_abs_w := 0.0
	for i in n:
		var bi: PackedFloat64Array = Bm[i]
		var s := 0.0
		for j in t:
			var qrow: PackedFloat64Array = qxx[j]
			var sj := 0.0
			for k in t:
				sj += qrow[k] * bi[k]
			s += bi[j] * sj
		var qvi := 1.0 / pw[i] - s
		if qvi <= 0.0:
			# 数值上可能出现的微负（冗余度≈0 的必要观测）：夹到 0 并在步骤中说明
			qvi = 0.0
		var ri := pw[i] * qvi
		var wi := 0.0
		if qvi > 0.0:
			wi = v[i] / (sigma0 * sqrt(qvi))
		q_v.append(qvi)
		r.append(ri)
		w.append(wi)
		sum_r += ri
		if absf(wi) > max_abs_w:
			max_abs_w = absf(wi)
			arg_max = i
		if qvi <= 0.0:
			flags.append("必要观测（冗余度≈0，不可检粗差）")
		elif absf(wi) > k_gross:
			flags.append("粗差")
			gross_idx.append(i)
		elif absf(wi) > k_warn:
			flags.append("可疑")
			warn_idx.append(i)
		else:
			flags.append("正常")
	var value := {
		"r": r,
		"q_v": q_v,
		"sigma_v": _scaled(sqrt_all(q_v), sigma0),
		"w": w,
		"flags": flags,
		"sum_r": sum_r,
		"n_minus_t": n - t,
		"n": n,
		"t": t,
		"k_warn": k_warn,
		"k_gross": k_gross,
		"arg_max_abs_w": arg_max,
		"max_abs_w": max_abs_w,
		"gross_indices": gross_idx,
		"warn_indices": warn_idx,
	}
	var steps := [
		{
			"title": "1. 改正数协因数对角元",
			"formula": "q_v_i = 1/p_i − b_i·Qxx·b_iᵀ（Qvv = Qll − B·Qxx·Bᵀ）",
			"substitution": "n = %d 个观测，t = %d 个参数" % [n, t],
			"result": "多余观测分量 r_i = p_i·q_v_i ∈ [0,1]",
		},
		{
			"title": "2. 可靠性总量检核",
			"formula": "Σr_i = n − t",
			"substitution": "Σr = %s，n − t = %d" % [_fmt(sum_r), n - t],
			"result": ("一致" if absf(sum_r - (n - t)) < 1e-6 * maxf(1.0, absf(sum_r)) else "数值上不一致（qxx 或权输入有误，请核查）"),
		},
		{
			"title": "3. 学生化残差与粗差判定",
			"formula": "w_i = v_i/(σ0·√q_v_i)；|w| > %s 可疑、> %s 判粗差（教学口径）" % [_fmt(k_warn), _fmt(k_gross)],
			"substitution": "最大 |w| = %s（观测 %d）" % [_fmt(max_abs_w), arg_max + 1],
			"result": "粗差 %d 处、可疑 %d 处" % [gross_idx.size(), warn_idx.size()],
		},
	]
	return _ok(value, steps, "数据探测法可靠性分析（学生化残差 w_i / 多余观测分量 r_i）")

## C10 内在可靠性界限（可发现粗差最小值下界，教学公式）
## g_i = σ_i·√(λ0/k_i) 形式的简化教学版：返回可发现粗差下界倍数 √(1/r_i)（k_warn 口径另计）
static func detectability(r_i: float) -> Dictionary:
	if not is_finite(r_i) or r_i <= 0.0 or r_i > 1.0 + 1e-9:
		return _fail("多余观测分量 r_i 应在 (0, 1] 内")
	var factor := 1.0 / sqrt(r_i)
	return _ok({"min_detect_factor": factor}, [
		{
			"title": "可发现粗差下界倍数（教学近似）",
			"formula": "∇0(g_i) ≈ σ_i·k临界/√r_i（此处输出 1/√r_i 因子）",
			"substitution": "r_i = %s" % _fmt(r_i),
			"result": "1/√r_i = %s（越大越难发现该观测的粗差）" % _fmt(factor),
		},
	], "观测内在可靠性（冗余度越小结越难检出粗差）")

# ---------- 内部 ----------

static func sqrt_all(v: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for x in v:
		out.append(sqrt(maxf(x, 0.0)))
	return out

static func _scaled(v: PackedFloat64Array, f: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for x in v:
		out.append(x * f)
	return out

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
