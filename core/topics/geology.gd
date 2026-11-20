# core/topics/geology.gd —— GK-M8-9（I-地质矿山）
#
# 内容：产状换算（走向↔倾向↔象限式、真倾角↔视倾角）/ 真厚度与视厚度 /
#       钻孔测斜三维坐标（平均角法）/ 线储量与块段储量估算。
#
# 约定（与分派权威构造向量自洽，见 _scripts/gen_vectors_b.py）：
#   - 倾向 = 走向 + 90°（右手法则；走向 045° → 倾向 135°）；
#   - 真厚度 t = L·sinα·sinγ：L 为勘探线（剖面）上矿体顶底板出露的水平宽度，
#     α 为真倾角，γ 为剖面方向与走向的夹角（剖面垂直走向时 γ=90° → t = L·sinα，
#     构造向量：L=100 m、α=30°、γ=90° → t=50.0 m）；
#   - 视倾角：tanβ = tanα·sinγ（γ 为剖面与走向夹角）；
#   - 测斜：天顶角（自铅垂线起算，0°=垂直向下）+ 方位角（北起顺时针），
#     平均角法（平衡正切法）：段内取上下测点角度均值；
#     Δx = L·sin(θ̄)·cos(Ā)，Δy = L·sin(θ̄)·sin(Ā)，Δz(垂深) = L·cos(θ̄)，x 东 y 北；
#   - 线储量 q = S·γ体（t/m）；线金属量 = S·γ体·品位；块段储量 = (S₁+S₂)/2·L·γ体。
#
# 设计约定同 core/astro/solar.gd 头注。
class_name GKGeology
extends RefCounted

## 产状换算（§5 协议）
## p: {strike_deg 走向（0-360，取倾向−90），dip_deg 真倾角（0-90）,
##     profile_az_deg 可选（勘探线/剖面方位角 → 输出视倾角）}
static func attitude(p: Dictionary) -> Dictionary:
	var strike := float(p.get("strike_deg", NAN))
	var dip := float(p.get("dip_deg", NAN))
	if is_nan(strike) or strike < 0.0 or strike >= 360.0:
		return _err("走向非法：应在 [0°, 360°)（倾向 − 90°）")
	if is_nan(dip) or dip < 0.0 or dip > 90.0:
		return _err("倾角非法：应在 [0°, 90°]")
	var dip_dir := fmod(strike + 90.0, 360.0)
	var value := {
		"dip_dir_deg": dip_dir,
		"dip_deg": dip,
		"strike_deg": strike,
	}
	value["strike_text"] = _quadrant_text(strike)
	value["dip_dir_text"] = _quadrant_text(dip_dir)
	var steps := [
		{"title": "1. 走向 → 倾向",
			"formula": "倾向 = (走向 + 90°) mod 360°",
			"substitution": "(%.1f° + 90°) mod 360°" % strike,
			"result": "倾向 = %.1f°（%s）" % [dip_dir, _quadrant_text(dip_dir)]},
		{"title": "2. 走向象限式",
			"formula": "N/E/S/W + 角度（0°/180° 为南北向，90°/270° 为东西向）",
			"substitution": "走向 %.1f°" % strike,
			"result": "走向 %s，倾角 %.1f°" % [_quadrant_text(strike), dip]},
	]
	var formula := "产状表示：走向 %s，倾向 %s∠%.1f°（倾向 = 走向 + 90°）" % [_quadrant_text(strike), _quadrant_text(dip_dir), dip]
	if p.has("profile_az_deg"):
		var paz := float(p.get("profile_az_deg", NAN))
		if is_nan(paz) or paz < 0.0 or paz >= 360.0:
			return _err("剖面方位非法：应在 [0°, 360°)")
		var gamma := _angle_to_strike(paz, strike)
		var app_dip := rad_to_deg(atan(tan(deg_to_rad(dip)) * sin(deg_to_rad(gamma))))
		value["profile_az_deg"] = paz
		value["gamma_deg"] = gamma
		value["apparent_dip_deg"] = app_dip
		steps.append({"title": "3. 视倾角",
			"formula": "tanβ = tanα·sinγ（γ = 剖面方位与走向夹角）",
			"substitution": "γ = %.1f°（剖面 %.1f° 与走向 %.1f°）" % [gamma, paz, strike],
			"result": "视倾角 β = %.4f°" % app_dip})
		formula += "；剖面方位 %.1f° → 视倾角 %.4f°" % [paz, app_dip]
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 真厚度（§5 协议）
## p: {width_m 剖面水平宽度（顶底板出露水平距）, dip_deg 真倾角,
##     profile_az_deg 剖面方位, strike_deg 走向}
static func true_thickness(p: Dictionary) -> Dictionary:
	var width := float(p.get("width_m", NAN))
	var dip := float(p.get("dip_deg", NAN))
	var paz := float(p.get("profile_az_deg", NAN))
	var strike := float(p.get("strike_deg", NAN))
	if is_nan(width) or width <= 0.0:
		return _err("剖面水平宽度非法：应为正（米）")
	if is_nan(dip) or dip <= 0.0 or dip > 90.0:
		return _err("真倾角非法：应在 (0°, 90°]")
	if is_nan(paz) or paz < 0.0 or paz >= 360.0:
		return _err("剖面方位非法：应在 [0°, 360°)")
	if is_nan(strike) or strike < 0.0 or strike >= 360.0:
		return _err("走向非法：应在 [0°, 360°)")
	var gamma := _angle_to_strike(paz, strike)
	var t := width * sin(deg_to_rad(dip)) * sin(deg_to_rad(gamma))
	var vertical := width * tan(deg_to_rad(dip)) * sin(deg_to_rad(gamma))
	var value := {
		"true_thickness_m": t,
		"vertical_thickness_m": vertical,
		"gamma_deg": gamma,
		"horiz_width_m": width,
	}
	var perp := absf(gamma - 90.0) < 1e-9
	var steps := [
		{"title": "1. 剖面与走向夹角 γ",
			"formula": "γ = |剖面方位 − 走向| 归算到 [0°, 90°]",
			"substitution": "|%.1f° − %.1f°| → %.1f°" % [paz, strike, gamma],
			"result": "γ = %.4f°%s" % [gamma, "（垂直走向）" if perp else ""]},
		{"title": "2. 真厚度",
			"formula": "t = L·sinα·sinγ",
			"substitution": "%.1f×sin(%.1f°)×sin(%.1f°)" % [width, dip, gamma],
			"result": "t = %.4f m%s" % [t, "（垂直走向时 t = L·sinα）" if perp else ""]},
	]
	var formula := "真厚度 t = L·sinα·sinγ（L=%.1f m，α=%.1f°，γ=%.1f°）%s" % [width, dip, gamma, "；垂直走向" if perp else "；γ≠90° 时为斜交剖面"]
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 钻孔测斜三维坐标（§5 协议，平均角法）
## p: {collar_x, collar_y, collar_z（孔口坐标，x 东 y 北，z 向上为正）,
##     stations: "depth,zenith_deg,az_deg;..."（天顶角自铅垂线起算，方位角北起顺时针）}
## 返回各测站 (x, y, z, 垂深) 与孔底坐标；天顶角应在 [0°, 90°]
static func borehole(p: Dictionary) -> Dictionary:
	var cx := float(p.get("collar_x", 0.0))
	var cy := float(p.get("collar_y", 0.0))
	var cz := float(p.get("collar_z", 0.0))
	for v in [cx, cy, cz]:
		if not is_finite(v):
			return _err("孔口坐标非法：应为数值（x 东、y 北、z 向上）")
	var st: Variant = _parse_stations(String(p.get("stations", "")))
	if st is String:
		return _err(st)
	var rows: Array = st
	for r: Array in rows:
		if float(r[0]) <= 0.0:
			return _err("测深非法：应 > 0（孔口起算累计深度）")
		if float(r[1]) < 0.0 or float(r[1]) > 90.0:
			return _err("天顶角非法：应在 [0°, 90°]（自铅垂线起算）")
		if float(r[2]) < 0.0 or float(r[2]) >= 360.0:
			return _err("方位角非法：应在 [0°, 360°)")
	# 深度递增检查
	for i in range(rows.size() - 1):
		if float(rows[i + 1][0]) <= float(rows[i][0]):
			return _err("测深必须递增：%s ≤ %s" % [str(rows[i + 1][0]), str(rows[i][0])])
	# 平均角法逐段推算
	var x := cx
	var y := cy
	var z := cz
	var depth_prev := 0.0
	var theta_prev := 0.0
	var az_prev := deg_to_rad(float(rows[0][2]))  # 弧度（段内统一弧度制）
	var value := {"n_stations": rows.size()}
	var lines := []
	var station_values := []
	for r: Array in rows:
		var depth := float(r[0])
		var theta := deg_to_rad(float(r[1]))
		var az := deg_to_rad(float(r[2]))
		var seg := depth - depth_prev
		# 段平均角：起点用上一测点（孔口天顶角 0°，方位取本段方位），终点用本测点
		var th_bar := (theta_prev + theta) / 2.0
		var az_bar := az_prev
		if depth_prev > 0.0:
			az_bar = _az_mean(az_prev, az)
		var dx := seg * sin(th_bar) * cos(az_bar)
		var dy := seg * sin(th_bar) * sin(az_bar)
		var dz := seg * cos(th_bar)
		x += dx
		y += dy
		z -= dz
		lines.append("段 %.1f→%.1f m：θ̄=%.2f°，Ā=%.2f°，Δ=(%.4f, %.4f, %.4f)" % [depth_prev, depth, rad_to_deg(th_bar), rad_to_deg(az_bar), dx, dy, dz])
		station_values.append({"depth": depth, "x": x, "y": y, "z": z})
		value["x_bottom_m"] = x
		value["y_bottom_m"] = y
		value["z_bottom_m"] = z
		value["depth_bottom_m"] = depth
		value["displacement_m"] = sqrt(pow(x - cx, 2.0) + pow(y - cy, 2.0))
		depth_prev = depth
		theta_prev = theta
		az_prev = az
	for i in station_values.size():
		var sv: Dictionary = station_values[i]
		value["station_%d_x" % (i + 1)] = sv["x"]
		value["station_%d_y" % (i + 1)] = sv["y"]
		value["station_%d_z" % (i + 1)] = sv["z"]
	var steps := [
		{"title": "1. 平均角法逐段推算",
			"formula": "Δx = L·sin(θ̄)·cos(Ā)，Δy = L·sin(θ̄)·sin(Ā)，Δz = L·cos(θ̄)（x 东 y 北，z 向上）",
			"substitution": "\n".join(lines),
			"result": "%d 段推算完成（平均角法/平衡正切法）" % rows.size()},
		{"title": "2. 孔底坐标与偏距",
			"formula": "累计 x,y,z；水平偏距 = √(Δx²+Δy²)",
			"substitution": "孔口 (%.3f, %.3f, %.3f)" % [cx, cy, cz],
			"result": "孔底 (%.4f, %.4f, %.4f)，水平偏距 %.4f m" % [x, y, z, float(value["displacement_m"])]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "钻孔测斜三维坐标（平均角法，天顶角+方位角，x 东 y 北 z 向上）",
			"error": ""}

## 线储量 / 块段储量（§5 协议）
## p: {S1_m2 断面矿体面积, S2_m2 可选（相邻断面）, L_m 可选（断面间距）,
##     density_t_m3 矿石体重, grade_percent 品位（%，可选默认 0）}
## S2+L 同时给出 → 块段储量（截面积平均法）；否则输出线储量（每米剖面储量）
static func reserve(p: Dictionary) -> Dictionary:
	var s1 := float(p.get("S1_m2", NAN))
	var s2 := float(p.get("S2_m2", NAN))
	var len_m := float(p.get("L_m", NAN))
	var density := float(p.get("density_t_m3", NAN))
	var grade := float(p.get("grade_percent", 0.0))
	if is_nan(s1) or s1 <= 0.0:
		return _err("断面矿体面积 S₁ 非法：应为正（m²）")
	if is_nan(density) or density <= 0.0:
		return _err("矿石体重 γ 非法：应为正（t/m³）")
	if is_nan(grade) or grade < 0.0 or grade > 100.0:
		return _err("品位非法：应在 [0, 100]（%）")
	var has_block := is_finite(s2) and is_finite(len_m)
	if has_block and (s2 <= 0.0 or len_m <= 0.0):
		return _err("块段参数非法：相邻断面面积 S₂ 与断面间距 L 均应为正")
	var value := {}
	var steps := []
	var formula := ""
	if has_block:
		var volume := (s1 + s2) / 2.0 * len_m
		var ore := volume * density
		var metal := ore * grade / 100.0
		value["volume_m3"] = volume
		value["ore_t"] = ore
		value["metal_t"] = metal
		steps.append({"title": "1. 块段体积（相邻断面平均）",
			"formula": "V = (S₁+S₂)/2 × L",
			"substitution": "(%.2f+%.2f)/2×%.2f" % [s1, s2, len_m],
			"result": "V = %.4f m³" % volume})
		steps.append({"title": "2. 矿石量与金属量",
			"formula": "Q = V·γ；P = Q·品位（%）",
			"substitution": "γ = %.3f t/m³，品位 = %.2f%%" % [density, grade],
			"result": "矿石量 %.3f t，金属量 %.3f t" % [ore, metal]})
		formula = "块段储量（断面平均法）：V=(S₁+S₂)L/2，Q=V·γ，P=Q·品位"
	else:
		var q_line := s1 * density
		var metal_line := q_line * grade / 100.0
		value["ore_t_per_m"] = q_line
		value["metal_t_per_m"] = metal_line
		steps.append({"title": "1. 线储量（每米剖面储量）",
			"formula": "q = S₁·γ（t/m）",
			"substitution": "%.2f×%.3f" % [s1, density],
			"result": "线储量 %.4f t/m" % q_line})
		steps.append({"title": "2. 线金属量",
			"formula": "p = q·品位（%）",
			"substitution": "%.4f×%.2f%%" % [q_line, grade],
			"result": "线金属量 %.4f t/m" % metal_line})
		formula = "线储量 q = S·γ（断面面积 × 体重）；提供 S₂ 与 L 时自动改算块段储量"
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

# ---------- 内部工具 ----------

## 剖面方位与走向的夹角，归算到 [0°, 90°]（走向有向线 ±180° 对称）
static func _angle_to_strike(profile_az: float, strike: float) -> float:
	var g := absf(fmod(profile_az - strike, 180.0))
	if g > 90.0:
		g = 180.0 - g
	return g

## 方位角均值（弧度制；走最短弧差，跨 0°/360° 正确）
static func _az_mean(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	elif d < -PI:
		d += TAU
	return fmod(a + d / 2.0 + TAU, TAU)

## 象限式文本：045° → N45°E；135° → S45°E；310° → N50°W
static func _quadrant_text(az: float) -> String:
	var a := fmod(fmod(az, 360.0) + 360.0, 360.0)
	if a < 1e-9 or absf(a - 360.0) < 1e-9:
		return "N0°E"
	if absf(a - 90.0) < 1e-9:
		return "N90°E"
	if absf(a - 180.0) < 1e-9:
		return "S0°E"
	if absf(a - 270.0) < 1e-9:
		return "N90°W"
	if a < 90.0:
		return "N%.1f°E" % a
	if a < 180.0:
		return "S%.1f°E" % (180.0 - a)
	if a < 270.0:
		return "S%.1f°W" % (a - 180.0)
	return "N%.1f°W" % (360.0 - a)

## 解析 "depth,zenith,az;..."
static func _parse_stations(text: String) -> Variant:
	var t := text.strip_edges().replace("，", ",").replace("；", ";").replace(" ", "").replace("\n", "").replace("\r", "")
	if t.is_empty():
		return "测斜数据为空：格式应为 depth,zenith_deg,az_deg;…（测深,天顶角,方位角）"
	var recs := t.split(";", false)
	if recs.is_empty():
		return "测斜数据为空"
	var out := []
	for rec in recs:
		var parts := rec.split(",")
		if parts.size() != 3:
			return "测斜记录格式错误（应为 测深,天顶角,方位角）：%s" % rec
		for s in parts:
			if not s.is_valid_float():
				return "测斜记录含非数值字段：%s" % rec
		out.append([rec.split(",")[0].to_float(), rec.split(",")[1].to_float(), rec.split(",")[2].to_float()])
	return out

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
