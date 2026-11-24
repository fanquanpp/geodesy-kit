# core/route/curve_elements.gd —— 缓和曲线要素（切线长 T、曲线全长 L、外距 E、切曲差 q、主点里程）
#
# 要素式：β0=l0/(2R)、p=l0²/(24R)−l0⁴/(2688R³)、m=l0/2−l0³/(240R²)；
# T=(R+p)tan(α/2)+m、L=R·αrad+l0、E=(R+p)/cos(α/2)−R、q=2T−L；l0=0 退化为纯圆曲线。
# 主点里程：ZH(ZY)→HY→QZ→YZ→HZ；α 须 ∈(0°,180°)（回头曲线用线元法 D2/D6）。
# 校验失败 ok=false + 中文 error。
class_name GKCurveElements
extends RefCounted

## 纯核：由 R、l0、α(rad) 计算要素字典。非法输入返回 {}。
static func elements(r: float, l0: float, alpha_rad: float) -> Dictionary:
	if not (is_finite(r) and is_finite(l0) and is_finite(alpha_rad)) \
			or r <= 0.0 or l0 < 0.0 or alpha_rad <= 0.0 or alpha_rad >= PI:
		return {}
	var beta0_rad := l0 / (2.0 * r)
	if 2.0 * beta0_rad >= alpha_rad:
		return {}  # 缓和曲线角超过转角，圆曲线段长非正
	var p_int := l0 * l0 / (24.0 * r) - pow(l0, 4.0) / (2688.0 * pow(r, 3.0))
	var m := l0 / 2.0 - pow(l0, 3.0) / (240.0 * r * r)
	var t_len := (r + p_int) * tan(alpha_rad / 2.0) + m
	var l_len := r * alpha_rad + l0
	var l_circ := r * (alpha_rad - 2.0 * beta0_rad)
	var e_ext := (r + p_int) / cos(alpha_rad / 2.0) - r
	var q_diff := 2.0 * t_len - l_len
	var out := {
		"beta0_rad": beta0_rad,
		"beta0_deg": rad_to_deg(beta0_rad),
		"p_m": p_int,
		"m_m": m,
		"t_m": t_len,
		"l_m": l_len,
		"l_circ_m": l_circ,
		"l_spiral_m": l0,
		"e_m": e_ext,
		"q_m": q_diff,
	}
	if l0 > 0.0:
		var x0 := l0 - pow(l0, 3.0) / (40.0 * r * r) + pow(l0, 5.0) / (3456.0 * pow(r, 4.0))
		var y0 := l0 * l0 / (6.0 * r) - pow(l0, 4.0) / (336.0 * pow(r, 3.0)) + pow(l0, 6.0) / (42240.0 * pow(r, 5.0))
		out["x0_m"] = x0
		out["y0_m"] = y0
	return out

## 纯核：主点里程。jd_chain 为交点里程（m）。非法/未给里程返回 []。
## l0>0 → [ZH, HY, QZ, YZ, HZ]；l0=0 → [ZY, QZ, YZ]。
static func main_chains(jd_chain: float, t_len: float, l_len: float, l0: float) -> PackedFloat64Array:
	if not (is_finite(jd_chain) and is_finite(t_len) and is_finite(l_len)) \
			or l_len <= 0.0 or l0 < 0.0:
		return PackedFloat64Array()
	var zh := jd_chain - t_len
	var out := PackedFloat64Array()
	if l0 > 0.0:
		out.append(zh)            # ZH
		out.append(zh + l0)       # HY
		out.append(zh + l_len / 2.0)  # QZ
		out.append(zh + l_len - l0)   # YZ
		out.append(zh + l_len)    # HZ
	else:
		out.append(zh)            # ZY
		out.append(zh + l_len / 2.0)  # QZ
		out.append(zh + l_len)    # YZ
	return out

## B3 协议入口。
## p = { r_m, l0_m=0, alpha_deg, jd_chain_m?(可选), dir=+1右/−1左(仅文案用) }
## value = 要素 + beta0_deg/p_m/m_m/t_m/l_m/l_circ_m/e_m/q_m(/x0_m/y0_m)
##         + 主点里程 zh_m/hy_m/qz_m/yz_m/hz_m（或 zy_m/qz_m/yz_m）。
static func forward(p: Dictionary) -> Dictionary:
	var r := _num(p.get("r_m", NAN))
	var l0 := _num(p.get("l0_m", 0.0)) if p.has("l0_m") else 0.0
	var adeg := _num(p.get("alpha_deg", NAN))
	if is_nan(r) or is_nan(adeg):
		return _err("输入缺失或非法：r_m 与 alpha_deg 均须为数字")
	var jd := NAN
	if p.has("jd_chain_m"):
		jd = _num(p["jd_chain_m"])
		if is_nan(jd):
			return _err("jd_chain_m 须为数字里程（m）")
	var alpha_rad := deg_to_rad(adeg)
	var el := elements(r, l0, alpha_rad)
	if el.is_empty():
		if r <= 0.0:
			return _err("半径 R 必须大于 0（当前 %s）" % str(r))
		if alpha_rad <= 0.0 or alpha_rad >= PI:
			return _err("转角 α 须在 0°~180° 之间（当前 %s°）。α≥180° 的回头曲线请改用线元法（D2）或匝道模块（D6）" % str(adeg))
		if l0 < 0.0:
			return _err("缓和曲线长 l0 不能为负")
		return _err("缓和曲线过长：2β0=%.4f° ≥ 转角 α=%.4f°，圆曲线段长非正，请减小 l0 或增大 R" % [rad_to_deg(2.0 * l0 / (2.0 * r)), adeg])
	var value := {
		"beta0_deg": el["beta0_deg"],
		"p_m": el["p_m"],
		"m_m": el["m_m"],
		"t_m": el["t_m"],
		"l_m": el["l_m"],
		"l_circ_m": el["l_circ_m"],
		"e_m": el["e_m"],
		"q_m": el["q_m"],
		"alpha_deg": adeg,
		"r_m": r,
		"l0_m": l0,
	}
	if el.has("x0_m"):
		value["x0_m"] = el["x0_m"]
		value["y0_m"] = el["y0_m"]
	var steps := [
		{
			"title": "1. 缓和曲线角 β0",
			"formula": "β0 = l0/(2R)（rad）",
			"substitution": "β0 = %.4f/(2×%.4f) = %.8f rad" % [l0, r, el["beta0_rad"]],
			"result": "%.7f°" % el["beta0_deg"],
		},
		{
			"title": "2. 内移值 p 与切线增长值 m",
			"formula": "p = l0²/(24R) − l0⁴/(2688R³)；m = l0/2 − l0³/(240R²)",
			"substitution": "p = %.4f²/(24×%.4f) − %.4f⁴/(2688×%.4f³)；m = %.4f/2 − %.4f³/(240×%.4f²)" % [l0, r, l0, r, l0, l0, r],
			"result": "p = %.4f m，m = %.4f m" % [el["p_m"], el["m_m"]],
		},
		{
			"title": "3. 切线长 T 与曲线长 L",
			"formula": "T = (R+p)·tan(α/2) + m；L = R·α(rad) + l0",
			"substitution": "T = (%.4f+%.4f)×tan(%s/2) + %.4f；L = %.4f×%.8f + %.4f" % [r, el["p_m"], _deg_str(adeg), el["m_m"], r, alpha_rad, l0],
			"result": "T = %.4f m，L = %.4f m（圆曲线段 %.4f m）" % [el["t_m"], el["l_m"], el["l_circ_m"]],
		},
		{
			"title": "4. 外距 E 与切曲差 q",
			"formula": "E = (R+p)/cos(α/2) − R；q = 2T − L",
			"substitution": "E = (%.4f)/cos(%s/2) − %.4f；q = 2×%.4f − %.4f" % [r + el["p_m"], _deg_str(adeg), r, el["t_m"], el["l_m"]],
			"result": "E = %.4f m，q = %.4f m" % [el["e_m"], el["q_m"]],
		},
	]
	if el.has("x0_m"):
		steps.append({
			"title": "5. 缓和曲线终点坐标 x0、y0",
			"formula": "x0 = l0 − l0³/(40R²) + l0⁵/(3456R⁴)；y0 = l0²/(6R) − l0⁴/(336R³) + l0⁶/(42240R⁵)",
			"substitution": "代入 l0=%.4f，R=%.4f" % [l0, r],
			"result": "x0 = %.4f m，y0 = %.4f m（y 指向曲线一侧）" % [el["x0_m"], el["y0_m"]],
		})
	var main_names := ["ZH", "HY", "QZ", "YZ", "HZ"] if l0 > 0.0 else ["ZY", "QZ", "YZ"]
	if not is_nan(jd):
		var ch := main_chains(jd, el["t_m"], el["l_m"], l0)
		if ch.size() == main_names.size():
			var ch_txt := PackedStringArray()
			for i in ch.size():
				value[main_names[i].to_lower() + "_m"] = ch[i]
				ch_txt.append("%s=%s" % [main_names[i], _chain_str(ch[i])])
			steps.append({
				"title": "6. 主点里程",
				"formula": "ZH = JD − T；HY = ZH + l0；QZ = ZH + L/2；YZ = ZH + L − l0；HZ = ZH + L" if l0 > 0.0 \
						else "ZY = JD − T；QZ = ZY + L/2；YZ = ZY + L",
				"substitution": "JD = %s，T = %.4f m，L = %.4f m" % [_chain_str(jd), el["t_m"], el["l_m"]],
				"result": "，".join(ch_txt),
			})
	return {"ok": true, "value": value, "steps": steps,
			"formula": "对称基本型曲线要素（直—缓—圆—缓—直）；l0=0 时为纯圆曲线。注意：T/L/E 均以交点转角 α 定义，主点里程由 JD − T 推算",
			"error": ""}

# ---------- 内部工具 ----------

static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String:
		var t := String(v).strip_edges()
		if t.is_valid_float():
			return t.to_float()
	return NAN

static func _deg_str(d: float) -> String:
	return "%.4f°" % d

## 里程文本：12345.678 → "K12+345.678"
static func _chain_str(c: float) -> String:
	if not is_finite(c):
		return "—"
	var k := int(floorf(c / 1000.0))
	var rest := c - k * 1000.0
	return "K%d+%08.3f" % [k, rest]

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
