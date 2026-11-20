# core/earthwork/grid_volume.gd —— GK-M7-10 方格网法土方 E1
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M7 / §5）：
#   - 方格网法：网格 rows×cols，格网边长 a；每格四角施工高度
#       h = 地面高程 − 设计高程（h>0 挖方 / h<0 填方）；
#     每格填/挖体积 = a² × Σ(角点 h 的正部或负部)/4（角点施工高度代数和的 1/4 × 面积）；
#     逐格累计填方、挖方与净值；含正负号混合格时按四角代数和分列（教学口径，
#     不做零线内分割——零线法精度差异在 formula 尾注声明）；
#   - 权威向量【构造·本会话】：20×20 格、四角 (1.0, 2.0, 1.5, 0.5)、设计高程 0 → V=500.0 m³；
#   - 校验失败 ok=false + 中文 error（网格行列一致、cell_size>0、数值合法）。
class_name GKGridVolume
extends RefCounted

## 纯核：单格填挖体积 [fill_m3, cut_m3]（均取正数；h>0 挖、h<0 填）。非法返回空。
static func cell_volume(a: float, h1: float, h2: float, h3: float, h4: float) -> PackedFloat64Array:
	if not (is_finite(a) and is_finite(h1) and is_finite(h2) and is_finite(h3) and is_finite(h4)) or a <= 0.0:
		return PackedFloat64Array()
	var fill := 0.0
	var cut := 0.0
	for h in [h1, h2, h3, h4]:
		if h > 0.0:
			cut += h
		else:
			fill += absf(h)
	var area := a * a
	return PackedFloat64Array([area * fill / 4.0, area * cut / 4.0])

## E1 协议入口。p = { design_elev_m(默认0), cell_size_m, grid: [[elev, ...], ...] }
## value = { fill_m3, cut_m3, net_m3, rows, cols, cells, cell_area_m2, zero_cells_m2(混合格面积) }
static func forward(p: Dictionary) -> Dictionary:
	var a := _num(p.get("cell_size_m", NAN))
	var zd := _num(p.get("design_elev_m", 0.0)) if p.has("design_elev_m") else 0.0
	if is_nan(a) or a <= 0.0:
		return _err("cell_size_m 须为正数格网边长（m）")
	if is_nan(zd):
		return _err("design_elev_m 须为数字设计高程（m）")
	var grid_in: Variant = p.get("grid", [])
	if not (grid_in is Array) or (grid_in as Array).size() < 2:
		return _err("grid 须为 ≥2 行的二维数组（每行为一行格网点高程）")
	var rows: Array = grid_in as Array
	var cols := -1
	var grid := []
	for r in rows:
		if not (r is Array):
			return _err("grid 每行须为数组（格网点地面高程，m）")
		if cols < 0:
			cols = (r as Array).size()
		elif (r as Array).size() != cols:
			return _err("grid 各行列数不一致（首行 %d 列，后续行 %d 列）" % [cols, (r as Array).size()])
		var row := []
		for v in r as Array:
			var vf := _num(v)
			if is_nan(vf):
				return _err("grid 含非数字高程：%s" % str(v))
			row.append(vf)
		if cols < 2:
			return _err("grid 每行至少 2 个格网点（须构成方格）")
		grid.append(row)
	var fill_sum := 0.0
	var cut_sum := 0.0
	var mixed_area := 0.0
	var cells := 0
	var sample_cell := ""
	for i in range(grid.size() - 1):
		for j in range(cols - 1):
			var h1: float = grid[i][j] - zd
			var h2: float = grid[i][j + 1] - zd
			var h3: float = grid[i + 1][j] - zd
			var h4: float = grid[i + 1][j + 1] - zd
			var cv := cell_volume(a, h1, h2, h3, h4)
			if cv.is_empty():
				return _err("方格体积计算失败（内部错误）")
			fill_sum += cv[0]
			cut_sum += cv[1]
			cells += 1
			var signs := [h1, h2, h3, h4]
			var has_pos := false
			var has_neg := false
			for h in signs:
				if h > 0.0:
					has_pos = true
				elif h < 0.0:
					has_neg = true
			if has_pos and has_neg:
				mixed_area += a * a
			if sample_cell == "" and i == 0 and j == 0:
				sample_cell = "%.4f + %.4f + %.4f + %.4f = %.4f（h 代数和）" % [h1, h2, h3, h4, h1 + h2 + h3 + h4]
	return {"ok": true, "value": {
				"fill_m3": fill_sum,
				"cut_m3": cut_sum,
				"net_m3": fill_sum - cut_sum,
				"rows": grid.size(),
				"cols": cols,
				"cells": cells,
				"cell_area_m2": a * a,
				"total_area_m2": a * a * cells,
				"mixed_cells_area_m2": mixed_area,
			},
			"steps": [
				{"title": "1. 施工高度（地面−设计）",
					"formula": "h = 地面高程 − 设计高程（h>0 挖方，h<0 填方）",
					"substitution": "设计高程 %.4f m，格网 %d×%d，边长 %.4f m" % [zd, grid.size(), cols, a],
					"result": "首格四角：%s" % sample_cell},
				{"title": "2. 逐格体积累计",
					"formula": "V格 = a² × Σ(四角 h 正部)/4（挖）+ a² × Σ(四角 |h 负部|)/4（填）",
					"substitution": "共 %d 格，单格面积 %.4f m²" % [cells, a * a],
					"result": "挖方 %.4f m³，填方 %.4f m³，净量（填−挖）%.4f m³" % [cut_sum, fill_sum, fill_sum - cut_sum]},
			],
			"formula": "方格网法：V = a²·Σh/4（四角施工高度代数和的 1/4 × 面积），填挖分列累计；混合符号格按角点代数和分列（未做零线内分割，教学口径）；净值 = 填方 − 挖方",
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
