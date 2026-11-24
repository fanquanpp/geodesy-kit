# app/batch_convert.gd —— G2 批量坐标转换编排（ARCHITECTURE.md §4 集成阶段）
#
# 职责：一份点文件（多行文本：每行 点名,值1,值2,…）对整批点套用各坐标类
# 模块已导出的转换函数。算法一律复用 core §5 协议入口
# （GKGaussKruger / GKUtm / GKBlhXYZ / GKBursa / GKFourParam），
# 本层只做解析 → 逐点编排 → 逐行错误报告，不重写任何投影/转换数学。
#
# 输入行格式（分隔符：中英文逗号/分号/制表符/空格；# 与 // 注释行跳过）：
#   点名, 值1, 值2[, 值3] —— 数值列含义由所选管线 cols 决定（见 PIPELINES）。
# 解析失败/数值非法的行不中断整批：进入 rows 逐行中文错误（进度与逐行报告口径）。
#
# 复用口径：core 为 static §5 协议（forward/inverse/transform/apply），
# 逐点调用即逐行拿到与单点计算器完全一致的中文错误与精度口径。
class_name GKBatchConvert
extends RefCounted

## 支持的转换管线。key → {label, dims, cols（输出列说明）, params_hint}
const PIPELINES := {
	"blh_to_xyz": {
		"label": "大地坐标 BLH → 空间直角 XYZ（EPSG 9602 闭式）",
		"dims": 3, "in_cols": "B（°）、L（°）、h（m）",
		"out_cols": ["X 坐标（m）", "Y 坐标（m）", "Z 坐标（m）"],
		"params_hint": "datum=椭球名（CGCS2000/WGS84…，留空 WGS84）",
	},
	"xyz_to_blh": {
		"label": "空间直角 XYZ → 大地坐标 BLH（Bowring 闭式）",
		"dims": 3, "in_cols": "X（m）、Y（m）、Z（m）",
		"out_cols": ["纬度（°）", "经度（°）", "高程（m）"],
		"params_hint": "datum=椭球名（留空 WGS84）",
	},
	"blh_to_gauss": {
		"label": "BLH → 高斯平面坐标 x/y（教材级数，与 pyproj 复核 ≤0.02mm）",
		"dims": 3, "in_cols": "B（°）、L（°）、h（m）",
		"out_cols": ["X 坐标（m）", "Y 坐标（m）"],
		"params_hint": "datum=椭球名（默认 CGCS2000）；l0_deg=中央子午线（度，必填）；k0/fe_m/fn_m 可选",
	},
	"gauss_to_blh": {
		"label": "高斯平面坐标 → BLH（μ1 迭代 + Newton 精化）",
		"dims": 2, "in_cols": "x（m）、y（m）",
		"out_cols": ["纬度（°）", "经度（°）"],
		"params_hint": "datum、l0_deg（度，必填）、k0/fe_m/fn_m 与正算同口径",
	},
	"blh_to_utm": {
		"label": "BLH → UTM（k0=0.9996，自动选带可指定）",
		"dims": 3, "in_cols": "B（°）、L（°）、h（m）",
		"out_cols": ["东坐标（m）", "北坐标（m）"],
		"params_hint": "datum（默认 WGS84）；zone=带号（留空自动选带）",
	},
	"utm_to_blh": {
		"label": "UTM（E/N）→ BLH",
		"dims": 2, "in_cols": "E（m）、N（m）",
		"out_cols": ["纬度（°）", "经度（°）"],
		"params_hint": "datum；zone=带号（1..60，必填）；hemisphere=N/S（必填，南北网格重叠无法自动判）",
	},
	"bursa_fwd": {
		"label": "七参数布尔莎转换 XYZ → XYZ（PV/CF 双约定，一次传入 core 批量算）",
		"dims": 3, "in_cols": "X（m）、Y（m）、Z（m）",
		"out_cols": ["目标 X 坐标（m）", "目标 Y 坐标（m）", "目标 Z 坐标（m）"], "batch": true,
		"params_hint": "tx_m/ty_m/tz_m；rx_as/ry_as/rz_as(″)；scale_ppm；convention=PV/CF；three_param=true 为三参数",
	},
	"four_param_fwd": {
		"label": "平面四参数转换（正算：源平面 → 目标平面）",
		"dims": 2, "in_cols": "x（m）、y（m）",
		"out_cols": ["目标 X 坐标（m）", "目标 Y 坐标（m）"], "batch": true,
		"params_hint": "dx_m, dy_m, scale, alpha_deg（°）",
	},
	"four_param_inv": {
		"label": "平面四参数转换（反算：目标平面 → 源平面）",
		"dims": 2, "in_cols": "X（m）、Y（m）",
		"out_cols": ["源 X 坐标（m）", "源 Y 坐标（m）"], "batch": true,
		"params_hint": "dx_m, dy_m, scale, alpha_deg（与正算同口径）",
	},
}

## 解析点文件文本 → {points:[{line,name,vals}], errors:[{line,error}]}
## 数值列数必须等于所选管线 dims；点名可空（执行时自动"点N"）。
static func parse_points(text: String, dims: int) -> Dictionary:
	var out := []
	var errors := []
	var lines := text.split("\n")
	for i in lines.size():
		var raw := lines[i].strip_edges()
		if raw.is_empty() or raw.begins_with("#") or raw.begins_with("//"):
			continue
		var cleaned := raw.replace("，", ",").replace("；", ",").replace("\t", ",")
		cleaned = cleaned.replace(",", " ")
		while "  " in cleaned:
			cleaned = cleaned.replace("  ", " ")
		var tokens := cleaned.split(" ", false)
		if tokens.size() < 1 + dims:
			errors.append({"line": i + 1,
					"error": "应为「点名 + %d 个数值」共 %d 列，实际 %d 列" % [dims, 1 + dims, tokens.size()]})
			continue
		var vals := []
		var bad := ""
		for j in range(1, 1 + dims):
			var t := String(tokens[j]).strip_edges().replace("−", "-")
			if t.is_empty() or not t.is_valid_float():
				bad = "第 %d 列不是有效数字：%s" % [j + 1, String(tokens[j])]
				break
			vals.append(t.to_float())
		if not bad.is_empty():
			errors.append({"line": i + 1, "error": bad})
			continue
		out.append({"line": i + 1, "name": String(tokens[0]), "vals": vals})
	return {"points": out, "errors": errors}

## 执行批量转换。
## p：{pipeline: String（PIPELINES 键）, text: String（点文件内容）, params: Dictionary}
## 返回 §5 协议：ok=true 时 value={rows, n_ok, n_err, pipeline, label, out_cols,
## in_cols, summary}；前七键为机器契约（tests/tools/test_tools.gd 直读，不可动），
## summary 为面向用户的中文统计行（渲染层展示键，报告/结果卡优先取它）。
## rows=[{line,name,values,error}]（失败行 error 中文、不中断整批）；
## ok=false 仅当管线名非法、core 参数整体非法或全部行解析失败。
static func convert(p: Dictionary) -> Dictionary:
	var formula := "G2 批量坐标转换（编排层：复用 core §5 协议，不重写算法）"
	var key := String(p.get("pipeline", "")).strip_edges()
	if not PIPELINES.has(key):
		return {"ok": false, "value": {}, "steps": [], "formula": formula,
				"error": "未知转换类型：%s（可用：%s）" % [key, "、".join(PIPELINES.keys())]}
	var pipe: Dictionary = PIPELINES[key]
	var dims := int(pipe["dims"])
	var parsed := parse_points(String(p.get("text", "")), dims)
	var points: Array = parsed["points"]
	var errors: Array = parsed["errors"]
	if points.is_empty():
		var first := "（无错误明细）"
		if not errors.is_empty():
			first = "第 %d 行 %s" % [int(errors[0]["line"]), String(errors[0]["error"])]
		return {"ok": false, "value": {}, "steps": [], "formula": formula,
				"error": "没有可转换的数据行（%d 行解析失败）。%s" % [errors.size(), first]}
	var params: Dictionary = p.get("params", {}) if p.get("params", {}) is Dictionary else {}
	if bool(pipe.get("batch", false)):
		# 解析失败行也要进 rows 逐行报告（与 _run_per_point 口径一致），
		# 否则坏行凭空消失、summary 失真
		return _run_batch(key, pipe, points, params, errors, formula)
	return _run_per_point(key, pipe, points, params, errors, formula)

# ---------- 逐点协议模式（投影/BLH 类：逐行错误报告） ----------

static func _run_per_point(key: String, pipe: Dictionary, points: Array,
		params: Dictionary, errors: Array, formula: String) -> Dictionary:
	var spec: Variant = _DISPATCH.get(key)
	if spec == null:
		return {"ok": false, "value": {}, "steps": [], "formula": formula,
				"error": "管线未注册执行器：%s" % key}
	var spec_d: Dictionary = spec
	var script: GDScript = spec_d["script"]
	var fn := String(spec_d["method"])
	var n_ok := 0
	var rows := []
	for e: Dictionary in errors:
		rows.append({"line": int(e["line"]), "name": "", "values": [], "error": String(e["error"])})
	for i in points.size():
		var pt: Dictionary = points[i]
		var q: Dictionary = _build_call_params(params, spec_d["keys"], pt["vals"])
		var r: Dictionary = script.call(fn, q)
		if bool(r.get("ok", false)):
			n_ok += 1
			rows.append({"line": int(pt["line"]), "name": _point_name(pt, i),
					"values": _pick_values(r.get("value", {}), spec_d["out"]), "error": ""})
		else:
			rows.append({"line": int(pt["line"]), "name": _point_name(pt, i),
					"values": [], "error": String(r.get("error", "转换失败"))})
	return _pack(key, pipe, rows, n_ok, formula)

# ---------- 点集一次传入模式（七参数/四参数：core 自身支持批量） ----------

static func _run_batch(key: String, pipe: Dictionary, points: Array, params: Dictionary,
		errors: Array, formula: String) -> Dictionary:
	var spec: Variant = _DISPATCH.get(key)
	if spec == null:
		return {"ok": false, "value": {}, "steps": [], "formula": formula,
				"error": "管线未注册执行器：%s" % key}
	var spec_d: Dictionary = spec
	var script: GDScript = spec_d["script"]
	var vals_arr := []
	for pt: Dictionary in points:
		vals_arr.append(pt["vals"])
	var q: Dictionary = (spec_d.get("extra", {}) as Dictionary).duplicate(true)
	q.merge(params.duplicate(true))
	q[String(spec_d["points_key"])] = vals_arr
	var r: Dictionary = script.call(String(spec_d["method"]), q)
	if not bool(r.get("ok", false)):
		return r  # core 参数级中文错误原样透传（参数缺失/约定非法等）
	var out_pts: Array = (r.get("value", {}) as Dictionary).get("points_m", [])
	var rows := []
	var n_ok := 0
	# 解析失败行先行进 rows（序次与 _run_per_point 一致：坏行在前，按行号排列）
	for e: Dictionary in errors:
		rows.append({"line": int(e["line"]), "name": "", "values": [], "error": String(e["error"])})
	for i in points.size():
		var pt: Dictionary = points[i]
		if i < out_pts.size():
			n_ok += 1
			rows.append({"line": int(pt["line"]), "name": _point_name(pt, i),
					"values": _nums_of(out_pts[i]), "error": ""})
		else:
			rows.append({"line": int(pt["line"]), "name": _point_name(pt, i),
					"values": [], "error": "core 未返回该行结果"})
	var steps: Array = r.get("steps", [])
	steps.append({"title": "批量编排（G2）", "formula": String(pipe["label"]),
			"substitution": "共 %d 点一次传入 core，与单点计算器同一实现" % points.size(),
			"result": "成功 %d 行，失败 %d 行" % [n_ok, rows.size() - n_ok]})
	return _pack(key, pipe, rows, n_ok, String(r.get("formula", formula)), steps)

# ---------- 共用 ----------

## core 脚本（preload 常量路径，GKBatchConvert 不经 class_name 依赖——
## 工程统一 --import 前 class_name 缓存未必就位，全走 preload 与各施工模块口径一致）
const _SCR_BLH := preload("res://core/ellipsoid/blh_xyz.gd")
const _SCR_GAUSS := preload("res://core/projection/gauss_kruger.gd")
const _SCR_UTM := preload("res://core/projection/utm.gd")
const _SCR_BURSA := preload("res://core/transform/bursa.gd")
const _SCR_FOUR := preload("res://core/transform/four_param.gd")

## 执行器注册表：key → {script, method, keys（数值列→协议键）, out（value→输出列键）}
const _DISPATCH := {
	"blh_to_xyz": {"script": _SCR_BLH, "method": "forward",
		"keys": ["lat_deg", "lon_deg", "h_m"], "out": ["x_m", "y_m", "z_m"]},
	"xyz_to_blh": {"script": _SCR_BLH, "method": "inverse",
		"keys": ["x_m", "y_m", "z_m"], "out": ["lat_deg", "lon_deg", "h_m"]},
	"blh_to_gauss": {"script": _SCR_GAUSS, "method": "forward",
		"keys": ["lat_deg", "lon_deg"], "out": ["x_m", "y_m"]},
	"gauss_to_blh": {"script": _SCR_GAUSS, "method": "inverse",
		"keys": ["x_m", "y_m"], "out": ["lat_deg", "lon_deg"]},
	"blh_to_utm": {"script": _SCR_UTM, "method": "forward",
		"keys": ["lat_deg", "lon_deg"], "out": ["e_m", "n_m"]},
	"utm_to_blh": {"script": _SCR_UTM, "method": "inverse",
		"keys": ["e_m", "n_m"], "out": ["lat_deg", "lon_deg"]},
	"bursa_fwd": {"script": _SCR_BURSA, "method": "transform",
		"points_key": "src_xyz"},
	"four_param_fwd": {"script": _SCR_FOUR, "method": "apply",
		"points_key": "src_xy", "extra": {"mode": "fwd"}},
	"four_param_inv": {"script": _SCR_FOUR, "method": "apply",
		"points_key": "dst_xy", "extra": {"mode": "inv"}},
}

static func _pack(key: String, pipe: Dictionary, rows: Array, n_ok: int,
		formula: String, steps: Array = []) -> Dictionary:
	var n_err := rows.size() - n_ok
	# 用户可见统计口径与步骤卡 result 行一致：只说行数，不暴露机器键名
	var summary := "共 %d 行：成功 %d 行，失败 %d 行" % [rows.size(), n_ok, n_err]
	if steps.is_empty():
		steps = [
			{"title": "1. 选择转换管线", "formula": String(pipe["label"]),
				"substitution": String(pipe.get("params_hint", "")),
				"result": "成功 %d 行，失败 %d 行" % [n_ok, n_err]},
			{"title": "2. 复用 core 转换函数", "formula": "逐点调用 core §5 协议入口",
				"substitution": "算法与单点计算器完全一致（同一 core 实现与精度口径）",
				"result": "逐行错误见结果表（失败行不中断整批）"},
		]
	return {
		"ok": true,
		"value": {"rows": rows, "n_ok": n_ok, "n_err": n_err,
				"pipeline": key, "label": String(pipe["label"]),
				"out_cols": pipe["out_cols"], "in_cols": String(pipe["in_cols"]),
				"summary": summary},
		"steps": steps, "formula": formula, "error": "",
	}

static func _build_call_params(params: Dictionary, keys: Array, vals: Array) -> Dictionary:
	var p := params.duplicate(true)
	for i: int in mini(keys.size(), vals.size()):
		p[keys[i]] = vals[i]
	return p

static func _pick_values(value: Dictionary, out_keys: Array) -> Array:
	var out := []
	for k: String in out_keys:
		out.append(float(value.get(k, NAN)))
	return out

static func _nums_of(v: Variant) -> Array:
	var out := []
	if v is Array or v is PackedFloat64Array:
		for x: Variant in v:
			out.append(float(x))
	return out

static func _point_name(pt: Dictionary, idx: int) -> String:
	var n := String(pt.get("name", "")).strip_edges()
	return n if not n.is_empty() else "点%d" % (idx + 1)

## rows → CSV 文本（导出结果文件用；失败行输出「失败：<错误>」状态列并按
## max_v 补齐空值列，保证每行字段数与表头一致（Excel 打开状态列不错位）。
## 表头优先用 out_cols（管线真实输出列名，与结果卡 _col_name 同源），
## 列数不足或未传时回退「值N」；decimals 为用户设置的小数位数（1–12，
## 与单点计算器 calculator_base._render_result 同口径）。
static func rows_to_csv(rows: Array, out_cols: Array = [], decimals: int = 6) -> String:
	var max_v := 0
	for r: Dictionary in rows:
		max_v = maxi(max_v, (r.get("values", []) as Array).size())
	var head := "行号,点名"
	for i in max_v:
		head += ",%s" % _csv_cell(String(out_cols[i]) if i < out_cols.size() and not String(out_cols[i]).is_empty() else "值%d" % (i + 1))
	head += ",状态"
	var L := PackedStringArray()
	L.append(head)
	for r: Dictionary in rows:
		var line := "%d,%s" % [int(r.get("line", 0)), _csv_cell(String(r.get("name", "")))]
		var err := String(r.get("error", ""))
		var vals: Array = r.get("values", [])
		if not err.is_empty():
			# 失败行：补齐空值占位列（与表头对齐）再接状态列
			for i in max_v:
				line += ","
			line += ",失败：%s" % _csv_cell(err)
			L.append(line)
			continue
		for i in max_v:
			line += ","
			if i < vals.size():
				line += _num_text(vals[i], decimals)
		line += ",成功"
		L.append(line)
	return "\n".join(L)

## 数值 → 定点小数文本；decimals 由调用方传入（设置页「计算结果小数位数」口径，
## 静态函数不依赖 GKServices 单例，面板侧负责取值）
static func _num_text(v: Variant, decimals: int) -> String:
	if v is float or v is int:
		return String.num(float(v), decimals)
	return str(v)

static func _csv_cell(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s
