# core/cogo/intersections.gd —— GK-M5：交会定点（B1 前方/侧方/后方 + B2 方位-方位/方位-距离/距离-距离）
#
# 纯静态、零引擎依赖；坐标/方位约定同 cogo.gd（x=东、y=北、北起顺时针）。
# 侧别：side=+1 为射线/基线前进方向右侧（顺时针 90°），−1 为左侧。
# 后方交会用「两定位圆求交」解析法：∠APB=α 的轨迹是过 A、B 半径 R=AB/(2sinα) 的圆，
# 4 种组合交点剔除 B 后按角度+方向检核选解；两圆重合 ⟺ 危险圆（四点共圆），无解并给中文警告。
# 交会角 γ<15°（或 >165°）输出「精度较弱」提示（仍给结果，不判失败）；统一返回 §5 协议。
class_name GKIntersections
extends RefCounted

const WEAK_ANGLE_DEG := 15.0  # 交会角下限：小于该值提示图形强度弱

# ---------- 纯计算原语（返回 {} / 空 solutions 表示无解或不合法） ----------

## 两方位线交点（方位-方位）。返回 {x, y, t1, t2, az1_deg, az2_deg}；平行/重合 → {}。
static func ray_ray(x1: float, y1: float, az1: float, x2: float, y2: float, az2: float) -> Dictionary:
	if not (is_finite(x1) and is_finite(y1) and is_finite(az1)
			and is_finite(x2) and is_finite(y2) and is_finite(az2)):
		return {}
	var a1 := deg_to_rad(az1)
	var a2 := deg_to_rad(az2)
	var u1x := sin(a1)
	var u1y := cos(a1)
	var u2x := sin(a2)
	var u2y := cos(a2)
	var det := u1x * (-u2y) - (-u2x) * u1y
	if absf(det) < 1e-12:
		return {}
	var rx := x2 - x1
	var ry := y2 - y1
	var t1 := (-rx * u2y + u2x * ry) / det
	var t2 := (u1x * ry - u1y * rx) / det
	return {
		"x": x1 + t1 * u1x, "y": y1 + t1 * u1y,
		"t1": t1, "t2": t2,
		"az1_deg": GKAngles.normalize_deg(az1), "az2_deg": GKAngles.normalize_deg(az2),
	}

## 两圆（距离-距离）交点。side：+1=基线 A→B 右侧，−1=左侧，0=相切（唯一解）。
## 返回 {solutions:[{x,y,side}], d_ab, foot_x, foot_y, a, h}；无实交点 → {}。
static func circle_circle(x1: float, y1: float, d_a: float, x2: float, y2: float, d_b: float) -> Dictionary:
	if not (is_finite(x1) and is_finite(y1) and is_finite(d_a)
			and is_finite(x2) and is_finite(y2) and is_finite(d_b)):
		return {}
	if d_a <= 0.0 or d_b <= 0.0:
		return {}
	var dx := x2 - x1
	var dy := y2 - y1
	var d := sqrt(dx * dx + dy * dy)
	if d < 1e-12:
		return {}  # 两圆同心
	# 外离 / 内含（留 1e-9 相对容差防浮点毛刺）
	if d > d_a + d_b + 1e-9 * maxf(d_a, d_b):
		return {}
	if d < absf(d_a - d_b) - 1e-9 * maxf(d_a, d_b):
		return {}
	var a := (d_a * d_a - d_b * d_b + d * d) / (2.0 * d)
	var h2 := d_a * d_a - a * a
	var h := sqrt(maxf(h2, 0.0))
	var ux := dx / d
	var uy := dy / d
	var mx := x1 + a * ux
	var my := y1 + a * uy
	var solutions := []
	if h2 <= 1e-12 * d_a * d_a:
		solutions.append({"x": mx, "y": my, "side": 0})  # 相切：双解退化为切点
	else:
		# 右法线（前进方向顺时针转 90°）= (uy, −ux)
		solutions.append({"x": mx + h * uy, "y": my - h * ux, "side": 1})
		solutions.append({"x": mx - h * uy, "y": my + h * ux, "side": -1})
	return {
		"solutions": solutions,
		"d_ab": d, "foot_x": mx, "foot_y": my, "a": a, "h": h,
	}

## 方位线与圆（方位-距离）交点。返回 {solutions:[{x,y,t,branch}], t 判别式解}；
## branch："near"/"far"。无实交点 → {}。t 为沿方位线自 A 起算的距离。
static func ray_circle(x1: float, y1: float, az: float, x2: float, y2: float, d_b: float) -> Dictionary:
	if not (is_finite(x1) and is_finite(y1) and is_finite(az)
			and is_finite(x2) and is_finite(y2) and is_finite(d_b)):
		return {}
	if d_b <= 0.0:
		return {}
	var ar := deg_to_rad(az)
	var ux := sin(ar)
	var uy := cos(ar)
	var wx := x2 - x1
	var wy := y2 - y1
	var b := wx * ux + wy * uy          # 圆心在射线方向上的投影
	var c := wx * wx + wy * wy - d_b * d_b
	var disc := b * b - c
	if disc < -1e-9 * maxf(d_b * d_b, 1.0):
		return {}  # 射线与圆无实交点
	var sq := sqrt(maxf(disc, 0.0))
	var solutions := []
	var t_near := b - sq
	var t_far := b + sq
	if t_near >= 0.0:
		solutions.append({"x": x1 + t_near * ux, "y": y1 + t_near * uy, "t": t_near, "branch": "near"})
	if sq > 1e-12 * maxf(absf(b), 1.0) and t_far >= 0.0:
		solutions.append({"x": x1 + t_far * ux, "y": y1 + t_far * uy, "t": t_far, "branch": "far"})
	if solutions.is_empty():
		return {}  # 交点位于射线反方向
	return {"solutions": solutions, "sq": sq, "t_near": t_near, "t_far": t_far}

## 角度式前方交会（β1 = ∠BAP 在 A 点、β2 = ∠ABP 在 B 点，均为三角形内角正值）。
## side：+1 交点在 A→B 右侧、−1 左侧。返回 {x, y, az_ap_deg, az_bp_deg, ap, bp, gamma_deg}。
static func forward_by_angles(x1: float, y1: float, x2: float, y2: float,
		beta1: float, beta2: float, side: int) -> Dictionary:
	if not (is_finite(x1) and is_finite(y1) and is_finite(x2) and is_finite(y2)
			and is_finite(beta1) and is_finite(beta2)):
		return {}
	if beta1 <= 0.0 or beta2 <= 0.0:
		return {}
	var gamma := 180.0 - beta1 - beta2
	if gamma <= 0.0:
		return {}  # 三角形内角和约束
	var az_ab := GKAngles.azimuth(x2 - x1, y2 - y1)
	var az_ba := GKAngles.normalize_deg(az_ab + 180.0)
	var s := float(side)
	var az_ap := GKAngles.normalize_deg(az_ab + s * beta1)
	var az_bp := GKAngles.normalize_deg(az_ba - s * beta2)
	var r := ray_ray(x1, y1, az_ap, x2, y2, az_bp)
	if r.is_empty():
		return {}
	var px: float = r["x"]
	var py: float = r["y"]
	var ra := inv_len(x1, y1, px, py)
	var rb := inv_len(x2, y2, px, py)
	return {
		"x": px, "y": py,
		"az_ap_deg": az_ap, "az_bp_deg": az_bp,
		"ap": ra, "bp": rb,
		"gamma_deg": gamma,
	}

## 侧方交会：β_A = ∠BAP 在已知点 A 观测、γ = ∠APB 在待定点 P 观测（均为正值）。
## B 点内角由内角和推出 β_B = 180° − β_A − γ，退化（≤0）→ {}。
static func side_intersection(x1: float, y1: float, x2: float, y2: float,
		beta_a: float, gamma: float, side: int) -> Dictionary:
	if not (is_finite(beta_a) and is_finite(gamma)):
		return {}
	if beta_a <= 0.0 or gamma <= 0.0 or gamma >= 180.0:
		return {}
	var beta_b := 180.0 - beta_a - gamma
	if beta_b <= 0.0:
		return {}
	return forward_by_angles(x1, y1, x2, y2, beta_a, beta_b, side)

## 后方交会（Collins 定位圆法）。A、B、C 已知点，α = ∠APB、β = ∠BPC（顺时针观测值）。
## 返回 {x, y, pa, pb, pc, gamma_ab, gamma_bc}。
## 危险圆（两定位圆重合）→ {"danger": "danger_circle"}；无解/多解 → {"danger": 原因文字}。
static func resection(x1: float, y1: float, x2: float, y2: float, x3: float, y3: float,
		alpha: float, beta: float) -> Dictionary:
	if not (is_finite(x1) and is_finite(y1) and is_finite(x2) and is_finite(y2)
			and is_finite(x3) and is_finite(y3) and is_finite(alpha) and is_finite(beta)):
		return {"danger": "输入存在非数值"}
	if alpha <= 1e-6 or alpha >= 180.0 - 1e-6 or beta <= 1e-6 or beta >= 180.0 - 1e-6:
		# 观测角即圆周角：α≥180° 意味着 A、B、P 已确定共圆（圆周角 = 弦所对角 ≤180°），
		# 先给危险圆口径再谈区间，避免对共圆配置误报「区间」错误
		if (alpha >= 180.0 - 1e-6 or beta >= 180.0 - 1e-6) 				and not (alpha <= 1e-6 or beta <= 1e-6):
			return {"danger": "danger_circle"}
		return {"danger": "观测角须在 (0°, 180°) 开区间内且不过小"}
	# 已知点三角形有效性：A、B、C 不得共线（叉积相对面积检核）
	var abx := x2 - x1
	var aby := y2 - y1
	var acx := x3 - x1
	var acy := y3 - y1
	var cross := abx * acy - aby * acx
	var scale2 := maxf(abx * abx + aby * aby, acx * acx + acy * acy)
	if absf(cross) < 1e-9 * maxf(scale2, 1.0):
		return {"danger": "三个已知点共线，后方交会无解"}
	var len_ab := sqrt(abx * abx + aby * aby)
	var bcx := x3 - x2
	var bcy := y3 - y2
	var len_bc := sqrt(bcx * bcx + bcy * bcy)
	if len_ab < 1e-12 or len_bc < 1e-12:
		return {"danger": "已知点坐标重复"}
	var ar := deg_to_rad(alpha)
	var br := deg_to_rad(beta)
	var r1 := len_ab / (2.0 * sin(ar))
	var r2 := len_bc / (2.0 * sin(br))
	var off1 := (len_ab / 2.0) / tan(ar)   # (AB/2)·cot α
	var off2 := (len_bc / 2.0) / tan(br)   # (BC/2)·cot β
	var m1x := (x1 + x2) / 2.0
	var m1y := (y1 + y2) / 2.0
	var m2x := (x2 + x3) / 2.0
	var m2y := (y2 + y3) / 2.0
	# 左法线：前进方向逆时针转 90° = (−uy, ux)；两侧各取一圆
	var n1x := -aby / len_ab
	var n1y := abx / len_ab
	var n2x := -bcy / len_bc
	var n2y := bcx / len_bc
	var candidates := []
	for s1: int in [1, -1]:
		var o1x := m1x + s1 * off1 * n1x
		var o1y := m1y + s1 * off1 * n1y
		for s2: int in [1, -1]:
			var o2x := m2x + s2 * off2 * n2x
			var o2y := m2y + s2 * off2 * n2y
			# 危险圆判据：两定位圆重合 ⟺ A、B、C、P 四点共圆，解不定
			var d_orad := sqrt((o1x - o2x) * (o1x - o2x) + (o1y - o2y) * (o1y - o2y))
			if d_orad < 1e-9 * maxf(r1, r2) and absf(r1 - r2) < 1e-9 * maxf(r1, r2):
				return {"danger": "danger_circle"}
			var its := circle_intersect(o1x, o1y, r1, o2x, o2y, r2)
			for c: Dictionary in its:
				var dbx: float = c["x"] - x2
				var dby: float = c["y"] - y2
				if dbx * dbx + dby * dby < 1e-12 * maxf(len_ab * len_ab, 1.0):
					continue  # 剔除已知点 B 自身
				candidates.append(c)
	# 角度与方向检核：顺时针方位差 = 观测角
	var valid := []
	for c: Dictionary in candidates:
		var px: float = c["x"]
		var py: float = c["y"]
		if absf(angle_at(px, py, x1, y1, x2, y2) - alpha) > 1e-4:
			continue
		if absf(angle_at(px, py, x2, y2, x3, y3) - beta) > 1e-4:
			continue
		var d_pa := GKAngles.azimuth(x1 - px, y1 - py)
		var d_pb := GKAngles.azimuth(x2 - px, y2 - py)
		var d_pc := GKAngles.azimuth(x3 - px, y3 - py)
		var cw1 := GKAngles.normalize_deg(d_pb - d_pa)
		var cw2 := GKAngles.normalize_deg(d_pc - d_pb)
		if absf(cw1 - alpha) > 1e-3 or absf(cw2 - beta) > 1e-3:
			continue
		valid.append(c)
	if valid.size() == 0:
		return {"danger": "无几何解：观测角与已知点图形不匹配（请检查角度与点名对应关系、观测方向顺序）"}
	if valid.size() > 1:
		return {"danger": "观测条件不足，存在多个几何解（请在已知点上增加观测方向或第四点）"}
	var sol: Dictionary = valid[0]
	var px: float = sol["x"]
	var py: float = sol["y"]
	# 兜底危险圆复核：P 与 A、B、C 的外接圆比较
	var circ := circumcircle_3p(x1, y1, x2, y2, x3, y3)
	if not circ.is_empty():
		var dpx: float = px - circ["cx"]
		var dpy: float = py - circ["cy"]
		var rr: float = circ["r"]
		if sqrt(dpx * dpx + dpy * dpy) < 1e-6 * maxf(rr, 1.0):
			return {"danger": "danger_circle"}
	var pa := inv_len(x1, y1, px, py)
	var pb := inv_len(x2, y2, px, py)
	var pc := inv_len(x3, y3, px, py)
	return {
		"x": px, "y": py, "pa": pa, "pb": pb, "pc": pc,
		"gamma_ab": angle_at(px, py, x1, y1, x2, y2),
		"gamma_bc": angle_at(px, py, x2, y2, x3, y3),
	}

## 点 P 处对 A、B 的张角 ∠APB（[0°, 180°]）
static func angle_at(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var vax := ax - px
	var vay := ay - py
	var vbx := bx - px
	var vby := by - py
	var la := sqrt(vax * vax + vay * vay)
	var lb := sqrt(vbx * vbx + vby * vby)
	if la < 1e-15 or lb < 1e-15:
		return 0.0
	var cs := (vax * vbx + vay * vby) / (la * lb)
	cs = clampf(cs, -1.0, 1.0)
	return rad_to_deg(acos(cs))

# ---------- §5 协议入口（计算器场景调用） ----------

## B1/B2 方位-方位交会（方位式前方交会）。输入：{x_a_m, y_a_m, az1_deg, x_b_m, y_b_m, az2_deg}。
static func b1_azimuth(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x1 := _num(p, "x_a_m", "已知点 A x", bad)
	var y1 := _num(p, "y_a_m", "已知点 A y", bad)
	var az1 := _ang(p, "az1_deg", "A 点方位角 α₁", bad)
	var x2 := _num(p, "x_b_m", "已知点 B x", bad)
	var y2 := _num(p, "y_b_m", "已知点 B y", bad)
	var az2 := _ang(p, "az2_deg", "B 点方位角 α₂", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var r := ray_ray(x1, y1, az1, x2, y2, az2)
	if r.is_empty():
		return _fail("两条方位线平行或重合，无唯一交点（请检查方位角）")
	var t1: float = r["t1"]
	var t2: float = r["t2"]
	var px: float = r["x"]
	var py: float = r["y"]
	var gamma := angle_at(px, py, x1, y1, x2, y2)
	var weak := gamma < WEAK_ANGLE_DEG or gamma > 180.0 - WEAK_ANGLE_DEG
	var steps := [
		_step("1. 建立两已知点的方位线", "u_i = (sin α_i, cos α_i)",
			"u₁ = (sin %s, cos %s)；u₂ = (sin %s, cos %s)" % [
				_f(GKAngles.normalize_deg(az1), 4) + "°", _f(GKAngles.normalize_deg(az1), 4) + "°",
				_f(GKAngles.normalize_deg(az2), 4) + "°", _f(GKAngles.normalize_deg(az2), 4) + "°"],
			"两条方位线方向确定"),
		_step("2. 解两线交点", "A + t₁·u₁ = B + t₂·u₂（二元一次方程组）",
			"t₁ = %s m，t₂ = %s m" % [_f(t1), _f(t2)],
			"P = (%s, %s)" % [_f(px), _f(py)]),
		_step("3. 交会角检核", "γ = 方向线 PA 与 PB 在 P 处的夹角",
			"γ = %s°" % _f(gamma, 4),
			"γ ≥ 15° 且 ≤ 165°，图形强度正常" if not weak else "γ 超出 [15°, 165°]，交会精度较弱，建议调整图形或增设已知点"),
	]
	return {
		"ok": true,
		"value": {
			"x_m": px, "y_m": py,
			"d_a_m": t1, "d_b_m": t2,
			"gamma_deg": gamma, "weak_angle": weak,
		},
		"steps": steps,
		"formula": "方位-方位交会：两条已知方位角的直线求交（2×2 线性方程组）。"
			+ "方位角从北起顺时针；交会角 γ ∈ [15°, 165°] 图形强度较好，越界提示精度弱。",
		"error": "",
	}

## B1 角度式前方交会。输入：{x_a_m, y_a_m, x_b_m, y_b_m, beta1_deg, beta2_deg, side}。
## β1 = ∠BAP（A 点），β2 = ∠ABP（B 点）；side："左"/"右"或 ±1，默认左。
static func b1_angles(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x1 := _num(p, "x_a_m", "已知点 A x", bad)
	var y1 := _num(p, "y_a_m", "已知点 A y", bad)
	var x2 := _num(p, "x_b_m", "已知点 B x", bad)
	var y2 := _num(p, "y_b_m", "已知点 B y", bad)
	var b1 := _ang(p, "beta1_deg", "A 点角 β₁", bad)
	var b2 := _ang(p, "beta2_deg", "B 点角 β₂", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var side := _side(p, "side", -1, bad, "交点侧别")
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	if b1 <= 0.0 or b2 <= 0.0:
		return _fail("交会角 β₁、β₂ 必须为正的三角形内角")
	var gamma := 180.0 - b1 - b2
	if gamma <= 0.0:
		return _fail("β₁ + β₂ = %s° ≥ 180°，不能构成交会三角形" % _f(b1 + b2, 4))
	var r := forward_by_angles(x1, y1, x2, y2, b1, b2, side)
	if r.is_empty():
		return _fail("角度式前方交会无解（几何条件不成立）")
	var weak := gamma < WEAK_ANGLE_DEG
	var side_txt := "右侧" if side >= 0 else "左侧"
	return {
		"ok": true,
		"value": {
			"x_m": r["x"], "y_m": r["y"],
			"ap_m": r["ap"], "bp_m": r["bp"],
			"az_ap_deg": r["az_ap_deg"], "az_bp_deg": r["az_bp_deg"],
			"gamma_deg": gamma, "side": side_txt, "weak_angle": weak,
		},
		"steps": [
			_step("1. 计算推算方位角", "α_AP = α_AB + side·β₁；α_BP = α_BA − side·β₂",
				"α_AB = %s°，side = %s" % [_f(GKAngles.azimuth(x2 - x1, y2 - y1), 4), side_txt],
				"α_AP = %s°，α_BP = %s°" % [_f(r["az_ap_deg"], 4), _f(r["az_bp_deg"], 4)]),
			_step("2. 两方位线求交", "A + t₁·u(α_AP) = B + t₂·u(α_BP)",
				"两线求交",
				"P = (%s, %s)" % [_f(r["x"]), _f(r["y"])]),
			_step("3. 交会角检核", "γ = 180° − β₁ − β₂",
				"γ = 180° − %s° − %s°" % [_f(b1, 4), _f(b2, 4)],
				"γ = %s°%s" % [_f(gamma, 4), "" if not weak else "，γ < 15° 交会精度较弱，建议调整图形"]),
		],
		"formula": "角度式前方交会：由已知边方位角推算 α_AP、α_BP 后两线求交。"
			+ "β₁ = ∠BAP（A 点）、β₂ = ∠ABP（B 点）；交点默认位于 A→B 左侧（side=左）。",
		"error": "",
	}

## B1 侧方交会。输入：{x_a_m, y_a_m, x_b_m, y_b_m, beta_a_deg, gamma_deg, side}。
## β_A = ∠BAP 在已知点 A 观测，γ = ∠APB 在待定点 P 观测；side 默认左。
static func b1_side(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x1 := _num(p, "x_a_m", "已知点 A x", bad)
	var y1 := _num(p, "y_a_m", "已知点 A y", bad)
	var x2 := _num(p, "x_b_m", "已知点 B x", bad)
	var y2 := _num(p, "y_b_m", "已知点 B y", bad)
	var ba := _ang(p, "beta_a_deg", "A 点观测角 β_A", bad)
	var ga := _ang(p, "gamma_deg", "P 点观测角 γ", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var side := _side(p, "side", -1, bad, "交点侧别")
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	if ba <= 0.0 or ga <= 0.0 or ga >= 180.0:
		return _fail("观测角 β_A、γ 必须为正且 γ < 180°")
	var beta_b := 180.0 - ba - ga
	if beta_b <= 0.0:
		return _fail("β_A + γ = %s° ≥ 180°，B 点内角为负，不能构成交会三角形" % _f(ba + ga, 4))
	var r := side_intersection(x1, y1, x2, y2, ba, ga, side)
	if r.is_empty():
		return _fail("侧方交会无解（几何条件不成立）")
	var ab := inv_len(x1, y1, x2, y2)
	var ap: float = r["ap"]
	var bp: float = r["bp"]
	var side_txt := "右侧" if side >= 0 else "左侧"
	return {
		"ok": true,
		"value": {
			"x_m": r["x"], "y_m": r["y"],
			"ap_m": ap, "bp_m": bp, "ab_m": ab,
			"beta_b_deg": beta_b,
			"az_ap_deg": r["az_ap_deg"],
			"side": side_txt,
		},
		"steps": [
			_step("1. 推算 B 点内角", "β_B = 180° − β_A − γ",
				"β_B = 180° − %s° − %s°" % [_f(ba, 4), _f(ga, 4)],
				"β_B = %s°" % _f(beta_b, 4)),
			_step("2. 推算 A→P 方位角", "α_AP = α_AB + side·β_A（side：左 −1 / 右 +1）",
				"α_AB = %s°，side = %s" % [_f(GKAngles.azimuth(x2 - x1, y2 - y1), 4), side_txt],
				"α_AP = %s°" % _f(r["az_ap_deg"], 4)),
			_step("3. 解三角形求 AP 边长", "AP = AB·sin β_B / sin γ",
				"AP = %s·sin %s° / sin %s°" % [_f(ab, 4), _f(beta_b, 4), _f(ga, 4)],
				"AP = %s m" % _f(ap)),
			_step("4. 坐标正算定 P", "x_P = x_A + AP·sin α_AP；y_P = y_A + AP·cos α_AP",
				"P 由 A 点沿 α_AP 前推 AP",
				"P = (%s, %s)" % [_f(r["x"]), _f(r["y"])]),
		],
		"formula": "侧方交会：已知 A、B，在 A 测 β_A（∠BAP）、在 P 测 γ（∠APB）。"
			+ "三角形内角和推 β_B 后按正弦定理求 AP，再坐标正算。交点默认位于 A→B 左侧。",
		"error": "",
	}

## B1 后方交会。输入：{x_a_m, y_a_m, x_b_m, y_b_m, x_c_m, y_c_m, alpha_deg, beta_deg}。
## α = ∠APB、β = ∠BPC（在 P 点顺时针观测）。危险圆返回 ok=false 中文警告。
static func b1_resection(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x1 := _num(p, "x_a_m", "已知点 A x", bad)
	var y1 := _num(p, "y_a_m", "已知点 A y", bad)
	var x2 := _num(p, "x_b_m", "已知点 B x", bad)
	var y2 := _num(p, "y_b_m", "已知点 B y", bad)
	var x3 := _num(p, "x_c_m", "已知点 C x", bad)
	var y3 := _num(p, "y_c_m", "已知点 C y", bad)
	var al := _ang(p, "alpha_deg", "观测角 α（∠APB）", bad)
	var be := _ang(p, "beta_deg", "观测角 β（∠BPC）", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var r := resection(x1, y1, x2, y2, x3, y3, al, be)
	if r.has("danger"):
		var d := String(r["danger"])
		if d == "danger_circle":
			return _fail("危险圆：A、B、C 与待定点 P 近似共圆，后方交会解不定（无数解）。"
				+ "请更换已知点组合、增加第四个观测方向或改用距离后方交会。")
		return _fail(d)
	var pa: float = r["pa"]
	var pb: float = r["pb"]
	var pc: float = r["pc"]
	var ga: float = r["gamma_ab"]
	var gb: float = r["gamma_bc"]
	var weak := al < WEAK_ANGLE_DEG or be < WEAK_ANGLE_DEG
	var steps := [
		_step("1. 构造定位圆（∠APB = α）", "R₁ = AB / (2·sin α)，圆心在 AB 中垂线上，偏距 (AB/2)·cot α",
			"R₁ = AB / (2·sin %s°)" % _f(al, 4),
			"圆₁ 过 A、B"),
		_step("2. 构造定位圆（∠BPC = β）", "R₂ = BC / (2·sin β)，圆心在 BC 中垂线上，偏距 (BC/2)·cot β",
			"R₂ = BC / (2·sin %s°)" % _f(be, 4),
			"圆₂ 过 B、C"),
		_step("3. 两定位圆求交并选解", "P ∈ 圆₁ ∩ 圆₂（剔除已知点 B，按观测角+顺时针方向检核）",
			"两侧共 4 种圆心组合求交",
			"P = (%s, %s)" % [_f(r["x"]), _f(r["y"])]),
		_step("4. 检核", "反算 ∠APB、∠BPC 与观测值较差；距离 PA/PB/PC",
			"∠APB = %s°，∠BPC = %s°" % [_f(ga, 6), _f(gb, 6)],
			"较差 ≤ 1e-4°，PA = %s m，PB = %s m，PC = %s m" % [_f(pa), _f(pb), _f(pc)]),
	]
	if weak:
		steps.append(_step("精度提示", "交会角（观测角）过小图形强度弱",
			"α = %s°，β = %s°" % [_f(al, 4), _f(be, 4)],
			"存在观测角 < 15°，后方交会精度较弱，建议增设已知点或加测第四方向"))
	return {
		"ok": true,
		"value": {
			"x_m": r["x"], "y_m": r["y"],
			"pa_m": pa, "pb_m": pb, "pc_m": pc,
			"gamma_ab_deg": ga, "gamma_bc_deg": gb,
			"weak_angle": weak,
		},
		"steps": steps,
		"formula": "后方交会（定位圆解析法）：∠APB = α 的轨迹是过 A、B 的圆（R = AB/2sinα），"
			+ "两定位圆交点即 P。两圆重合 ⟺ 危险圆（四点共圆），无解。观测角按顺时针方向（α 从 PA 顺转至 PB，β 从 PB 顺转至 PC）。",
		"error": "",
	}

## B2 方位-方位交会（与 b1_azimuth 同一算法的 B2 编号入口）
static func b2_az_az(p: Dictionary) -> Dictionary:
	return b1_azimuth(p)

## B2 方位-距离交会。输入：{x_a_m, y_a_m, az1_deg, x_b_m, y_b_m, d_b_m, branch}。
## branch："near"/"far"（近端/远端），默认 near。
static func b2_az_dist(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x1 := _num(p, "x_a_m", "已知点 A x", bad)
	var y1 := _num(p, "y_a_m", "已知点 A y", bad)
	var az1 := _ang(p, "az1_deg", "A 点方位角 α₁", bad)
	var x2 := _num(p, "x_b_m", "已知点 B x", bad)
	var y2 := _num(p, "y_b_m", "已知点 B y", bad)
	var db := _num(p, "d_b_m", "B 点距离 D_B", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var branch := "near"
	if p.has("branch"):
		var t := String(p["branch"]).strip_edges().to_lower()
		if t == "far" or t == "远" or t == "远端":
			branch = "far"
		elif t == "near" or t == "近" or t == "近端" or t.is_empty():
			branch = "near"
		else:
			return _fail("分支只支持 near（近端）或 far（远端），输入：%s" % t)
	if db <= 0.0:
		return _fail("距离 D_B 必须为正数（输入 %.4f）" % db)
	var r := ray_circle(x1, y1, az1, x2, y2, db)
	if r.is_empty():
		return _fail("方位线与圆无实交点（D_B 过小，或交点位于方位线反方向），请检查输入")
	var solutions: Array = r["solutions"]
	var sel: Dictionary = {}
	var alt: Dictionary = {}
	for s: Dictionary in solutions:
		if String(s["branch"]) == branch:
			sel = s
		else:
			alt = s
	if sel.is_empty():
		return _fail("所选分支（%s）无解：该侧交点位于方位线反方向或不存在" % ("近端" if branch == "near" else "远端"))
	var px: float = sel["x"]
	var py: float = sel["y"]
	var t: float = sel["t"]
	# 检核：P 到 B 的距离应等于 D_B
	var chk := inv_len(px, py, x2, y2)
	# 相切判定：唯一解且判别式平方根 ≈ 0（t_near ≈ t_far）
	var is_tangent: bool = solutions.size() == 1 and absf(float(r["sq"])) < 1e-9 * maxf(db, 1.0)
	var value := {
		"x_m": px, "y_m": py,
		"t_m": t, "d_a_m": t,
		"d_b_check_m": chk, "d_b_m": db,
		"branch": "近端" if branch == "near" else "远端",
		"tangent": is_tangent,
	}
	if not alt.is_empty():
		value["alt_x_m"] = alt["x"]
		value["alt_y_m"] = alt["y"]
	var t_txt := ""
	if solutions.size() > 1:
		t_txt = "t₁ = %s m（近），t₂ = %s m（远）" % [_f(float(solutions[0]["t"])), _f(float(solutions[1]["t"]))]
	elif is_tangent:
		t_txt = "唯一解 t = %s m（射线与圆相切，双解重合）" % _f(t)
	else:
		t_txt = "可行解 t = %s m（另一解 t < 0 位于射线反方向，已剔除）" % _f(t)
	return {
		"ok": true,
		"value": value,
		"steps": [
			_step("1. 写出射线参数方程", "P(t) = A + t·u(α₁)，u = (sin α₁, cos α₁)",
				"A = (%s, %s)，α₁ = %s°" % [_f(x1), _f(y1), _f(GKAngles.normalize_deg(az1), 4)],
				"|P(t) − B| = D_B"),
			_step("2. 解一元二次方程", "t² − 2·(u·(B−A))·t + (|B−A|² − D_B²) = 0",
				"判别式 Δ = (u·(B−A))² − (|B−A|² − D_B²)",
				t_txt),
			_step("3. 选定分支并检核", "按 branch 取近端/远端解，反算 |PB| 与 D_B 较差",
				"分支 = %s" % ("近端" if branch == "near" else "远端"),
				"P = (%s, %s)，|PB| = %s m（应 = %s m）" % [_f(px), _f(py), _f(chk), _f(db)]),
		],
		"formula": "方位-距离交会：方位线参数方程与圆方程联立得一元二次，双解取近端/远端。"
			+ "解位于方位线反方向（t<0）时判为无解。",
		"error": "",
	}

## B2 距离-距离交会。输入：{x_a_m, y_a_m, d_a_m, x_b_m, y_b_m, d_b_m, side}。
## side：+1=右（默认，对应权威向量 P₊）、−1=左。
static func b2_dist_dist(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x1 := _num(p, "x_a_m", "已知点 A x", bad)
	var y1 := _num(p, "y_a_m", "已知点 A y", bad)
	var da := _num(p, "d_a_m", "A 点距离 D_A", bad)
	var x2 := _num(p, "x_b_m", "已知点 B x", bad)
	var y2 := _num(p, "y_b_m", "已知点 B y", bad)
	var db := _num(p, "d_b_m", "B 点距离 D_B", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var side := _side(p, "side", 1, bad, "交点侧别")
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	if da <= 0.0 or db <= 0.0:
		return _fail("观测距离 D_A、D_B 必须为正数")
	var r := circle_circle(x1, y1, da, x2, y2, db)
	if r.is_empty():
		if sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)) < 1e-12:
			return _fail("两已知点重合，无法交会")
		return _fail("两圆无实交点：|D_A − D_B| > D_AB 或 D_A + D_B < D_AB，距离与已知边不匹配")
	var solutions: Array = r["solutions"]
	var sel: Dictionary = {}
	var other: Dictionary = {}
	for s: Dictionary in solutions:
		var sd: int = int(s["side"])
		if sd == side or (sd == 0 and solutions.size() == 1):
			sel = s
		else:
			other = s
	if sel.is_empty():
		sel = solutions[0]  # 相切等退化场合
	var px: float = sel["x"]
	var py: float = sel["y"]
	var chk_a := inv_len(px, py, x1, y1)
	var chk_b := inv_len(px, py, x2, y2)
	var gamma := angle_at(px, py, x1, y1, x2, y2)
	var weak := gamma < WEAK_ANGLE_DEG or gamma > 180.0 - WEAK_ANGLE_DEG
	var tangent: bool = int(sel["side"]) == 0
	var side_txt := "切点" if tangent else ("右侧" if side >= 0 else "左侧")
	var value := {
		"x_m": px, "y_m": py,
		"d_ab_m": r["d_ab"], "a_m": r["a"], "h_m": r["h"],
		"d_a_check_m": chk_a, "d_b_check_m": chk_b,
		"gamma_deg": gamma, "side": side_txt, "weak_angle": weak,
		"tangent": tangent,
	}
	if not other.is_empty():
		value["alt_x_m"] = other["x"]
		value["alt_y_m"] = other["y"]
		value["alt_side"] = "左" if int(other["side"]) < 0 else "右"
	return {
		"ok": true,
		"value": value,
		"steps": [
			_step("1. 计算已知边", "D_AB = √(Δx² + Δy²)",
				"AB 两点坐标差求边长",
				"D_AB = %s m" % _f(r["d_ab"])),
			_step("2. 求交点弦位置", "a = (D_A² − D_B² + D_AB²)/(2·D_AB)；h = √(D_A² − a²)",
				"a = %s m，h = %s m" % [_f(r["a"]), _f(r["h"])],
				"垂足 (%s, %s)，偏移 h" % [_f(r["foot_x"]), _f(r["foot_y"])]),
			_step("3. 双解坐标", "P = 垂足 ± h·n（右法线 n = (u_y, −u_x)）",
				"side = %s" % side_txt,
				"P = (%s, %s)" % [_f(px), _f(py)]),
			_step("4. 检核", "反算 |PA|、|PB| 与观测距离较差；交会角 γ",
				"|PA| = %s m，|PB| = %s m，γ = %s°" % [_f(chk_a), _f(chk_b), _f(gamma, 4)],
				"较差 ≤ 1e-9 m；%s" % ("图形强度正常" if not weak else "γ 超出 [15°, 165°]，交会精度较弱")),
		],
		"formula": "距离-距离交会（两圆求交）：a = (D_A²−D_B²+D_AB²)/2D_AB，h = √(D_A²−a²)。"
			+ "恒有双解（相切退化为一解），按 side 选右侧（+1，默认）或左侧（−1）；另一解在 value.alt_x/alt_y。",
		"error": "",
	}

# ---------- 协议与解析小工具 ----------

static func _step(title: String, formula: String, substitution: String, result: String) -> Dictionary:
	return {"title": title, "formula": formula, "substitution": substitution, "result": result}

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}

static func _f(v: float, n := 4) -> String:
	var fmt := "%." + str(n) + "f"
	return fmt % v

static func _join_bad(bad: Array) -> String:
	var out := ""
	for i in bad.size():
		if i > 0:
			out += "；"
		out += String(bad[i])
	return out

static func _num(p: Dictionary, key: String, label: String, bad: Array) -> float:
	if not p.has(key):
		bad.append("缺少输入项「%s」" % label)
		return NAN
	var v: Variant = p[key]
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return f
		bad.append("「%s」数值非有限" % label)
		return NAN
	if v is String:
		var t := String(v).strip_edges().replace("−", "-")
		if t.is_empty():
			bad.append("请输入「%s」" % label)
			return NAN
		if t.is_valid_float():
			var f2 := t.to_float()
			if is_finite(f2):
				return f2
		bad.append("「%s」不是有效数字：%s" % [label, t])
		return NAN
	bad.append("「%s」输入类型不支持" % label)
	return NAN

static func _ang(p: Dictionary, key: String, label: String, bad: Array) -> float:
	if not p.has(key):
		bad.append("缺少输入项「%s」" % label)
		return NAN
	var v: Variant = p[key]
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return f
		bad.append("「%s」数值非有限" % label)
		return NAN
	if v is String:
		var t := String(v).strip_edges()
		if t.is_empty():
			bad.append("请输入「%s」" % label)
			return NAN
		var deg := GKAngles.parse_dms(t)
		if is_nan(deg):
			bad.append("「%s」不是有效角度：%s（可输 30.5 或 30 30 00）" % [label, t])
			return NAN
		return deg
	bad.append("「%s」输入类型不支持" % label)
	return NAN

## 侧别解析：左/右/left/right/±1；非法值记入 bad（空则用默认）
static func _side(p: Dictionary, key: String, default_side: int, bad: Array, label: String) -> int:
	if not p.has(key):
		return default_side
	var v: Variant = p[key]
	var t := ""
	if v is String:
		t = String(v).strip_edges().to_lower()
	elif v is float or v is int:
		var fi := int(v)
		if fi == 1:
			return 1
		if fi == -1:
			return -1
		bad.append("「%s」只支持 左/右（±1）" % label)
		return 0
	else:
		bad.append("「%s」输入类型不支持" % label)
		return 0
	if t.is_empty():
		return default_side
	if t == "右" or t == "r" or t == "right" or t == "1" or t == "+1":
		return 1
	if t == "左" or t == "l" or t == "left" or t == "-1" or t == "−1":
		return -1
	bad.append("「%s」只支持 左/右（或 left/right/±1），输入：%s" % [label, t])
	return 0

static func inv_len(x1: float, y1: float, x2: float, y2: float) -> float:
	var dx := x2 - x1
	var dy := y2 - y1
	return sqrt(dx * dx + dy * dy)

## 圆-圆求交（内部用，含相切退化；不检查包含/外离语义）
static func circle_intersect(o1x: float, o1y: float, r1: float, o2x: float, o2y: float, r2: float) -> Array:
	var dx := o2x - o1x
	var dy := o2y - o1y
	var d := sqrt(dx * dx + dy * dy)
	if d < 1e-15:
		return []  # 同心
	if d > r1 + r2 or d < absf(r1 - r2):
		return []
	var a := (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
	var h2 := r1 * r1 - a * a
	var h := sqrt(maxf(h2, 0.0))
	var mx := o1x + a * dx / d
	var my := o1y + a * dy / d
	var out := []
	if h2 <= 1e-12 * r1 * r1:
		out.append({"x": mx, "y": my})
	else:
		out.append({"x": mx + h * dy / d, "y": my - h * dx / d})
		out.append({"x": mx - h * dy / d, "y": my + h * dx / d})
	return out

## 三点外接圆（内部危险圆复核用）；共线返回 {}
static func circumcircle_3p(x1: float, y1: float, x2: float, y2: float, x3: float, y3: float) -> Dictionary:
	var d := 2.0 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
	if absf(d) < 1e-12:
		return {}
	var s1 := x1 * x1 + y1 * y1
	var s2 := x2 * x2 + y2 * y2
	var s3 := x3 * x3 + y3 * y3
	var cx := (s1 * (y2 - y3) + s2 * (y3 - y1) + s3 * (y1 - y2)) / d
	var cy := (s1 * (x3 - x2) + s2 * (x1 - x3) + s3 * (x2 - x1)) / d
	var dxr := x1 - cx
	var dyr := y1 - cy
	return {"cx": cx, "cy": cy, "r": sqrt(dxr * dxr + dyr * dyr)}
