# core/astro/curvature_refraction.gd —— GK-M8-5（F1）地球曲率与大气折光（球气差）
#
# 口径（ARCHITECTURE.md §4 GK-M8 F1）：
#   地球曲率差   c₁ = D²/(2R)                 —— 水平距离 D 上的地球弯曲改正
#   大气折光差   r  = k·D²/(2R)               —— 折光使视线弯向地面，读数减小
#   球气差综合   f  = (1−k)·D²/(2R) = c₁ − r  —— 三角高程"两差改正"
#   折光系数 k 与地区气象有关，常用 0.13/0.14（本模块默认 0.14，可配）；
#   k=0.14 时 f = 0.43·D²/R（D 以 km、f 以 m 的教材速算式同源）。
#   平均曲率半径 R 默认取 WGS84 平均半径 R₁ = (2a+b)/3 = 6371008.7714 m（与 M8-8 GIS 口径一致）。
#
# 设计约定同 core/astro/solar.gd 头注。
class_name GKCurvRefr
extends RefCounted

const DEFAULT_R_M := 6371008.7714    # WGS84 平均半径 R1 = (2a+b)/3
const DEFAULT_K := 0.14              # 大气折光系数（常用 0.13/0.14，可配）

## 球气差各分量（§5 协议）
## p: {D_m 水平距离, k 可选默认 0.14, R_m 可选默认 6371008.7714}
static func correction(p: Dictionary) -> Dictionary:
	var d := float(p.get("D_m", NAN))
	var k := float(p.get("k", DEFAULT_K))
	var r := float(p.get("R_m", DEFAULT_R_M))
	if is_nan(d) or d <= 0.0 or d > 300000.0:
		return _err("水平距离 D 非法：应为 0 < D ≤ 300000 m")
	if is_nan(k) or k < 0.0 or k > 1.0:
		return _err("折光系数 k 非法：应在 [0, 1]（常用 0.13/0.14）")
	if is_nan(r) or r <= 0.0:
		return _err("曲率半径 R 非法：应为正（默认平均半径 6371008.7714 m）")
	var curv := d * d / (2.0 * r)
	var refr := k * curv
	var f := curv - refr
	var value := {
		"curv_m": curv,     # 地球曲率差（正：使高差偏小，需加上）
		"refr_m": refr,     # 大气折光差
		"f_m": f,           # 球气差综合改正（两差改正，三角高程用）
		"k": k,
		"R_m": r,
	}
	var steps := [
		{"title": "1. 地球曲率差",
			"formula": "c₁ = D²/(2R)",
			"substitution": "%.1f²/(2×%.1f)" % [d, r],
			"result": "%.6f m（≈ %.2f mm）" % [curv, curv * 1000.0]},
		{"title": "2. 大气折光差",
			"formula": "r = k·D²/(2R)，k = %.2f" % k,
			"substitution": "%.2f×%.6f" % [k, curv],
			"result": "%.6f m" % refr},
		{"title": "3. 球气差综合改正（两差改正）",
			"formula": "f = (1−k)·D²/(2R) = c₁ − r",
			"substitution": "%.6f − %.6f" % [curv, refr],
			"result": "%.6f m" % f},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "球气差 f=(1−k)D²/(2R)，k=%.2f（常用 0.13/0.14 可配），R=平均半径 %.1f m" % [k, r],
			"error": ""}

## 三角高程单向观测高差（§5 协议）
## h = D·tanα + (1−k)D²/(2R) + i − v
## p: {D_m, alpha_deg 竖直角, i_m 仪器高, v_m 目标高/棱镜高, k/R 可选}
static func trig_height(p: Dictionary) -> Dictionary:
	var d := float(p.get("D_m", NAN))
	var alpha := float(p.get("alpha_deg", NAN))
	var i := float(p.get("i_m", 0.0))
	var v := float(p.get("v_m", 0.0))
	var k := float(p.get("k", DEFAULT_K))
	var r := float(p.get("R_m", DEFAULT_R_M))
	if is_nan(d) or d <= 0.0 or d > 300000.0:
		return _err("水平距离 D 非法：应为 0 < D ≤ 300000 m")
	if is_nan(alpha) or absf(alpha) >= 90.0:
		return _err("竖直角 α 非法：|α| 应 < 90°（仰角为正）")
	if is_nan(i) or is_nan(v) or i < 0.0 or v < 0.0:
		return _err("仪器高/目标高非法：应为非负米数")
	if is_nan(k) or k < 0.0 or k > 1.0:
		return _err("折光系数 k 非法：应在 [0, 1]")
	var f := (1.0 - k) * d * d / (2.0 * r)
	var geometric := d * tan(deg_to_rad(alpha))
	var dh := geometric + f + i - v
	var value := {
		"dh_m": dh,             # 单向观测高差
		"geometric_m": geometric,
		"f_m": f,
		"k": k,
	}
	var steps := [
		{"title": "1. 几何高差",
			"formula": "h几何 = D·tanα",
			"substitution": "%.1f×tan(%.4f°)" % [d, alpha],
			"result": "%.6f m" % geometric},
		{"title": "2. 球气差改正",
			"formula": "f = (1−k)·D²/(2R)，k = %.2f" % k,
			"substitution": "(1−%.2f)×%.1f²/(2×%.1f)" % [k, d, r],
			"result": "%.6f m" % f},
		{"title": "3. 单向观测高差",
			"formula": "h = D·tanα + f + i − v",
			"substitution": "%.6f + %.6f + %.3f − %.3f" % [geometric, f, i, v],
			"result": "%.6f m" % dh},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "三角高程 h = D·tanα + (1−k)D²/(2R) + i − v（单向观测，k=%.2f）" % k,
			"error": ""}

## 弦长与弧长之差：s − D ≈ D³/(24R²)（D 为弦长；教学参考）
static func chord_arc_diff_m(d: float, r: float) -> float:
	if not is_finite(d) or not is_finite(r) or d <= 0.0 or r <= 0.0:
		return NAN
	return d * d * d / (24.0 * r * r)

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
