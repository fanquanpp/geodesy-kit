# core/cogo/area_tools.gd —— GK-M5：多边形面积（B6，鞋带公式）与亩/公顷/英亩换算
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M5 / §5 协议）：
#   - 纯静态函数、零引擎依赖；鞋带公式（Surveyor's formula）：
#     S = ½·Σ(x_i·y_{i+1} − x_{i+1}·y_i)，顶点按顺序闭合；结果取绝对值（面积恒正）；
#   - 单位定义为精确值（不引入未实现模块的常数，源注释注明）：
#     1 亩 = 2000/3 m²（定义）、1 公顷 = 10000 m²、1 英亩 = 4046.8564224 m²（国际英尺定义精确值）；
#   - 顶点输入接受 Array（元素为 {x,y} 字典或 [x,y] 数组）或字符串（"x,y" 用 ; / 换行分隔）；
#   - 每个计算入口统一返回 §5 协议 {ok, value, steps, formula, error}。
class_name GKAreaTools
extends RefCounted

const MU_M2 := 2000.0 / 3.0      # 1 亩 = 2000/3 m²（中国市制定义）
const HA_M2 := 10000.0           # 1 公顷 = 10000 m²（定义）
const ACRE_M2 := 4046.8564224    # 1 英亩 = 4046.8564224 m²（1 ft=0.3048 m 定义的精确值）

## 解析顶点字符串 → Array[Dictionary{x,y}]。支持 "x,y" 以 ";" 或换行分隔，
## 逗号接受半角/全角；单段无逗号时按 "x y" 空格分隔。非法返回 []。
static func parse_points(text: String) -> Array:
	var t := text.strip_edges().replace("，", ",").replace("；", ";").replace("\r", "")
	if t.is_empty():
		return []
	var chunks := t.split(";", false)
	if chunks.size() == 1 and "\n" in t:
		chunks = t.split("\n", false)
	var pts := []
	for c: String in chunks:
		var s := c.strip_edges()
		if s.is_empty():
			continue
		var xy: PackedStringArray
		if "," in s:
			xy = s.split(",", false)
		else:
			xy = s.split(" ", false)
		if xy.size() != 2:
			return []  # 残段（缺逗号/空格或多余数字）
		var sx := xy[0].strip_edges()
		var sy := xy[1].strip_edges()
		if not sx.is_valid_float() or not sy.is_valid_float():
			return []
		pts.append({"x": sx.to_float(), "y": sy.to_float()})
	return pts

## 归一化顶点输入（Array 或 String）→ Array[Dictionary{x,y}]；非法返回 []。
static func normalize_points(points: Variant) -> Array:
	if points is String:
		return parse_points(String(points))
	if not (points is Array):
		return []
	var pts := []
	for v: Variant in points:
		if v is Dictionary and v.has("x") and v.has("y"):
			var vx: Variant = v["x"]
			var vy: Variant = v["y"]
			if not ((vx is float or vx is int) and (vy is float or vy is int)):
				return []
			pts.append({"x": float(vx), "y": float(vy)})
		elif v is Array and (v as Array).size() == 2:
			var vx2: Variant = v[0]
			var vy2: Variant = v[1]
			if not ((vx2 is float or vx2 is int) and (vy2 is float or vy2 is int)):
				return []
			pts.append({"x": float(vx2), "y": float(vy2)})
		else:
			return []
	return pts

## 鞋带公式原语。pts 至少 3 个不重复顶点；返回 {signed, area, perimeter, n}；不合法 → {}。
static func shoelace(pts: Array) -> Dictionary:
	if pts.size() < 3:
		return {}
	var n := pts.size()
	var s := 0.0
	var perimeter := 0.0
	for i in n:
		var a: Dictionary = pts[i]
		var b: Dictionary = pts[(i + 1) % n]
		var ax: float = a["x"]
		var ay: float = a["y"]
		var bx: float = b["x"]
		var by: float = b["y"]
		if not (is_finite(ax) and is_finite(ay) and is_finite(bx) and is_finite(by)):
			return {}
		s += ax * by - bx * ay
		var dx := bx - ax
		var dy := by - ay
		perimeter += sqrt(dx * dx + dy * dy)
	var signed := s / 2.0
	return {"signed": signed, "area": absf(signed), "perimeter": perimeter, "n": n}

## B6 多边形面积与单位换算。输入：{points: String 或 Array}。
static func polygon_area(p: Dictionary) -> Dictionary:
	if not p.has("points"):
		return _fail("缺少输入项「顶点坐标」（格式：100,100;500,120;520,480;120,500）")
	var pts := normalize_points(p["points"])
	if pts.is_empty():
		return _fail("顶点坐标不合法：请按 100,100;500,120;… 格式逐点输入（至少 3 个顶点，逗号分隔 xy，分号分隔点）")
	var r := shoelace(pts)
	if r.is_empty():
		return _fail("顶点坐标不合法（至少 3 个顶点且坐标为有限数值）")
	# 顶点重合/退化检查：面积为 0 提示（不判失败，可能确为共线点列）
	var area: float = r["area"]
	var signed: float = r["signed"]
	var n: int = r["n"]
	var steps := [
		_step("1. 鞋带公式逐边求和", "Σ = Σ(x_i·y_{i+1} − x_{i+1}·y_i)，顶点按顺序闭合",
			"共 %d 个顶点，Σ = %s" % [n, _f(2.0 * signed, 6)],
			"Σ = %s" % _f(2.0 * signed, 6)),
		_step("2. 面积（取绝对值）", "S = ½·|Σ|",
			"S = ½·|%s|" % _f(2.0 * signed, 6),
			"S = %s m²" % _f(area, 4)),
		_step("3. 单位换算", "亩 = S×3/2000；公顷 = S/10000；英亩 = S/4046.8564224",
			"亩 = %s×3/2000；公顷 = %s/10000；英亩 = %s/4046.8564224" % [_f(area, 4), _f(area, 4), _f(area, 4)],
			"%s 亩 = %s 公顷 = %s 英亩" % [_f(area * 3.0 / 2000.0, 6), _f(area / 10000.0, 6), _f(area / ACRE_M2, 6)]),
	]
	if area < 1e-9:
		steps.append(_step("检核提示", "面积 ≈ 0 的几何含义",
			"S = %s m²" % _f(area, 6),
			"顶点可能共线或有重复点，请检查顶点顺序与坐标"))
	return {
		"ok": true,
		"value": {
			"area_m2": area,
			"area_signed_m2": signed,
			"area_mu": area * 3.0 / 2000.0,
			"area_ha": area / 10000.0,
			"area_acre": area / ACRE_M2,
			"perimeter_m": r["perimeter"],
			"n_vertices": n,
		},
		"steps": steps,
		"formula": "鞋带公式（测量面积）：S = ½·Σ(x_i·y_{i+1} − x_{i+1}·y_i)。"
			+ "单位定义：1 亩 = 2000/3 m²，1 公顷 = 10000 m²，1 英亩 = 4046.8564224 m²。顶点顺序（顺/逆时针）只影响正负号，面积取绝对值。",
		"error": "",
	}

# ---------- 协议小工具 ----------

static func _step(title: String, formula: String, substitution: String, result: String) -> Dictionary:
	return {"title": title, "formula": formula, "substitution": substitution, "result": result}

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}

static func _f(v: float, n := 4) -> String:
	var fmt := "%." + str(n) + "f"
	return fmt % v
