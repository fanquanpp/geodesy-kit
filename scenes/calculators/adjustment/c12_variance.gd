# scenes/calculators/adjustment/c12_variance.gd —— C12 方差分量估计（Helmert）与秩亏自由网计算器
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const VE := preload("res://core/adjustment/variance_est.gd")

const FMT_NET := """自由网模式每行一条（无已知点，须含测边提供尺度）：
U 名称 x0 y0
D 起点 终点 边长 σ_m
L 测站 后视 前视 角度° σ_″     （β=α(前视)−α(后视)，可正可负）"""

const FMT_GROUP := """Helmert 模式每行一条（每组内 σ 须一致）：
D 起点 终点 边长 σ_m
L 测站 后视 前视 角度° σ_″"""

func _build_fields() -> void:
	add_input_row("模式：helmert / free", "mode", "free")
	_add_text_area("已知点 K 名称 x y（仅 helmert 用）", "known",
			"K A 0 0\nK B 1000 0\nK C 500 866.0254")
	_add_text_area("未知点 U 名称 x0 y0", "approx",
			"U A 0 0\nU B 1000 0\nU C 500 866.0254")
	_add_text_area("观测组1（helmert：测边组；free：全部观测）", "group1",
			"D A B 1000.004 0.005\nD B C 999.997 0.005\nD C A 1000.002 0.005")
	_add_text_area("观测组2（helmert：测角组；free 模式忽略）", "group2",
			"L A B C -60 2\nL B C A -60 2\nL C A B -60 2")

## 行解析（D/L 行，helmert 组与 free 通用）
func _parse_obs(text: String, errors: PackedStringArray, what: String) -> Array:
	var dist_obs := []
	var angle_obs := []
	for row: Array in _parse_lines(text):
		var tag := String(row[0]).to_upper()
		if tag == "D":
			if row.size() < 5:
				errors.append("%s：D 行应为 D 起点 终点 边长 σ" % what)
				continue
			var s := _num(row[3])
			var sig := _num(row[4])
			if is_nan(s) or is_nan(sig) or sig <= 0.0:
				errors.append("%s：D 行边长/σ 非法" % what)
				continue
			dist_obs.append({"from": String(row[1]), "to": String(row[2]), "value": s, "sigma": sig})
		elif tag == "L":
			if row.size() < 6:
				errors.append("%s：L 行应为 L 测站 后视 前视 角度 σ″" % what)
				continue
			var deg := _num(row[4])
			var sig_s := _num(row[5])
			if is_nan(deg) or is_nan(sig_s) or sig_s <= 0.0:
				errors.append("%s：L 行角度/σ″ 非法" % what)
				continue
			angle_obs.append({"at": String(row[1]), "back": String(row[2]), "front": String(row[3]),
					"value_deg": deg, "sigma_s": sig_s})
		elif tag == "K" or tag == "U":
			errors.append("%s：K/U 行请填到对应输入框" % what)
		else:
			errors.append("%s：未知行类型 %s（应为 D/L）" % [what, String(row[0])])
	return [dist_obs, angle_obs]

func _parse_points(text: String, errors: PackedStringArray, tag_expect: String) -> Dictionary:
	var out := {}
	for row: Array in _parse_lines(text):
		if String(row[0]).to_upper() != tag_expect:
			errors.append("%s 行应以 %s 开头" % [String(row[0]), tag_expect])
			continue
		if row.size() < 4:
			errors.append("%s 行应为：%s 名称 x y" % [tag_expect, tag_expect])
			continue
		var x := _num(row[2])
		var y := _num(row[3])
		if is_nan(x) or is_nan(y):
			errors.append("%s 行 %s 坐标须为数字" % [tag_expect, String(row[1])])
			continue
		out[String(row[1])] = [x, y]
	return out

func run() -> Dictionary:
	var errors := PackedStringArray()
	var mode: String = String(_field_text("mode")).strip_edges().to_lower()
	if mode == "free":
		var approx := _parse_points(_field_text("approx"), errors, "U")
		var obs: Array = _parse_obs(_field_text("group1"), errors, "观测")
		if errors.size() > 0:
			return _parse_fail(errors)
		return VE.free_net({"approx": approx, "dist_obs": obs[0], "angle_obs": obs[1]})
	if mode != "helmert":
		return {"ok": false, "value": {}, "steps": [], "formula": "",
				"error": "模式只支持 helmert / free"}
	var known := _parse_points(_field_text("known"), errors, "K")
	var approx2 := _parse_points(_field_text("approx"), errors, "U")
	var g1: Array = _parse_obs(_field_text("group1"), errors, "组1")
	var g2: Array = _parse_obs(_field_text("group2"), errors, "组2")
	if errors.size() > 0:
		return _parse_fail(errors)
	if g1[0].is_empty() and g1[1].is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "",
				"error": "观测组1 为空"}
	if g2[0].is_empty() and g2[1].is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "",
				"error": "Helmert 估计至少需要 2 个观测组，请在观测组2 填入数据"}
	return VE.helmert({
		"known": known, "approx": approx2,
		"groups": [
			{"name": "组1", "dist_obs": g1[0], "angle_obs": g1[1]},
			{"name": "组2", "dist_obs": g2[0], "angle_obs": g2[1]},
		],
	})

func get_title() -> String:
	return "方差分量估计与秩亏自由网（C12）"

func get_description() -> String:
	return "free=秩亏自由网平差（附加基准条件法最小范数解：Σδx=Σδy=Σ(−y⁰δx+x⁰δy)=0）；helmert=严格无偏两分量方差分量估计（迭代重定权至 σ̂0i²→1，输出各组原生单位 σ 估值）。"

func get_entry_id() -> String:
	return "c12_variance"
