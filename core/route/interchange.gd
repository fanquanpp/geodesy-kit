# core/route/interchange.gd —— GK-M7-8 匝道复杂线型 D6（C型/S型/卵型/回头曲线）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M7 / §5）：
#   - 全部匝道 = 线元序列（D2 契约），坐标/方位由 GKAlignmentEl 装配，本文件只做组合与检核；
#   - 线型定义（回旋线组合口径）：
#       基本型：直线—回旋(0→1/R)—圆—回旋(1/R→0)—直线（basic，α<180°）；
#       S型：  圆(R1,+β1)—回旋(1/R1→0)—回旋(0→−1/R2)—圆(R2,−β2)：两反向回旋线在曲率
#              零点径相衔接（无直线段），转向相反；
#       卵型：  圆(R1,+β1)—回旋(1/R1→1/R2)—圆(R2,+β2)：两同向圆曲线间以一个回旋线连接
#              （要求 R1>R2）；
#       C型：  圆(R1,+β1)—回旋(1/R1→0)—[短直线]—回旋(0→1/R2)—圆(R2,+β2)：两同向回旋线
#              在曲率零点衔接（夹直线默认 0），转向相同；
#       回头曲线：转角 |α|>180° 的基本型线元序列（交点法切线长公式失效，不输出 T/E）；
#   - 检核：接点曲率连续、总转角 = Σ(k0+k1)/2·len（与线元表逐段复核）、正反算往返闭合；
#   - 校验失败 ok=false + 中文 error（卵型要求 R1>R2、半径/转角为正等）。
class_name GKInterchange
extends RefCounted

const El := preload("res://core/route/alignment_el.gd")

# ---------- 线型组合器 ----------

## 基本型（直—缓—圆—缓—直）。p = { r_m, l0_m, alpha_deg, dir=±1, start }
static func basic(p: Dictionary) -> Dictionary:
	var r := _num(p.get("r_m", NAN))
	var l0 := _num(p.get("l0_m", 0.0)) if p.has("l0_m") else 0.0
	var adeg := _num(p.get("alpha_deg", NAN))
	var dir := _dir(p)
	if _bad_rla(r, l0, adeg, dir):
		return _err("输入须为：r_m>0、l0_m≥0、0<alpha_deg<180、dir=±1")
	if adeg - rad_to_deg(l0 / r) <= 0.0:
		return _err("缓和曲线过长：圆曲线段转角 α−2β0=%.4f° 非正，请减小 l0 或增大 R" % (adeg - rad_to_deg(l0 / r)))
	var els := []
	if l0 > 0.0:
		els.append(El.make_spiral(0.0, r, l0, dir))
	els.append(El.make_arc(r, dir * (adeg - rad_to_deg(l0 / r))))
	if l0 > 0.0:
		els.append(El.make_spiral(r, 0.0, l0, dir))
	return _assemble_report("基本型（直—缓—圆—缓—直）", els, p,
			"匝道基本型：缓和曲线参数 A²=R·l0；α<180° 时也可用交点法（D1）计算切线长/主点里程")

## S型：两反向回旋线在曲率零点径相衔接。p = { r1_m, r2_m, l01_m, l02_m,
##        arc1_turn_deg(圆1纯圆段转角), arc2_turn_deg, dir=±1(第一段转向，第二段取反), start }
static func s_type(p: Dictionary) -> Dictionary:
	var r1 := _num(p.get("r1_m", NAN))
	var r2 := _num(p.get("r2_m", NAN))
	var l01 := _num(p.get("l01_m", NAN))
	var l02 := _num(p.get("l02_m", NAN))
	var b1 := _num(p.get("arc1_turn_deg", NAN))
	var b2 := _num(p.get("arc2_turn_deg", NAN))
	var dir := _dir(p)
	if _bad5(r1, r2, l01, l02, dir) or is_nan(b1) or is_nan(b2) or b1 <= 0.0 or b2 <= 0.0:
		return _err("S型输入须为：r1_m/r2_m>0、l01_m/l02_m>0、arc1_turn_deg/arc2_turn_deg>0、dir=±1")
	var els := [
		El.make_arc(r1, dir * b1),
		El.make_spiral(r1, 0.0, l01, dir),
		El.make_spiral(0.0, r2, l02, -dir),
		El.make_arc(r2, -dir * b2),
	]
	return _assemble_report("S型（反向回旋线曲率零点衔接）", els, p,
			"S型匝道：两反向回旋线在曲率零点（k=0）径相衔接；回旋线各自参数 A₁²=R1·l01、A₂²=R2·l02")

## 卵型：两同向圆曲线间以一个回旋线连接。p = { r1_m, r2_m, l0_m,
##        arc1_turn_deg, arc2_turn_deg, dir=±1, start }（要求 r1 > r2）
static func egg(p: Dictionary) -> Dictionary:
	var r1 := _num(p.get("r1_m", NAN))
	var r2 := _num(p.get("r2_m", NAN))
	var l0 := _num(p.get("l0_m", NAN))
	var b1 := _num(p.get("arc1_turn_deg", NAN))
	var b2 := _num(p.get("arc2_turn_deg", NAN))
	var dir := _dir(p)
	if _bad5(r1, r2, l0, b1, dir) or is_nan(b2) or b2 <= 0.0 or b1 <= 0.0 or l0 <= 0.0:
		return _err("卵型输入须为：r1_m/r2_m>0、l0_m>0、arc1_turn_deg/arc2_turn_deg>0、dir=±1")
	if r2 >= r1:
		return _err("卵型要求大圆半径 r1 > 小圆半径 r2（当前 r1=%s，r2=%s）" % [str(r1), str(r2)])
	var els := [
		El.make_arc(r1, dir * b1),
		El.make_spiral(r1, r2, l0, dir),
		El.make_arc(r2, dir * b2),
	]
	return _assemble_report("卵型（同向圆曲线间回旋线连接）", els, p,
			"卵型匝道：回旋线曲率自 1/R1 连续过渡到 1/R2，参数 A²=l0·R1·R2/(R1−R2)；要求 R1>R2")

## C型：两同向回旋线在曲率零点衔接（可夹短直线）。p = { r1_m, r2_m, l01_m, l02_m,
##        arc1_turn_deg, arc2_turn_deg, straight_m=0, dir=±1, start }
static func c_type(p: Dictionary) -> Dictionary:
	var r1 := _num(p.get("r1_m", NAN))
	var r2 := _num(p.get("r2_m", NAN))
	var l01 := _num(p.get("l01_m", NAN))
	var l02 := _num(p.get("l02_m", NAN))
	var b1 := _num(p.get("arc1_turn_deg", NAN))
	var b2 := _num(p.get("arc2_turn_deg", NAN))
	var straight := _num(p.get("straight_m", 0.0)) if p.has("straight_m") else 0.0
	var dir := _dir(p)
	if _bad5(r1, r2, l01, l02, dir) or is_nan(b1) or is_nan(b2) or b1 <= 0.0 or b2 <= 0.0 or is_nan(straight) or straight < 0.0:
		return _err("C型输入须为：r1_m/r2_m>0、l01_m/l02_m>0、转角>0、straight_m≥0、dir=±1")
	var els := [
		El.make_arc(r1, dir * b1),
		El.make_spiral(r1, 0.0, l01, dir),
	]
	if straight > 0.0:
		els.append(El.make_line(straight))
	els.append(El.make_spiral(0.0, r2, l02, dir))
	els.append(El.make_arc(r2, dir * b2))
	return _assemble_report("C型（同向回旋线曲率零点衔接）", els, p,
			"C型匝道：两同向回旋线在曲率零点（k=0）径相衔接，可夹短直线（straight_m，默认 0）")

## 回头曲线：转角 |α|>180° 的基本型线元序列。p = { r_m, l0_m, alpha_deg(|α|>180), dir=±1, start }
static func hairpin(p: Dictionary) -> Dictionary:
	var r := _num(p.get("r_m", NAN))
	var l0 := _num(p.get("l0_m", 0.0)) if p.has("l0_m") else 0.0
	var adeg := _num(p.get("alpha_deg", NAN))
	var dir := _dir(p)
	if not (is_finite(r) and is_finite(l0) and is_finite(adeg)) or r <= 0.0 or l0 < 0.0 \
			or absf(adeg) <= 180.0 or absf(adeg) > 540.0 or (dir != 1 and dir != -1):
		return _err("回头曲线输入须为：r_m>0、l0_m≥0、180°<|alpha_deg|≤540°、dir=±1")
	if absf(adeg) - rad_to_deg(l0 / r) <= 0.0:
		return _err("缓和曲线过长：圆曲线段转角非正")
	var a := absf(adeg)
	var els := []
	if l0 > 0.0:
		els.append(El.make_spiral(0.0, r, l0, dir))
	els.append(El.make_arc(r, dir * (a - rad_to_deg(l0 / r))))
	if l0 > 0.0:
		els.append(El.make_spiral(r, 0.0, l0, dir))
	return _assemble_report("回头曲线（转角 %s，%s）" % [GKAngles.deg_to_dms_str(a, 1), "右回头" if dir > 0 else "左回头"], els, p,
			"回头曲线：|α|>180°，交点法切线长公式失效；本模块以线元序列直接计算坐标与总转角，不输出 T/E")

# ---------- 内部装配与检核 ----------

## 组装线元序列 → D2 build → 检核报告（协议结构）
static func _assemble_report(type_cn: String, els: Array, p: Dictionary, formula_note: String) -> Dictionary:
	var built := El.build({"elements": els, "start": p.get("start", {})})
	if not bool(built.get("ok", false)):
		return _err(String(built.get("error", "线元装配失败：请提供合法的 start（x_m/y_m/bearing_deg）")))
	var segs: Array = built["value"]["segs"]
	# 检核1：总转角 = Σ(k0+k1)/2·len，另按"逐段转角和"复核
	var turn1 := El.turn_total_rad(els)
	var turn2 := 0.0
	for seg: Dictionary in segs:
		turn2 += deg_to_rad(float(seg["turn_deg"]))
	if absf(turn1 - turn2) > 1e-9:
		return _err("内部检核失败：总转角两条路径不一致（%.12f vs %.12f rad）" % [turn1, turn2])
	# 检核2：接点曲率连续（相邻线元 k1 == k0_{i+1}）
	for i in range(1, els.size()):
		var k_prev: float = els[i - 1]["k1"]
		var k_cur: float = els[i]["k0"]
		if absf(k_prev - k_cur) > 1e-12:
			return _err("内部检核失败：线元 %d 与 %d 接点曲率不连续（%f vs %f）" % [i, i + 1, k_prev, k_cur])
	# 检核3：终点连续性（逐段 x1/y1 == 下一段 x0/y0）
	for i in range(1, segs.size()):
		var prev: Dictionary = segs[i - 1]
		var cur: Dictionary = segs[i]
		if absf(float(prev["x1_m"]) - float(cur["x0_m"])) > 1e-9 \
				or absf(float(prev["y1_m"]) - float(cur["y0_m"])) > 1e-9:
			return _err("内部检核失败：线元 %d→%d 接点坐标不连续" % [i, i + 1])
	var steps := []
	for seg: Dictionary in segs:
		steps.append({
			"title": "%s：线元%d %s（长 %.4f m）" % [type_cn, int(seg["index"]) + 1, _type_cn(seg["type"]), float(seg["len_m"])],
			"formula": "k(s)=k0+(k1−k0)s/L 线性过渡；总转角=∫k·ds",
			"substitution": "k0=%.8f → k1=%.8f (1/m)" % [float(seg["k0"]), float(seg["k1"])],
			"result": "终点(%s, %s)，方位 %.4f°，本段转角 %.4f°" % [String.num(float(seg["x1_m"]), 4), String.num(float(seg["y1_m"]), 4), float(seg["bearing1_deg"]), float(seg["turn_deg"])],
		})
	steps.append({
		"title": "检核",
		"formula": "Σ(k0+k1)/2·len == Σ分段转角；接点曲率连续；接点坐标连续",
		"substitution": "%d 个线元" % els.size(),
		"result": "总转角 %.6f°，全长 %.4f m，三项检核全部通过" % [rad_to_deg(turn1), built["value"]["total_len_m"]],
	})
	return {"ok": true, "value": {
				"type_cn": type_cn,
				"elements": els,
				"segs": segs,
				"total_len_m": built["value"]["total_len_m"],
				"total_turn_deg": rad_to_deg(turn1),
				"element_count": els.size(),
			},
			"steps": steps,
			"formula": "匝道线型 = 线元序列组合（" + formula_note + "）；坐标定位与检核走线元法 D2",
			"error": ""}

# ---------- 内部工具 ----------

static func _dir(p: Dictionary) -> int:
	return 1 if not p.has("dir") else int(p["dir"])

static func _bad_rla(r: float, l0: float, adeg: float, dir: int) -> bool:
	return not (is_finite(r) and is_finite(l0) and is_finite(adeg)) or r <= 0.0 or l0 < 0.0 \
			or adeg <= 0.0 or adeg >= 180.0 or (dir != 1 and dir != -1)

static func _bad5(r1: float, r2: float, l0: float, b: float, dir: int) -> bool:
	return not (is_finite(r1) and is_finite(r2) and is_finite(l0) and is_finite(b)) \
			or r1 <= 0.0 or r2 <= 0.0 or l0 < 0.0 or (dir != 1 and dir != -1)

static func _type_cn(t: String) -> String:
	match t:
		"line": return "直线"
		"arc": return "圆曲线"
		_: return "缓和曲线"

static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String:
		var t := String(v).strip_edges()
		if t.is_valid_float():
			return t.to_float()
	return NAN

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
