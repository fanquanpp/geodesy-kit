# core/adjustment/traverse.gd —— GK-M6-1 导线计算（C1 支导线 / C2 闭合导线 / C3 附合导线·Bowditch / C4 无定向导线）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M6 / §5 协议）：
#   - 坐标约定与 core/math/angles.gd 一致：x=东、y=北；方位角从北起顺时针 [0°,360°)；
#   - 角度约定：输入左角（十进制度），推算公式 α_{i+1} = α_i + β_左 − 180°（GKAngles.propagate_azimuth 同口径）；
#   - 平差口径：教材近似平差——角度闭合差反号平均分配 → 推算方位角 → 坐标闭合差按边长比例
#     反号分配（Bowditch 规则）。近似平差非严密平差，结果页/公式尾注须标注（精度诚实原则）；
#   - C2 闭合导线实现为"附合到自身"的特例（终点=起点、终边方位=起始方位），与 C3 共用核心；
#   - 全部静态函数、零引擎依赖（extends RefCounted）；输入非法返回 {"ok": false, "error": 中文}，
#     计算成功但超限返回 ok=true 且 value.ok_limit=false（§5 规则：超限是检核结论不是计算失败）。
class_name GKAdjustTraverse
extends RefCounted

## C1 支导线：起点 + 起始方位角 + 左角串 + 边长串 → 展点（无任何检核条件）
## p = {start:[x,y], az_start_deg, angles_deg:[...], sides_m:[...], start_name?, point_names?}
static func open_traverse(p: Dictionary) -> Dictionary:
	var bad := _check_chain_inputs(p, false)
	if bad != "":
		return _fail(bad)
	var angles := PackedFloat64Array(p["angles_deg"])
	var sides := PackedFloat64Array(p["sides_m"])
	var chain := _chain(p["start"], float(p["az_start_deg"]), angles, sides)
	# 支导线：每条边末端都是一个新点（无已知终点），n_inter = 边数
	var names := _point_names(p, sides.size(), true, false)
	var value := {}
	for i in chain.points.size():
		value["x_%s_m" % names[i]] = chain.points[i][0]
		value["y_%s_m" % names[i]] = chain.points[i][1]
	value["az_deg"] = chain.az
	var steps := [
		{
			"title": "1. 由起始方位推算各边方位角",
			"formula": "α_{i+1} = α_i + β_左 − 180°",
			"substitution": "α_起 = %s°，依次推算 %d 条边" % [_fmt(az_start_value(p)), sides.size()],
			"result": "方位角串见结果 az_deg",
		},
		{
			"title": "2. 坐标正算逐点展点",
			"formula": "Δx = D·sinα，Δy = D·cosα；x_{i+1} = x_i + Δx，y_{i+1} = y_i + Δy",
			"substitution": "边长 %s" % _fmt_vec(sides),
			"result": "各点坐标见结果",
		},
		{
			"title": "教学提示：支导线无检核条件",
			"formula": "支导线终点不附合于已知控制，无角度/坐标闭合差可检核",
			"substitution": "成果可靠性完全取决于观测质量，生产中仅用于低精度放样/图根",
			"result": "建议改用闭合/附合导线并做平差",
		},
	]
	return _ok(value, steps, "支导线展点（坐标正算，无平差检核）")

## C2 闭合导线平差：n 边闭合环，左角 n 个、边长 n 条，起终边方位相同
## p = {start:[x,y], az_start_deg, angles_deg:[n], sides_m:[n], start_name?, point_names?,
##      limit_fb_s? / limit_rel_k?（自输限差，可选）}
static func closed_traverse(p: Dictionary) -> Dictionary:
	var q := p.duplicate()
	q["end"] = [float(p["start"][0]), float(p["start"][1])]
	q["az_end_deg"] = float(p["az_start_deg"])
	q["end_name"] = String(p.get("start_name", "A"))  # 闭合环终点即起点
	return _connect_adjust(q, true, true)

## C3 附合导线平差（Bowditch）：两端附合于已知点与已知方位
## p = {start:[x,y], end:[x,y], az_start_deg, az_end_deg, angles_deg:[n], sides_m:[n+1],
##      start_name?, end_name?, point_names?, limit_fb_s?, limit_rel_k?}
static func connect_traverse(p: Dictionary) -> Dictionary:
	return _connect_adjust(p, false, false)

## C4 无定向导线：两端点已知但无已知方位角（假定起始方向 → 旋转闭合 → 比例分配）
## p = {start:[x,y], end:[x,y], angles_deg:[n], sides_m:[n+1], ...同上}
static func no_orient_traverse(p: Dictionary) -> Dictionary:
	var bad := _check_chain_inputs(p, false, false)
	if bad != "":
		return _fail(bad)
	if not p.has("end") or (p["end"] as Array).size() != 2:
		return _fail("缺少终点已知坐标 end:[x,y]")
	var endpt: Array = p["end"]
	if not _finite_xy(endpt):
		return _fail("终点坐标含非法数值（空/非数字/NaN）")
	var angles := PackedFloat64Array(p["angles_deg"])
	var sides := PackedFloat64Array(p["sides_m"])
	var start: Array = p["start"]
	# 1) 假定起始方位 α'1 = 0°，推算假定终点
	var prov := _chain(start, 0.0, angles, sides)
	var bpt: Array = prov.points[prov.points.size() - 1]
	var vec_abp := [bpt[0] - start[0], bpt[1] - start[1]]
	if absf(vec_abp[0]) < 1e-12 and absf(vec_abp[1]) < 1e-12:
		return _fail("假定方向下闭合边长度为零，无法旋转定向，请检查观测数据")
	var az_true := GKAngles.azimuth(float(p["end"][0]) - float(start[0]), float(p["end"][1]) - float(start[1]))
	var az_prov := GKAngles.azimuth(vec_abp[0], vec_abp[1])
	var delta := _wrap180(az_true - az_prov)
	# 2) 全部方位角旋转 δ 后重新推算
	var chain := _chain(start, delta, angles, sides)
	# 3) 坐标闭合差按边长比例分配（此时闭合差方向必沿 AB）
	var dEs: PackedFloat64Array = chain.dE
	var dNs: PackedFloat64Array = chain.dN
	var fx := _sum_pfa(dEs) - (float(endpt[0]) - float(start[0]))
	var fy := _sum_pfa(dNs) - (float(endpt[1]) - float(start[1]))
	var sum_d := _sum_pfa(sides)
	var names := _point_names(p, sides.size() - 1, true, true)
	var res := _distribute_and_build(chain, fx, fy, sides, sum_d, names, start,
			"无定向导线（假定方向+旋转定向+比例分配，近似平差）", delta)
	return res

# ---------- 内部实现 ----------

## C2/C3 共用核心：角度闭合差反号均分 → 方位角 → 坐标闭合差按边长比例分配
static func _connect_adjust(p: Dictionary, closed: bool, is_loop: bool) -> Dictionary:
	var bad := _check_chain_inputs(p, is_loop)
	if bad != "":
		return _fail(bad)
	if not p.has("end") or (p["end"] as Array).size() != 2:
		return _fail("缺少终点已知坐标 end:[x,y]")
	var endpt: Array = p["end"]
	if not _finite_xy(endpt):
		return _fail("终点坐标含非法数值（空/非数字/NaN）")
	if not p.has("az_end_deg") or is_nan(float(p.get("az_end_deg", NAN))):
		return _fail("缺少终止边已知方位角 az_end_deg")
	var start: Array = p["start"]
	var angles := PackedFloat64Array(p["angles_deg"])
	var sides := PackedFloat64Array(p["sides_m"])
	var az_start := float(p["az_start_deg"])
	var az_end := float(p["az_end_deg"])
	# 1) 角度闭合差：推算终边方位 − 已知终边方位
	var n_ang := angles.size()
	var az_calc := GKAngles.normalize_deg(az_start + _sum_pfa(angles) - 180.0 * n_ang)
	var f_beta := _wrap180(az_calc - az_end)
	var f_beta_s := f_beta * 3600.0
	# 2) 反号平均分配
	var corr := -f_beta / n_ang
	var adj := PackedFloat64Array()
	for a in angles:
		adj.append(a + corr)
	var chain := _chain(start, az_start, adj, sides)
	# 3) 坐标闭合差
	var target := [float(endpt[0]) - float(start[0]), float(endpt[1]) - float(start[1])]
	var fx: float = _sum_pfa(chain.dE) - float(target[0])
	var fy: float = _sum_pfa(chain.dN) - float(target[1])
	var sum_d := _sum_pfa(sides)
	var names := _point_names(p, sides.size() - 1, true, true)
	var title := "闭合导线平差（角度均分+边长比例分配，近似平差）" if closed else "附合导线平差（Bowditch：角度均分+边长比例分配，近似平差）"
	# 步骤编号：角度闭合差步骤占用 "1."，后续步骤从 2 起编
	var res := _distribute_and_build(chain, fx, fy, sides, sum_d, names, start, title, NAN, 1)
	if not bool(res.get("ok", false)):
		return res
	var value: Dictionary = res["value"]
	value["f_beta_s"] = f_beta_s
	value["f_beta_per_angle_s"] = corr * 3600.0
	# 限差检核（自输限差，可选；依据标注"用户输入限差"，未核读规范前不伪造标准值）
	var checks := PackedStringArray()
	var ok_limit := true
	var has_limit := false
	if p.has("limit_fb_s") and is_finite(float(p["limit_fb_s"])):
		has_limit = true
		var lim := absf(float(p["limit_fb_s"]))
		value["limit_fb_s"] = lim
		value["basis"] = "用户输入限差（未核读 GB 50026 等规范限差表，data/tolerance.json 为占位）"
		checks.append("角度闭合差 %s″，限差 ±%s″" % [_fmt(f_beta_s), _fmt(lim)])
		if absf(f_beta_s) > lim:
			ok_limit = false
			checks.append("角度闭合差超限")
	if p.has("limit_rel_k") and is_finite(float(p["limit_rel_k"])) and float(p["limit_rel_k"]) > 0.0:
		has_limit = true
		var lrel := float(p["limit_rel_k"])
		value["limit_rel_k"] = lrel
		var rel_k: float = value.get("rel_k", INF)
		checks.append("相对闭合差 1/%s，限差 1/%s" % [_fmt(rel_k), _fmt(lrel)])
		if rel_k < lrel:
			ok_limit = false
			checks.append("相对闭合差超限")
	if has_limit:
		value["ok_limit"] = ok_limit
		if not checks.is_empty():
			value["basis"] = "用户输入限差（未核读 GB 50026 等规范限差表，data/tolerance.json 为占位）"
	res["value"] = value
	# 步骤补角度闭合差明细
	var steps: Array = res["steps"]
	var st_fb := {
		"title": "1. 角度闭合差及改正",
		"formula": "fβ = α_起 + Σβ_左 − n·180° − α_终；改正 vβ = −fβ/n（各角均分）",
		"substitution": "fβ = %s° = %s″；vβ = %s″" % [_fmt(f_beta), _fmt(f_beta_s), _fmt(corr * 3600.0)],
		"result": "改正后方位角闭合于已知终边",
	}
	steps.insert(0, st_fb)
	return res

## 通用展点链：返回 {points:[[x,y]...], az:PackedFloat64Array, dE, dN}
static func _chain(start: Array, az_start_deg: float, angles: PackedFloat64Array, sides: PackedFloat64Array) -> Dictionary:
	var pts := []
	var azs := PackedFloat64Array()
	var dEs := PackedFloat64Array()
	var dNs := PackedFloat64Array()
	var x := float(start[0])
	var y := float(start[1])
	pts.append([x, y])
	var az := az_start_deg
	azs.append(az)
	for i in sides.size():
		var dE := sides[i] * sin(deg_to_rad(az))
		var dN := sides[i] * cos(deg_to_rad(az))
		dEs.append(dE)
		dNs.append(dN)
		x += dE
		y += dN
		pts.append([x, y])
		if i < angles.size():
			az = GKAngles.normalize_deg(az + angles[i] - 180.0)
			azs.append(az)
	return {"points": pts, "az": azs, "dE": dEs, "dN": dNs}

## 比例分配并组装 §5 结果（traverse 内部）；step_offset 为已有前置步骤数（编号衔接）
static func _distribute_and_build(chain: Dictionary, fx: float, fy: float,
		sides: PackedFloat64Array, sum_d: float, names: Array, start: Array,
		title: String, rotation_deg: float, step_offset := 0) -> Dictionary:
	var dEs: PackedFloat64Array = chain.dE
	var dNs: PackedFloat64Array = chain.dN
	var vxs := PackedFloat64Array()
	var vys := PackedFloat64Array()
	for i in sides.size():
		vxs.append(-fx * sides[i] / sum_d)
		vys.append(-fy * sides[i] / sum_d)
	var f := sqrt(fx * fx + fy * fy)
	var rel_k := INF if f <= 0.0 else sum_d / f
	# 平差后坐标
	var value := {}
	var px := float(start[0])
	var py := float(start[1])
	value["x_%s_m" % names[0]] = px
	value["y_%s_m" % names[0]] = py
	for i in sides.size():
		px += dEs[i] + vxs[i]
		py += dNs[i] + vys[i]
		value["x_%s_m" % names[i + 1]] = px
		value["y_%s_m" % names[i + 1]] = py
	value["fx_m"] = fx
	value["fy_m"] = fy
	value["f_m"] = f
	value["sum_d_m"] = sum_d
	value["rel_k"] = rel_k
	var rel_text := GKStatistics.relative_fraction_text(f / sum_d)
	if rel_text == "∞":
		rel_text = "1/∞（坐标闭合差为零）"
	value["rel_text"] = rel_text
	if is_finite(rotation_deg):
		value["rotation_deg"] = rotation_deg
	var steps := []
	if is_finite(rotation_deg):
		steps.append({
			"title": "1. 假定方向与旋转角",
			"formula": "δ = α_AB(已知) − α_AB'(假定 α'1=0° 推算)",
			"substitution": "旋转角 δ = %s°" % _fmt(rotation_deg),
			"result": "全部假定方位角加 δ 后重新推算",
		})
	steps.append({
		"title": "%d. 坐标闭合差" % (steps.size() + 1),
		"formula": "fx = ΣΔx − (x_终 − x_起)；fy = ΣΔy − (y_终 − y_起)",
		"substitution": "fx = %s m，fy = %s m" % [_fmt(fx), _fmt(fy)],
		"result": "f = %s m，ΣD = %s m，相对闭合差 %s" % [_fmt(f), _fmt(sum_d), rel_text],
	})
	steps.append({
		"title": "%d. 按边长比例反号分配（Bowditch）" % (steps.size() + 1),
		"formula": "vΔx_i = −fx·D_i/ΣD，vΔy_i = −fy·D_i/ΣD",
		"substitution": "首边改正 vΔx = %s m，vΔy = %s m" % [_fmt(vxs[0]), _fmt(vys[0])],
		"result": "改正后坐标增量终点附合于已知点",
	})
	steps.append({
		"title": "%d. 平差后坐标" % (steps.size() + 1),
		"formula": "x_i = x_{i-1} + Δx_i + vΔx_i；y_i 同理",
		"substitution": "逐点累加",
		"result": "各点平差后坐标见结果",
	})
	steps.append({
		"title": "精度声明",
		"formula": "本结果为近似平差（非严密平差）",
		"substitution": "角度闭合差平均分配未考虑观测量权重；严密平差请使用导线网间接平差（C5）",
		"result": "教学演示用途",
	})
	return _ok(value, steps, title)

# ---------- 输入校验与工具 ----------

static func _check_chain_inputs(p: Dictionary, is_loop: bool, need_az := true) -> String:
	if not p.has("start") or (p["start"] as Array).size() != 2:
		return "缺少起点坐标 start:[x,y]"
	if not _finite_xy(p["start"]):
		return "起点坐标含非法数值（空/非数字/NaN）"
	# 无定向导线（C4）无已知方位角：need_az=false 时不要求 az_start_deg
	if need_az and (not p.has("az_start_deg") or is_nan(float(p.get("az_start_deg", NAN)))):
		return "缺少起始方位角 az_start_deg（十进制度）"
	if not p.has("angles_deg") or not (p["angles_deg"] is Array) or (p["angles_deg"] as Array).size() < 1:
		return "缺少转折角 angles_deg（至少 1 个左角，十进制度）"
	if not p.has("sides_m") or not (p["sides_m"] is Array) or (p["sides_m"] as Array).size() < 2:
		return "缺少边长 sides_m（至少 2 条边）"
	var angles: Array = p["angles_deg"]
	var sides: Array = p["sides_m"]
	if is_loop:
		if sides.size() != angles.size():
			return "闭合导线的转折角个数应等于边长个数（n 边形 n 角 n 边）"
	else:
		if sides.size() != angles.size() + 1:
			return "边长个数应为 转折角个数+1（附合/无定向）；闭合导线请用 closed_traverse（角数=边数）"
	for a in angles:
		if not _finite_num(a):
			return "转折角含非法数值（空/非数字/NaN）"
	for d in sides:
		if not _finite_num(d):
			return "边长含非法数值（空/非数字/NaN）"
		if float(d) <= 0.0:
			return "边长必须为正数"
	return ""

static func _point_names(p: Dictionary, n_inter: int, with_start: bool, with_end: bool) -> Array:
	var names: Array = []
	var start_name := String(p.get("start_name", "A"))
	var end_name := String(p.get("end_name", "B"))
	var inter: Array = p.get("point_names", [])
	if with_start:
		names.append(start_name)
	for i in n_inter:
		if i < inter.size() and String(inter[i]) != "":
			names.append(String(inter[i]))
		else:
			names.append("P%d" % (i + 1))
	if with_end:
		names.append(end_name)
	return names

static func az_start_value(p: Dictionary) -> float:
	return float(p.get("az_start_deg", NAN))

static func _finite_xy(arr) -> bool:
	if not (arr is Array) or (arr as Array).size() != 2:
		return false
	return _finite_num(arr[0]) and _finite_num(arr[1])

static func _finite_num(v) -> bool:
	if not (v is float or v is int):
		return false
	return is_finite(float(v))

static func _sum_pfa(v: PackedFloat64Array) -> float:
	var s := 0.0
	for x in v:
		s += x
	return s

static func _wrap180(deg: float) -> float:
	var d := GKAngles.normalize_deg(deg)
	if d > 180.0:
		d -= 360.0
	return d

static func _fmt(v: float) -> String:
	if not is_finite(v):
		if v > 0.0:
			return "+∞"
		elif v < 0.0:
			return "−∞"
		return "NaN"
	return "%.6f" % v

static func _fmt_vec(v: PackedFloat64Array) -> String:
	var parts := PackedStringArray()
	for x in v:
		parts.append(_fmt(x))
	return "、".join(parts)

## §5 协议成功壳
static func _ok(value: Dictionary, steps: Array, formula: String) -> Dictionary:
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## §5 协议失败壳（value 必空、error 必中文）
static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}
