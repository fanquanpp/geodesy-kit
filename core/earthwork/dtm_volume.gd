# core/earthwork/dtm_volume.gd —— GK-M7-12 DTM 法土方 E3（TIN 三棱柱累加）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M7 / §5）：
#   - 三角形三棱柱：设计面（平面 z = z0 + ix·x + iy·y）与 DTM 三角面之间：
#       净体积（精确）：V_tri = 面积 × (h1+h2+h3)/3，h_i = 地面高程 − 设计面高程
#       （h 沿三角形线性 ⇒ 平均高度 = 形心值，公式精确，无论符号是否混合）；
#     填/挖分解（精确）：符号混合时零线把三角形分割为小三角形+四边形，
#       逐块按线性高度场精确积分（顶点在零线上高度为 0，楔形/锥形公式）；
#   - 构造向量（本会话手算+自洽检核）：
#       直角三角形 (0,0)(100,0)(0,100)，设计面 z=0，角点高 (1,2,3) → V=10000 m³（全填侧）；
#       角点高 (3,−1,−2) → 填 2250 / 挖 2250 / 净 0（零线分割解析值）；
#   - 校验失败 ok=false + 中文 error（三角形面积非退化、数值合法）。
class_name GKDTMVolume
extends RefCounted

## 纯核：三角形面积（叉积/2）
static func tri_area(x1: float, y1: float, x2: float, y2: float, x3: float, y3: float) -> float:
	return absf((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) * 0.5

## 纯核：三角形三棱柱净体积（设计平面 via h 场）与填挖分解 [fill, cut, net]。
## h1/h2/h3 = 各角点（地面−设计）高度。退化三角形返回空。
static func tri_volumes(x1: float, y1: float, h1: float, x2: float, y2: float, h2: float,
		x3: float, y3: float, h3: float) -> PackedFloat64Array:
	var area := tri_area(x1, y1, x2, y2, x3, y3)
	if not is_finite(area) or area <= 1e-12:
		return PackedFloat64Array()
	if not (is_finite(h1) and is_finite(h2) and is_finite(h3)):
		return PackedFloat64Array()
	var net := area * (h1 + h2 + h3) / 3.0
	var fill := 0.0
	var cut := 0.0
	var signs := [h1, h2, h3]
	var has_pos := h1 > 0.0 or h2 > 0.0 or h3 > 0.0
	var has_neg := h1 < 0.0 or h2 < 0.0 or h3 < 0.0
	if not (has_pos and has_neg):
		if has_pos:
			fill = net
		elif has_neg:
			cut = -net
		return PackedFloat64Array([fill, cut, net])
	# 符号混合：精确分割。ia 取"与另外两点异号"的顶点（独正或独负），
	# 其余两点 o1/o2 同号；零线与边 (ia,o1)、(ia,o2) 相交于 P、Q。
	var verts := [[x1, y1, h1], [x2, y2, h2], [x3, y3, h3]]
	var pos_idx := []
	var neg_idx := []
	for i in 3:
		if float(verts[i][2]) > 0.0:
			pos_idx.append(i)
		elif float(verts[i][2]) < 0.0:
			neg_idx.append(i)
	var ia := -1
	if pos_idx.size() == 1:
		ia = int(pos_idx[0])
	elif neg_idx.size() == 1:
		ia = int(neg_idx[0])
	else:
		ia = int(pos_idx[0])  # 含 h=0 顶点的退化情形：任取一侧（P/Q 重合于零顶点，公式仍自洽）
	var others := []
	for i in 3:
		if i != ia:
			others.append(i)
	var o1 := int(others[0])
	var o2 := int(others[1])
	var ha: float = verts[ia][2]
	var h1o: float = verts[o1][2]
	var h2o: float = verts[o2][2]
	# P、Q：零线与边 (ia,o1)、(ia,o2) 的交点（ha 与 h_o 异号，比例落在 [0,1]）
	var tab := ha / (ha - h1o)
	var px: float = verts[ia][0] + (verts[o1][0] - verts[ia][0]) * tab
	var py: float = verts[ia][1] + (verts[o1][1] - verts[ia][1]) * tab
	var tac := ha / (ha - h2o)
	var qx: float = verts[ia][0] + (verts[o2][0] - verts[ia][0]) * tac
	var qy: float = verts[ia][1] + (verts[o2][1] - verts[ia][1]) * tac
	# 尖端块：三角形 A-P-Q（线性高度场，顶点 ha，P/Q 为 0）→ 平均高 ha/3
	var area_tip := tri_area(float(verts[ia][0]), float(verts[ia][1]), px, py, qx, qy)
	var v_tip := area_tip * ha / 3.0
	# 基座块：四边形 P-o1-o2-Q = 三角形 P-o1-o2（平均高 (0+h_o1+h_o2)/3）
	#        + 三角形 P-o2-Q（平均高 (0+h_o2+0)/3 = h_o2/3）
	var area_poo := tri_area(px, py, float(verts[o1][0]), float(verts[o1][1]), float(verts[o2][0]), float(verts[o2][1]))
	var area_poq := tri_area(px, py, float(verts[o2][0]), float(verts[o2][1]), qx, qy)
	var v_base := area_poo * (h1o + h2o) / 3.0 + area_poq * h2o / 3.0
	if ha > 0.0:
		fill = v_tip
		cut = -v_base
	else:
		cut = -v_tip
		fill = v_base
	return PackedFloat64Array([fill, cut, net])

## E3 协议入口。p = {
##   design_elev_m 或 plane:{z0, ix, iy}（z = z0 + ix·x + iy·y）,
##   triangles: [{v1:{x_m,y_m,z_m}, v2:{...}, v3:{...}}, ...] }
## value = { fill_m3, cut_m3, net_m3, tri_count, total_area_m2 }
static func forward(p: Dictionary) -> Dictionary:
	var zd := 0.0
	var ix := 0.0
	var iy := 0.0
	if p.has("plane"):
		var pl: Dictionary = p["plane"]
		zd = _num(pl.get("z0", 0.0)) if pl.has("z0") else 0.0
		ix = _num(pl.get("ix", 0.0)) if pl.has("ix") else 0.0
		iy = _num(pl.get("iy", 0.0)) if pl.has("iy") else 0.0
		if is_nan(zd) or is_nan(ix) or is_nan(iy):
			return _err("plane 须为 {z0, ix, iy}（z = z0 + ix·x + iy·y，数值）")
	else:
		zd = _num(p.get("design_elev_m", 0.0)) if p.has("design_elev_m") else 0.0
		if is_nan(zd):
			return _err("design_elev_m 须为数字设计高程（m）")
	var tris_in: Variant = p.get("triangles", [])
	if not (tris_in is Array) or (tris_in as Array).is_empty():
		return _err("triangles 须为非空三角形数组：[{v1:{x_m,y_m,z_m}, v2:{...}, v3:{...}}, ...]")
	var fill_sum := 0.0
	var cut_sum := 0.0
	var net_sum := 0.0
	var area_sum := 0.0
	var rows := PackedStringArray()
	var idx := 0
	for t in tris_in as Array:
		if not (t is Dictionary):
			return _err("triangles 元素须为对象 {v1, v2, v3}，每点 {x_m, y_m, z_m}")
		var vs := []
		for key in ["v1", "v2", "v3"]:
			var vv: Variant = (t as Dictionary).get(key, null)
			if not (vv is Dictionary):
				return _err("三角形 %d 的 %s 须为对象 {x_m, y_m, z_m}" % [idx + 1, key])
			var vx := _num((vv as Dictionary).get("x_m", NAN))
			var vy := _num((vv as Dictionary).get("y_m", NAN))
			var vz := _num((vv as Dictionary).get("z_m", NAN))
			if is_nan(vx) or is_nan(vy) or is_nan(vz):
				return _err("三角形 %d 的 %s 坐标须为数字（x_m/y_m/z_m）" % [idx + 1, key])
			vs.append([vx, vy, vz])
		var h1: float = vs[0][2] - (zd + ix * float(vs[0][0]) + iy * float(vs[0][1]))
		var h2: float = vs[1][2] - (zd + ix * float(vs[1][0]) + iy * float(vs[1][1]))
		var h3: float = vs[2][2] - (zd + ix * float(vs[2][0]) + iy * float(vs[2][1]))
		var tv := tri_volumes(float(vs[0][0]), float(vs[0][1]), h1, float(vs[1][0]), float(vs[1][1]), h2, float(vs[2][0]), float(vs[2][1]), h3)
		if tv.is_empty():
			return _err("三角形 %d 退化（三点共线或面积过小），请检查坐标" % (idx + 1))
		var ar := tri_area(float(vs[0][0]), float(vs[0][1]), float(vs[1][0]), float(vs[1][1]), float(vs[2][0]), float(vs[2][1]))
		fill_sum += tv[0]
		cut_sum += tv[1]
		net_sum += tv[2]
		area_sum += ar
		if idx < 3:
			rows.append("△%d：面积 %.4f m²，净 %.4f m³（填 %.4f / 挖 %.4f）" % [idx + 1, ar, tv[2], tv[0], tv[1]])
		idx += 1
	return {"ok": true, "value": {
				"fill_m3": fill_sum,
				"cut_m3": cut_sum,
				"net_m3": net_sum,
				"tri_count": idx,
				"total_area_m2": area_sum,
			},
			"steps": [
				{"title": "1. 三棱柱逐块体积",
					"formula": "V_tri = 面积 × (h1+h2+h3)/3（h 沿三角形线性，平均高=形心值，公式精确）",
					"substitution": "设计面 z = %.4f + %.4f·x + %.4f·y，共 %d 个三角形" % [zd, ix, iy, idx],
					"result": "；".join(rows) + ("（…共 %d 块）" % idx if idx > 3 else "")},
				{"title": "2. 填挖分解与累计",
					"formula": "符号混合时零线分割为尖端小三角形（平均高 h/3）+ 基座楔形，逐块精确积分",
					"substitution": "逐三角形按角点符号分块",
					"result": "填方 %.4f m³，挖方 %.4f m³，净量 %.4f m³，总面积 %.4f m²" % [fill_sum, cut_sum, net_sum, area_sum]},
			],
			"formula": "DTM 三棱柱法：净体积 V=Σ A·(h1+h2+h3)/3（线性高度场精确）；填挖分解按零线分割（小三角形+楔形）精确积分",
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

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
