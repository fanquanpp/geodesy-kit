# scenes/calculators/adjustment/c5_network.gd —— C5 平面控制网严密平差计算器（测边/测角/边角，间接平差）
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const NW := preload("res://core/adjustment/network.gd")
const AC := preload("res://core/adjustment/accuracy.gd")
const SketchScene := preload("res://scenes/widgets/sketch_panel.tscn")  # GKSketchPanel

const FMT_HINT := """每行一条，空白或逗号分隔，# 开头为注释：
K 名称 x y          已知点（至少 1 个）
U 名称 x0 y0        未知点近似坐标
D 起点 终点 边长 [σ_m]        测边观测（σ 默认 0.01 m）
L 测站 后视 前视 角度° [σ_″]  角度观测（σ 默认 2″；β=α(前视)−α(后视)）"""

func _build_fields() -> void:
	_add_text_area("网形与观测数据", "data", FMT_HINT)
	_add_section("说明")
	var note := Label.new()
	note.text = "严密平差（间接法，单次线性化）：输出平差后坐标、残差、单位权中误差 μ₀ 与各未知点点位中误差 mp。坐标约定 x=东、y=北。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"Muted"
	_inputs_root.add_child(note)

var _sketch: Control  # 网图（GKSketchPanel）：按 K/U 行坐标与 D/L 行观测连线

## 点位连线图挂在公式折叠卡之后；解析成功即按已知点/近似点与观测边连线重绘
func _build_sketch() -> void:
	_sketch = SketchScene.instantiate()
	add_child(_sketch)

## 网形文本 → 米制折线顶点序列：K/U 行收点，D 行按边连线（两顶点一段），
## L 行不连线（角度无独立图形边）。无任何点返回空数组（控件清屏）。
func _sketch_points(text: String) -> PackedVector2Array:
	var pts: Dictionary = {}
	var edges: Array = []
	var errors := PackedStringArray()
	var net := _parse_network(text, errors)
	for nm: String in net["known"].keys():
		var c: Array = net["known"][nm]
		pts[nm] = Vector2(float(c[0]), float(c[1]))
	for nm2: String in net["approx"].keys():
		var c2: Array = net["approx"][nm2]
		pts[nm2] = Vector2(float(c2[0]), float(c2[1]))
	for o in net["dist_obs"]:
		var a: String = String(o["from"])
		var b: String = String(o["to"])
		if pts.has(a) and pts.has(b):
			edges.append(PackedVector2Array([pts[a], pts[b]]))
	var out := PackedVector2Array()
	if edges.is_empty():
		# 无测边观测时退化为单点序列连线（按收录顺序），至少呈现点位分布
		for nm3: String in pts.keys():
			out.append(pts[nm3])
		return out
	for seg in edges:
		out.append(seg[0])
		out.append(seg[1])
	return out

## 文本块 → core 输入字典；出错返回 {} 并填 errors
func _parse_network(text: String, errors: PackedStringArray) -> Dictionary:
	var known := {}
	var approx := {}
	var dist_obs := []
	var angle_obs := []
	for row: Array in _parse_lines(text):
		var tag := String(row[0]).to_upper()
		if tag == "K":
			if row.size() < 4:
				errors.append("K 行应为：K 名称 x y")
				continue
			var x := _num(row[2])
			var y := _num(row[3])
			if is_nan(x) or is_nan(y):
				errors.append("K 行 %s 坐标须为数字" % String(row[1]))
				continue
			known[String(row[1])] = [x, y]
		elif tag == "U":
			if row.size() < 4:
				errors.append("U 行应为：U 名称 x0 y0")
				continue
			var x0 := _num(row[2])
			var y0 := _num(row[3])
			if is_nan(x0) or is_nan(y0):
				errors.append("U 行 %s 近似坐标须为数字" % String(row[1]))
				continue
			approx[String(row[1])] = [x0, y0]
		elif tag == "D":
			# D 起点 终点 边长 [σ_m]：4 列（无 σ）与 5 列（自定 σ）均合法
			if row.size() < 4:
				errors.append("D 行应为：D 起点 终点 边长 [σ]")
				continue
			var s := _num(row[3])
			if is_nan(s):
				errors.append("D 行边长非法：%s" % String(row[3]))
				continue
			var sig := 0.01  # 缺省 σ 默认 0.01 m
			if row.size() >= 5:
				sig = _num(row[4])
				if is_nan(sig) or sig <= 0.0:
					errors.append("D 行 σ 非法：%s" % String(row[4]))
					continue
			dist_obs.append({"from": String(row[1]), "to": String(row[2]), "value": s, "sigma": sig})
		elif tag == "L":
			# L 测站 后视 前视 角度 [σ″]：5 列（无 σ）与 6 列（自定 σ）均合法
			if row.size() < 5:
				errors.append("L 行应为：L 测站 后视 前视 角度 [σ″]")
				continue
			var deg := _num(row[4])
			if is_nan(deg):
				errors.append("L 行角度非法：%s" % String(row[4]))
				continue
			var sig_s := 2.0  # 缺省 σ 默认 2″
			if row.size() >= 6:
				sig_s = _num(row[5])
				if is_nan(sig_s) or sig_s <= 0.0:
					errors.append("L 行 σ″ 非法：%s" % String(row[5]))
					continue
			angle_obs.append({"at": String(row[1]), "back": String(row[2]), "front": String(row[3]),
					"value_deg": deg, "sigma_s": sig_s})
		else:
			errors.append("未知行类型 %s（应为 K/U/D/L）" % String(row[0]))
	return {"known": known, "approx": approx, "dist_obs": dist_obs, "angle_obs": angle_obs}

func run() -> Dictionary:
	var errors := PackedStringArray()
	var net := _parse_network(_field_text("data"), errors)
	# 网图：只要解析出点位就画（先于报错返回，便于用户对照图形找格式问题）
	if _sketch != null:
		_sketch.call("set_points", _sketch_points(_field_text("data")))
	if errors.size() > 0:
		return _parse_fail(errors)
	var res := NW.adjust(net)
	if not bool(res.get("ok", false)):
		return res
	# 附加：每个未知点的误差椭圆（C9 联动，教学展示）
	var qxx: Array = res.get("qxx", [])
	var mu: float = float(res["value"].get("mu0", NAN))
	var names: Array = res.get("param_names", [])
	if not qxx.is_empty() and is_finite(mu):
		for j in names.size() / 2:
			var qx: float = (qxx[2 * j] as PackedFloat64Array)[2 * j]
			var qy: float = (qxx[2 * j + 1] as PackedFloat64Array)[2 * j + 1]
			var qxy: float = (qxx[2 * j] as PackedFloat64Array)[2 * j + 1]
			var ell: Dictionary = AC.ellipse_from_q({"qxx": qx, "qyy": qy, "qxy": qxy, "sigma0": mu})
			if bool(ell.get("ok", false)):
				var nm: String = String(names[2 * j])
				res["value"]["ell_%s_A_mm" % nm] = float(ell["value"]["A_m"]) * 1000.0
				res["value"]["ell_%s_B_mm" % nm] = float(ell["value"]["B_m"]) * 1000.0
				res["value"]["ell_%s_phiE_deg" % nm] = float(ell["value"]["phi_E_deg"])
	return res

func get_title() -> String:
	return "平面控制网严密平差（C5）"

func get_description() -> String:
	return "导线网/测边网/边角网间接平差：误差方程→法方程（Cholesky）→精度评定。输出坐标、残差、μ₀、点位中误差与误差椭圆。区别于 C1-C4 近似平差。"

func get_entry_id() -> String:
	return "c5_network"
