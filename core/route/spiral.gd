# core/route/spiral.gd —— GK-M7-2 缓和曲线（回旋线 / clothoid）B4
#
# 纯静态、零引擎依赖；全局 x=东、y=北、方位自北起顺时针；转向 dir：+1 右转 / −1 左转；
# 回旋线局部系 x' 沿起点切线、y' 指向弯曲一侧（右转曲线 y'>0）。
# 双路径互检（tests/route/test_spiral.gd）：A 布告式级数（x=l−l⁵/(40R²l0²)+…，y=l³/(6Rl0)−…）；
# B 数值积分 θ(t)=t²/(2Rl0) 的 Fresnel 型自适应辛普森。
# 本文件自包含（自带小型积分器）；D2 的广义线元积分器独立实现于 alignment_el.gd。
# 校验失败返回空容器 PackedFloat64Array() / {}，协议入口 ok=false + 中文 error。
class_name GKSpiral
extends RefCounted

## 布告式级数：自回旋线起点弧长 l（0<=l<=l0）处的切线坐标 [x, y]。
## y 指向曲线弯曲一侧（右转时取正后再由调用方按 dir 定向）。
## l=0 或 l0<=0 或 R<=0 返回空；l=0 返回 [0,0]。
static func point_series(l: float, r: float, l0: float) -> PackedFloat64Array:
	if not _valid3(l, r, l0) or l0 <= 0.0 or r <= 0.0 or l < 0.0:
		return PackedFloat64Array()
	var ls := minf(l, l0)
	var x: float = ls \
			- pow(ls, 5.0) / (40.0 * r * r * l0 * l0) \
			+ pow(ls, 9.0) / (3456.0 * pow(r, 4.0) * pow(l0, 4.0)) \
			- pow(ls, 13.0) / (599040.0 * pow(r, 6.0) * pow(l0, 6.0))
	var y: float = pow(ls, 3.0) / (6.0 * r * l0) \
			- pow(ls, 7.0) / (336.0 * pow(r, 3.0) * pow(l0, 3.0)) \
			+ pow(ls, 11.0) / (42240.0 * pow(r, 5.0) * pow(l0, 5.0)) \
			- pow(ls, 15.0) / (9676800.0 * pow(r, 7.0) * pow(l0, 7.0))
	return PackedFloat64Array([x, y])

## 切线角（相对起点切线，弧度）：β(l) = l²/(2Rl0)。右转为正。非法输入 NAN。
static func tangent_angle_rad(l: float, r: float, l0: float) -> float:
	if not _valid3(l, r, l0) or l0 <= 0.0 or r <= 0.0 or l < 0.0:
		return NAN
	var ls := minf(l, l0)
	return ls * ls / (2.0 * r * l0)

## 数值积分路径：理想回旋线（A²=R·l0，曲率 k=l/A² 线性）任意弧长 l 处
## 局部切线坐标 [x, y]（x 沿起点切线，y 指向弯曲一侧），自适应辛普森（float64）。
## l=0 返回 [0,0]；l0<=0 或 R<=0 返回空。
static func point_integral(l: float, r: float, l0: float) -> PackedFloat64Array:
	if not _valid3(l, r, l0) or l0 <= 0.0 or r <= 0.0 or l < 0.0:
		return PackedFloat64Array()
	var ls := minf(l, l0)
	if ls == 0.0:
		return PackedFloat64Array([0.0, 0.0])
	# β(t) = t²/(2Rl0)；x=∫cosβ dt, y=∫sinβ dt（弯曲一侧为正）
	var f := func(t: float) -> PackedFloat64Array:
		var b: float = t * t / (2.0 * r * l0)
		return PackedFloat64Array([cos(b), sin(b)])
	var v := _simpson2(f, 0.0, ls)
	return PackedFloat64Array([v[0], v[1]])

## B4 协议入口：缓和曲线任意弧长坐标。
## p = { r_m, l0_m, l_m, dir:int=+1右/−1左, start:{x_m,y_m,bearing_deg}? }
## value = { x_local_m, y_local_m, tangent_deg, beta_deg, l_m, r_m, l0_m }
##         给 start 时另附全局 { x_m, y_m, bearing_deg }。
## 失败 ok=false + 中文 error（R<=0、l0<=0、l<0 或 l>l0 等）。
static func coords(p: Dictionary) -> Dictionary:
	var r := _num(p.get("r_m", NAN))
	var l0 := _num(p.get("l0_m", NAN))
	var l := _num(p.get("l_m", NAN))
	var dir := 1 if not p.has("dir") else int(p["dir"])
	if is_nan(r) or is_nan(l0) or is_nan(l):
		return _err("输入缺失或非法：r_m、l0_m、l_m 均须为数字")
	if r <= 0.0:
		return _err("圆半径 R 必须大于 0（当前 %.4f m）" % r)
	if l0 <= 0.0:
		return _err("缓和曲线长 l0 必须大于 0（当前 %.4f m）" % l0)
	if l < 0.0:
		return _err("弧长 l 不能为负（当前 %.4f m）" % l)
	if l > l0 + 1e-9:
		return _err("弧长 l=%.4f m 超出缓和曲线全长 l0=%.4f m，请检查输入" % [l, l0])
	if dir != 1 and dir != -1:
		return _err("转向 dir 只能取 +1（右转）或 −1（左转）")
	var ser := point_series(l, r, l0)
	var itg := point_integral(l, r, l0)
	if ser.is_empty() or itg.is_empty():
		return _err("回旋线计算失败（数值溢出或输入非法）")
	var beta_rad := tangent_angle_rad(l, r, l0)
	var value := {
		"x_local_m": ser[0],                    # 局部 x 沿切线正向，恒为正
		"y_local_m": dir * ser[1],              # y 指向弯曲一侧：右转 +、左转 −
		"l_m": l, "r_m": r, "l0_m": l0,
		"tangent_deg": dir * rad_to_deg(beta_rad),  # 带转向符号的切线角
		"beta_deg": rad_to_deg(beta_rad),       # 切线角绝对值
	}
	# 双路径一致性（差异过大视为内部错误，正常应 <1e-6 m）
	var gap: float = sqrt(pow(ser[0] - itg[0], 2.0) + pow(ser[1] - itg[1], 2.0))
	value["dual_path_gap_m"] = gap
	var steps := [
		{
			"title": "1. 布告式级数坐标（公式链）",
			"formula": "x = l − l⁵/(40R²l0²) + l⁹/(3456R⁴l0⁴)；y = l³/(6Rl0) − l⁷/(336R³l0³) + l¹¹/(42240R⁵l0⁵)（各四项）",
			"substitution": "R=%.4f m，l0=%.4f m，l=%.4f m" % [r, l0, l],
			"result": "x=%.4f m，y=%.4f m（|y| 指向曲线一侧）" % [ser[0], ser[1]],
		},
		{
			"title": "2. Fresnel 型数值积分互检",
			"formula": "β(t)=t²/(2Rl0)；(x,y)=∫₀ˡ(cosβ, sinβ)dt（自适应辛普森）",
			"substitution": "对 [0, %.4f] 数值积分" % l,
			"result": "x=%.4f m，y=%.4f m，与级数互差 %.12f m" % [itg[0], itg[1], gap],
		},
		{
			"title": "3. 切线角",
			"formula": "β(l) = l²/(2Rl0)",
			"substitution": "β = %.4f²/(2×%.4f×%.4f) rad" % [l, r, l0],
			"result": "%.6f°" % rad_to_deg(beta_rad),
		},
	]
	if p.has("start"):
		var st: Dictionary = p["start"]
		var g := _to_global(st, ser[0], dir * ser[1], beta_rad, dir)
		if g.is_empty():
			return _err("start 需含 x_m、y_m、bearing_deg 三个数字字段")
		value["x_m"] = g[0]
		value["y_m"] = g[1]
		value["bearing_deg"] = rad_to_deg(g[2])
		steps.append({
			"title": "4. 全局坐标归化",
			"formula": "X = x0 + x'·sin(α) + y'·sin(α+dir·90°)；Y = y0 + x'·cos(α) + y'·cos(α+dir·90°)",
			"substitution": "起点(%s, %s)，切线方位 %s°" % [str(st.get("x_m")), str(st.get("y_m")), str(st.get("bearing_deg"))],
			"result": "X=%.4f m，Y=%.4f m，方位=%.6f°" % [g[0], g[1], rad_to_deg(g[2])],
		})
	return {"ok": true, "value": value, "steps": steps,
			"formula": "辐射螺旋线（回旋线）缓和曲线：曲率随弧长线性增长，A²=R·l0；y 正方向指向曲线弯曲一侧",
			"error": ""}

# ---------- 内部工具 ----------

static func _valid3(a: float, b: float, c: float) -> bool:
	return is_finite(a) and is_finite(b) and is_finite(c)

static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String:
		var t := String(v).strip_edges()
		if t.is_valid_float():
			return t.to_float()
	return NAN

## 局部切线坐标 → 全局。st={x_m(东), y_m(北), bearing_deg}，beta_rad 为切线相对转角，
## dir 为转向（+1 右转 / −1 左转）。
## 返回 [x_east, y_north, bearing_rad]；失败返回空。
static func _to_global(st: Dictionary, xl: float, yl: float, beta_rad: float, dir: int) -> PackedFloat64Array:
	var x0 := _num(st.get("x_m", NAN))
	var y0 := _num(st.get("y_m", NAN))
	var az := _num(st.get("bearing_deg", NAN))
	if is_nan(x0) or is_nan(y0) or is_nan(az):
		return PackedFloat64Array()
	var ds := 1.0 if dir >= 0 else -1.0
	var th := deg_to_rad(az)
	# 切线方向单位向量（东,北）：(sinθ, cosθ)；弯曲一侧 = 方位 θ+dir·90°
	var ax := sin(th)
	var ay := cos(th)
	var side := th + ds * PI / 2.0
	var bx := sin(side)
	var by := cos(side)
	var x: float = x0 + xl * ax + absf(yl) * bx
	var y: float = y0 + xl * ay + absf(yl) * by
	return PackedFloat64Array([x, y, th + ds * beta_rad])

## 自适应辛普森积分（双分量 PackedFloat64Array 被积函数；全程 float64，
## 不用 Vector2——其为 32 位浮点，测量级计算精度不足）
static func _simpson2(f: Callable, a: float, b: float, eps := 1e-12, depth := 50) -> PackedFloat64Array:
	if a == b:
		return PackedFloat64Array([0.0, 0.0])
	var fa: PackedFloat64Array = f.call(a)
	var fb: PackedFloat64Array = f.call(b)
	var fm: PackedFloat64Array = f.call((a + b) * 0.5)
	return _simpson2_rec(f, a, b, fa, fm, fb, eps, depth)

static func _simpson2_rec(f: Callable, a: float, b: float, fa: PackedFloat64Array, fm: PackedFloat64Array, fb: PackedFloat64Array, tol: float, depth: int) -> PackedFloat64Array:
	var m := (a + b) * 0.5
	var whole := PackedFloat64Array([(b - a) / 6.0 * (fa[0] + 4.0 * fm[0] + fb[0]), (b - a) / 6.0 * (fa[1] + 4.0 * fm[1] + fb[1])])
	var fl: PackedFloat64Array = f.call((a + m) * 0.5)
	var fr: PackedFloat64Array = f.call((m + b) * 0.5)
	var left := PackedFloat64Array([(m - a) / 6.0 * (fa[0] + 4.0 * fl[0] + fm[0]), (m - a) / 6.0 * (fa[1] + 4.0 * fl[1] + fm[1])])
	var right := PackedFloat64Array([(b - m) / 6.0 * (fm[0] + 4.0 * fr[0] + fb[0]), (b - m) / 6.0 * (fm[1] + 4.0 * fr[1] + fb[1])])
	var err := sqrt(pow(left[0] + right[0] - whole[0], 2.0) + pow(left[1] + right[1] - whole[1], 2.0))
	if depth <= 0 or err <= 15.0 * tol:
		return PackedFloat64Array([left[0] + right[0] + (left[0] + right[0] - whole[0]) / 15.0,
				left[1] + right[1] + (left[1] + right[1] - whole[1]) / 15.0])
	var lrec := _simpson2_rec(f, a, m, fa, fl, fm, tol * 0.5, depth - 1)
	var rrec := _simpson2_rec(f, m, b, fm, fr, fb, tol * 0.5, depth - 1)
	return PackedFloat64Array([lrec[0] + rrec[0], lrec[1] + rrec[1]])

## 协议失败结果（§5：ok=false 时 value 空、error 中文）
static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
