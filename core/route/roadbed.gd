# core/route/roadbed.gd —— GK-M7-9 路基横断面：开挖口/坡脚放样 D7
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M7 / §5）：
#   - 横断面模板：路槽边缘高程 = 设计中心高程 − i·b/100（路拱横坡 i 两侧对称外降）；
#   - 填方（路堤）：边缘点向外下放边坡 1:m —— z(t) = z_edge − t/m，水平距 = b + t；
#   - 挖方（路堑）：边缘点向外上开挖边坡 1:n —— z(t) = z_edge + t/n，水平距 = b + t
#     （教学简化模板：不含碎落台/边沟，需时可增大 b 等效计入）；
#   - 逐侧判性：边缘点设计高程 vs 地面高程定填/挖；坡脚 = 边坡线与地面折线（分段线性）
#     的第一个外向交点，逐段精确解线性方程（无迭代近似）；
#   - 输入地面线 = [{offset_m(右正左负), elev_m}, ...]（按 offset 升序）；
#   - 校验失败 ok=false + 中文 error（地面线未覆盖边坡范围、坡率非法等）。
class_name GKRoadbed
extends RefCounted

## D7 协议入口。p = {
##   design_elev_m, half_width_m, cross_slope_pct=0, fill_slope_ratio(1:m),
##   cut_slope_ratio(1:n), ground:[{offset_m, elev_m},...] }
## value = { edge_l/edge_r（边缘点）, foot_l/foot_r（坡脚/开挖口）,
##           center_mode（"路堤填方"/"路堑挖方"）, ... }
static func forward(p: Dictionary) -> Dictionary:
	var zd := _num(p.get("design_elev_m", NAN))
	var b := _num(p.get("half_width_m", NAN))
	var i_pct := _num(p.get("cross_slope_pct", 0.0)) if p.has("cross_slope_pct") else 0.0
	var m_fill := _num(p.get("fill_slope_ratio", NAN))
	var n_cut := _num(p.get("cut_slope_ratio", NAN))
	if is_nan(zd) or is_nan(b) or is_nan(m_fill) or is_nan(n_cut) or is_nan(i_pct):
		return _err("输入缺失：design_elev_m、half_width_m、fill_slope_ratio、cut_slope_ratio（cross_slope_pct 可选）均须为数字")
	if b <= 0.0:
		return _err("路基半宽 half_width_m 必须大于 0")
	if m_fill <= 0.0:
		return _err("填方坡率 1:m 中 m 必须大于 0（如 1:1.5 输入 1.5）")
	if n_cut <= 0.0:
		return _err("挖方坡率 1:n 中 n 必须大于 0（如 1:0.75 输入 0.75）")
	if i_pct < 0.0:
		return _err("路拱横坡 cross_slope_pct 不能为负")
	var ground_in: Variant = p.get("ground", [])
	if not (ground_in is Array) or (ground_in as Array).size() < 2:
		return _err("ground 须为 ≥2 点的地面线数组：[{offset_m, elev_m}, ...]（offset 右正左负，升序）")
	var ground := []
	for g in ground_in as Array:
		if not (g is Dictionary):
			return _err("ground 元素须为对象 {offset_m, elev_m}")
		var off := _num((g as Dictionary).get("offset_m", NAN))
		var zz := _num((g as Dictionary).get("elev_m", NAN))
		if is_nan(off) or is_nan(zz):
			return _err("地面线点 offset_m/elev_m 须为数字")
		ground.append({"off": off, "z": zz})
	for i in range(1, ground.size()):
		if float(ground[i]["off"]) <= float(ground[i - 1]["off"]):
			return _err("地面线 offset_m 须严格递增（右正左负），第 %d 点顺序错误" % (i + 1))
	var z_edge := zd - i_pct * b / 100.0  # 路槽边缘高程（两侧对称外降）
	var sides := [[1.0, "右"], [-1.0, "左"]]
	var side_rows := []
	var steps := [{
		"title": "1. 路槽边缘高程",
		"formula": "z_edge = 设计中心高程 − i·b/100",
		"substitution": "z_d=%.4f，i=%.4f%%，b=%.4f m" % [zd, i_pct, b],
		"result": "z_edge = %.4f m（两侧对称）" % z_edge,
	}]
	var all_ok := true
	for side in sides:
		var s: float = side[0]
		var name_cn: String = side[1]
		var r := _solve_side(s, b, z_edge, m_fill, n_cut, ground)
		if r.is_empty():
			all_ok = false
			side_rows.append({"side": name_cn, "error": "地面线数据不足或坡线无交点"})
			steps.append({
				"title": "%d. %s侧坡脚解算" % [side_rows.size() + 1, name_cn],
				"formula": "边坡线与地面折线求交",
				"substitution": "%s侧边缘点 (%.4f·b, %.4f)" % [name_cn, s, z_edge],
				"result": "失败：地面线未覆盖边坡范围或坡率与地面线无交点",
			})
			continue
		side_rows.append(r)
		steps.append({
			"title": "%d. %s侧判定与坡脚解算" % [side_rows.size() + 1, name_cn],
			"formula": "填方：z(t)=z_edge−t/m；挖方：z(t)=z_edge+t/n；与地面折线逐段解线性方程",
			"substitution": "%s侧边缘高程 %.4f，地面边缘高程 %.4f → %s（坡率 1:%s）" % [name_cn, z_edge, float(r["edge_ground_elev_m"]), String(r["mode"]), String(r["slope_txt"])],
			"result": "%s：坡脚距中桩 %.4f m（桩号距），地面高程 %.4f m，边缘填挖高 %.4f m" % [String(r["mode"]), float(r["foot_dist_m"]), float(r["foot_ground_elev_m"]), float(r["edge_diff_m"])],
		})
	var center_mode := "路堤填方" if zd >= _ground_at(ground, 0.0) else "路堑挖方"
	if not all_ok:
		return _err("坡脚解算失败：" + String(side_rows[side_rows.size() - 1].get("error", "地面线不足")))
	var value := {
		"design_elev_m": zd,
		"edge_elev_m": z_edge,
		"center_mode": center_mode,
		"fill_slope_txt": "1:%s" % String.num(m_fill, 4),
		"cut_slope_txt": "1:%s" % String.num(n_cut, 4),
	}
	for row: Dictionary in side_rows:
		var tag := "right" if String(row["side"]) == "右" else "left"
		value["edge_%s_elev_m" % tag] = z_edge
		value["foot_%s_dist_m" % tag] = float(row["foot_dist_m"])
		value["foot_%s_elev_m" % tag] = float(row["foot_ground_elev_m"])
		value["foot_%s_offset_m" % tag] = float(row["foot_offset_m"])
		value["mode_%s" % tag] = String(row["mode"])
		value["slope_%s" % tag] = String(row["slope_txt"])
		value["edge_diff_%s_m" % tag] = float(row["edge_diff_m"])
	return {"ok": true, "value": value, "steps": steps,
			"formula": "横断面模板：路槽边缘外放边坡线（填 1:m 下放 / 挖 1:n 上挖），与地面折线逐段精确求交得坡脚/开挖口；教学简化模板不含边沟与碎落台",
			"error": ""}

# ---------- 内部工具 ----------

## 单侧解算。s=+1 右 / −1 左。返回行字典或空（失败）。
## 思路：取该侧地面折线（x=|偏距| 向外递增），自路槽边缘 x=b 起逐段与边坡线解
## 线性方程，取第一个变号点（d = 坡线高程 − 地面高程）。
static func _solve_side(s: float, b: float, z_edge: float, m_fill: float, n_cut: float, ground: Array) -> Dictionary:
	var z_g_edge := _ground_at(ground, s * b)
	if is_nan(z_g_edge):
		return {}
	var is_fill := z_edge >= z_g_edge
	var slope := m_fill if is_fill else n_cut
	var pts := []
	for g in ground:
		var x := s * float(g["off"])
		if x >= -1e-12:
			pts.append([maxf(x, 0.0), float(g["z"])])
	if pts.size() < 2:
		return {}
	pts.sort_custom(func(u: Array, v: Array) -> bool:
		return float(u[0]) < float(v[0]))
	# 起始段（含 x=b）
	var k0 := -1
	for i in range(pts.size() - 1):
		if float(pts[i][0]) <= b + 1e-12 and float(pts[i + 1][0]) >= b - 1e-12:
			k0 = i
			break
	if k0 < 0:
		return {}
	for i in range(k0, pts.size() - 1):
		var x1 := maxf(float(pts[i][0]), b)
		var x2 := float(pts[i + 1][0])
		if x2 <= x1 + 1e-15:
			continue
		var t1 := x1 - b
		var t2 := x2 - b
		var zs1 := _slope_z(z_edge, is_fill, slope, t1)
		var zs2 := _slope_z(z_edge, is_fill, slope, t2)
		var zg1 := z_g_edge if i == k0 else float(pts[i][1])
		var zg2 := float(pts[i + 1][1])
		var d0 := zs1 - zg1
		var d1 := zs2 - zg2
		var hit := NAN
		if absf(d0) < 1e-12 and i == k0:
			hit = t1  # 边缘即接地：坡脚=边缘
		elif d0 * d1 < 0.0:
			hit = t1 + (t2 - t1) * d0 / (d0 - d1)
		elif absf(d1) < 1e-12 and i > k0:
			hit = t2
		if not is_nan(hit) and hit >= -1e-12:
			var foot_abs := b + hit
			var foot_ground := _ground_at(ground, s * foot_abs)
			if is_nan(foot_ground):
				foot_ground = zg1 + (zg2 - zg1) * (hit - t1) / maxf(t2 - t1, 1e-15)
			return {
				"side": "右" if s > 0.0 else "左",
				"mode": "路堤填方" if is_fill else "路堑挖方",
				"slope_txt": ("1:%s" % String.num(m_fill, 4)) if is_fill else ("1:%s" % String.num(n_cut, 4)),
				"foot_offset_m": s * foot_abs,
				"foot_dist_m": foot_abs,
				"foot_ground_elev_m": foot_ground,
				"edge_ground_elev_m": z_g_edge,
				"edge_diff_m": z_edge - z_g_edge,
			}
	return {}

## 边坡线高程：填方下放 z(t)=z_edge−t/m；挖方上挖 z(t)=z_edge+t/n
static func _slope_z(z_edge: float, is_fill: bool, slope: float, t: float) -> float:
	return z_edge - t / slope if is_fill else z_edge + t / slope

## 点列（[x, z]，x 升序）在 x 处线性内插
static func _interp_x(pts: Array, x: float) -> float:
	for i in range(pts.size() - 1):
		var x1: float = pts[i][0]
		var x2: float = pts[i + 1][0]
		if x >= x1 and x <= x2:
			if x2 == x1:
				return float(pts[i][1])
			var t := (x - x1) / (x2 - x1)
			return float(pts[i][1]) * (1.0 - t) + float(pts[i + 1][1]) * t
	return float(pts[pts.size() - 1][1])

## 地面线在 offset 处的线性内插高程；超出范围返回 NAN
static func _ground_at(ground: Array, off: float) -> float:
	if off < float(ground[0]["off"]) - 1e-12 or off > float(ground[ground.size() - 1]["off"]) + 1e-12:
		return NAN
	for i in range(ground.size() - 1):
		var x1: float = ground[i]["off"]
		var x2: float = ground[i + 1]["off"]
		if off >= x1 and off <= x2:
			if x2 == x1:
				return float(ground[i]["z"])
			var t := (off - x1) / (x2 - x1)
			return float(ground[i]["z"]) * (1.0 - t) + float(ground[i + 1]["z"]) * t
	return float(ground[ground.size() - 1]["z"])

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
