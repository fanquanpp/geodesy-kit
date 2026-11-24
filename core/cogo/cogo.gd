# core/cogo/cogo.gd —— GK-M5：坐标正算/反算（A1/A2）+ 三维正反算（斜距/竖直角/仪高/棱镜高）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M5 / §5 协议）：
#   - 纯静态函数、零引擎依赖（extends RefCounted）；角度调 M1 GKAngles（唯一允许的跨域依赖）；
#   - 坐标系约定：平面直角坐标 x=东（横）、y=北（纵）；方位角从北（+y）起顺时针 [0°,360°)；
#     坐标增量 Δx = D·sin α，Δy = D·cos α；
#   - 三维：斜距 S、竖直角 v（仰角为正）、仪器高 i、棱镜高 t；
#     平距 D = S·cos v；高差（棱镜中心）Δh_镜 = S·sin v；地面高程 H_P = H_0 + S·sin v + i − t；
#   - 每个计算入口统一返回 §5 协议 {ok, value, steps, formula, error}；
#     失败 ok=false：value 空字典、error 必为中文可读原因，不抛异常不输出堆栈。
class_name GKCogo
extends RefCounted

# 球气差（地球曲率+大气折光）计算用平均地球半径（米，GeographicLib R1 约定），
# 与 core/adjustment/leveling.gd 单向三角高程同一取值；键名统一 f_ballistic_m。
const EARTH_R_M := 6371008.7714
const K_DEFAULT := 0.13  # 大气折光系数默认值

# ---------- 纯计算原语（返回 {} 表示输入不合法；供核心内部复用） ----------

## 平面坐标正算：A(x0,y0) 沿方位 az_deg 前进 dist → P。距离为负视为不合法。
static func fwd(x0: float, y0: float, az_deg: float, dist: float) -> Dictionary:
	if not (is_finite(x0) and is_finite(y0) and is_finite(az_deg) and is_finite(dist)):
		return {}
	if dist < 0.0:
		return {}
	var ar := deg_to_rad(az_deg)
	var dx := dist * sin(ar)
	var dy := dist * cos(ar)
	return {
		"x": x0 + dx, "y": y0 + dy,
		"dx": dx, "dy": dy,
		"az_deg": GKAngles.normalize_deg(az_deg), "dist": dist,
	}

## 平面坐标反算：两点边长与坐标方位角。两点重合（d<1e-12）方位角无定义 → {}。
static func inv(x0: float, y0: float, x: float, y: float) -> Dictionary:
	if not (is_finite(x0) and is_finite(y0) and is_finite(x) and is_finite(y)):
		return {}
	var dx := x - x0
	var dy := y - y0
	var d := sqrt(dx * dx + dy * dy)
	if d < 1e-12:
		return {}
	return {"d": d, "az_deg": GKAngles.azimuth(dx, dy), "dx": dx, "dy": dy}

## 三维坐标正算。dist 为斜距（dist_is_slope=true）或平距；v_deg 竖直角（仰角为正，|v|<90°）。
## k 为大气折光系数（默认 0.13）；f_ball 为球气差（地球曲率+大气折光）改正，
## f = (1−k)·D²/(2R)，R 取平均地球半径，与 leveling.gd 单向三角高程同式同键名 f_ballistic_m。
## 返回 {x, y, h, d_horiz, dh, slope, az_deg, f_ballistic_m}；dh 为地面高差（已含仪高/棱镜高/球气差改正）。
static func fwd_3d(x0: float, y0: float, h0: float, az_deg: float, dist: float,
		v_deg: float, hi: float, ht: float, dist_is_slope := true, k := 0.13) -> Dictionary:
	if not (is_finite(x0) and is_finite(y0) and is_finite(h0) and is_finite(az_deg)
			and is_finite(dist) and is_finite(v_deg) and is_finite(hi) and is_finite(ht)
			and is_finite(k)):
		return {}
	if dist < 0.0:
		return {}
	if absf(v_deg) >= 90.0:
		return {}
	if k < 0.0 or k >= 1.0:
		return {}
	var vr := deg_to_rad(v_deg)
	var d_horiz := 0.0
	var dh := 0.0
	var dh_prism := 0.0  # 棱镜中心高差（不含仪高/棱镜高/球气差改正）
	if dist_is_slope:
		d_horiz = dist * cos(vr)
		dh_prism = dist * sin(vr)
		dh = dh_prism + hi - ht
	else:
		d_horiz = dist
		dh_prism = dist * tan(vr)
		dh = dh_prism + hi - ht
	# 球气差改正：f = (1−k)·D²/(2R)（D 平距，单向观测恒为正项）
	var f_ball := (1.0 - k) * d_horiz * d_horiz / (2.0 * EARTH_R_M)
	dh += f_ball
	var f := fwd(x0, y0, az_deg, d_horiz)
	if f.is_empty():
		return {}
	return {
		"x": f["x"], "y": f["y"],
		"h": h0 + dh,
		"d_horiz": d_horiz, "dh": dh,
		"f_ballistic_m": f_ball,
		# 到棱镜中心的三维斜距（与 inv_3d 的 slope 同一口径：√(D²+Δh_镜²)，不含球气差）
		"slope": sqrt(d_horiz * d_horiz + dh_prism * dh_prism),
		"az_deg": f["az_deg"],
		"k": k,
	}

## 三维坐标反算：由测站（含仪器高）与目标点（含棱镜高）反算平距/斜距/竖直角/方位角。
## 竖直角指向棱镜中心：dh_镜 = (h_P + t) − (H_0 + i)。两点平面重合 → {}。
static func inv_3d(x0: float, y0: float, h0: float, x: float, y: float, h: float,
		hi: float, ht: float) -> Dictionary:
	var p := inv(x0, y0, x, y)
	if p.is_empty():
		return {}
	if not (is_finite(h0) and is_finite(h) and is_finite(hi) and is_finite(ht)):
		return {}
	var dh := (h + ht) - (h0 + hi)
	var d_horiz: float = p["d"]
	return {
		"d_horiz": d_horiz,
		"slope": sqrt(d_horiz * d_horiz + dh * dh),
		"v_deg": rad_to_deg(atan2(dh, d_horiz)),
		"az_deg": p["az_deg"],
		"dh": dh,
	}
# ---------- §5 协议入口（计算器场景调用） ----------

## A1 坐标正算（极坐标法）。输入：{x0_m, y0_m, az_deg, dist_m}。
static func forward(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x0 := _num(p, "x0_m", "起点 x", bad)
	var y0 := _num(p, "y0_m", "起点 y", bad)
	var az := _ang(p, "az_deg", "坐标方位角", bad)
	var dist := _num(p, "dist_m", "水平距离", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	if dist < 0.0:
		return _fail("水平距离不能为负数（输入 %.4f）" % dist)
	var r := fwd(x0, y0, az, dist)
	if r.is_empty():
		return _fail("坐标正算输入不合法")
	var az_n: float = r["az_deg"]
	return {
		"ok": true,
		"value": {
			"x_m": r["x"], "y_m": r["y"],
			"dx_m": r["dx"], "dy_m": r["dy"],
			"az_deg": az_n, "az_dms": GKAngles.deg_to_dms_str(az_n),
			"dist_m": dist,
		},
		"steps": [
			_step("1. 计算坐标增量", "Δx = D·sin α；Δy = D·cos α",
				"Δx = %s×sin %s = %s m；Δy = %s×cos %s = %s m" % [
					_f(dist), GKAngles.deg_to_dms_str(az_n), _f(r["dx"]),
					_f(dist), GKAngles.deg_to_dms_str(az_n), _f(r["dy"])],
				"Δx = %s m，Δy = %s m" % [_f(r["dx"]), _f(r["dy"])]),
			_step("2. 计算待定点坐标", "x_P = x_A + Δx；y_P = y_A + Δy",
				"x = %s + %s；y = %s + %s" % [_f(x0), _f(r["dx"]), _f(y0), _f(r["dy"])],
				"x = %s m，y = %s m" % [_f(r["x"]), _f(r["y"])]),
			_step("3. 长度改化提示（高斯投影）", "高斯平面边长 ≠ 实地边长：m ≈ 1 + y²/(2R²)（y 为距中央子午线的横坐标）",
				"例：y=400 km 时 m≈1.001971，即每公里实测边长改化到高斯平面约 +1.97 m（m≈1.001971）",
				"长距离放样/量距时请先做长度改化（每公里 +1.97 m @400km）；本计算按高斯平面直角坐标（未改化）进行"),
		],
		"formula": "坐标正算（极坐标法）：Δx = D·sin α，Δy = D·cos α。"
				+ "坐标约定：x=东（横）、y=北（纵），方位角从北起顺时针。"
				+ "坐标为高斯平面直角坐标时，实测边长需先做长度改化（y=400 km 处 m≈1.001971，每公里 +1.97 m）。",
		"error": "",
	}

## A2 坐标反算。输入：{x0_m, y0_m, x_m, y_m}。两点重合报错。
static func inverse(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x0 := _num(p, "x0_m", "起点 x", bad)
	var y0 := _num(p, "y0_m", "起点 y", bad)
	var x := _num(p, "x_m", "待定点 x", bad)
	var y := _num(p, "y_m", "待定点 y", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var r := inv(x0, y0, x, y)
	if r.is_empty():
		return _fail("两点重合（坐标完全相同），边长与方位角无定义")
	var az: float = r["az_deg"]
	var az_back := GKAngles.normalize_deg(az + 180.0)
	return {
		"ok": true,
		"value": {
			"dist_m": r["d"],
			"az_deg": az, "az_dms": GKAngles.deg_to_dms_str(az),
			"az_back_deg": az_back, "az_back_dms": GKAngles.deg_to_dms_str(az_back),
			"dx_m": r["dx"], "dy_m": r["dy"],
		},
		"steps": [
			_step("1. 计算坐标增量", "Δx = x_P − x_A；Δy = y_P − y_A",
				"Δx = %s − %s = %s；Δy = %s − %s = %s" % [
					_f(x), _f(x0), _f(r["dx"]), _f(y), _f(y0), _f(r["dy"])],
				"Δx = %s m，Δy = %s m" % [_f(r["dx"]), _f(r["dy"])]),
			_step("2. 计算边长", "D = √(Δx² + Δy²)",
				"D = √(%s² + %s²)" % [_f(r["dx"]), _f(r["dy"])],
				"D = %s m" % _f(r["d"])),
			_step("3. 计算坐标方位角", "α = atan2(Δx, Δy)（北起顺时针，规范化到 [0°,360°)；象限按 Δx/Δy 符号判定）",
				"α = atan2(%s, %s)（Δx%s0 →%s，Δy%s0 →%s）" % [
					_f(r["dx"], 6), _f(r["dy"], 6),
					"≥" if r["dx"] >= 0.0 else "<", "东" if r["dx"] >= 0.0 else "西",
					"≥" if r["dy"] >= 0.0 else "<", "北" if r["dy"] >= 0.0 else "南"],
				"α = %s = %s（%s象限）" % [_f(az, 6) + "°", GKAngles.deg_to_dms_str(az), _quadrant_name(az)]),
			_step("4. 长度改化提示（高斯投影）", "高斯平面边长 ≠ 实地边长：m ≈ 1 + y²/(2R²)（y 为距中央子午线的横坐标）",
				"例：y=400 km 时 m≈1.001971，即每公里实测边长改化到高斯平面约 +1.97 m（m≈1.001971）",
				"长距离放样/量距时请先做长度改化（每公里 +1.97 m @400km）；本计算按高斯平面直角坐标（未改化）进行"),
		],
		"formula": "坐标反算：D = √(Δx²+Δy²)，α = atan2(Δx, Δy)，象限按 Δx/Δy 符号判定。"
			+ "反方位角 α′ = α + 180°（规范化）。两点重合时无解。",
		"error": "",
	}

## 三维坐标正算。输入：{x0_m, y0_m, h0_m, az_deg, dist_m, v_deg, hi_m, ht_m, dist_mode, k?}。
## dist_mode："slope"（斜距，默认）或 "horiz"（平距）；k 大气折光系数（缺省 0.13）。
static func forward_3d(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x0 := _num(p, "x0_m", "测站 x", bad)
	var y0 := _num(p, "y0_m", "测站 y", bad)
	var h0 := _num(p, "h0_m", "测站高程", bad)
	var az := _ang(p, "az_deg", "坐标方位角", bad)
	var dist := _num(p, "dist_m", "距离（斜距或平距）", bad)
	var v := _ang(p, "v_deg", "竖直角", bad)
	var hi := _num(p, "hi_m", "仪器高", bad)
	var ht := _num(p, "ht_m", "棱镜高", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var k := K_DEFAULT
	if p.has("k") and p.get("k") != null and not (p.get("k") is String and String(p.get("k")).strip_edges().is_empty()):
		var kk := _num(p, "k", "大气折光系数", bad)
		if not bad.is_empty():
			return _fail(_join_bad(bad))
		k = kk
	if k < 0.0 or k >= 1.0:
		return _fail("大气折光系数 k 应在 [0, 1) 内（默认 %.2f，输入 %s）" % [K_DEFAULT, _f(k, 4)])
	var mode := "slope"
	if p.has("dist_mode"):
		var m := String(p["dist_mode"]).strip_edges().to_lower()
		if m == "horiz" or m == "平距":
			mode = "horiz"
		elif m == "slope" or m == "斜距" or m.is_empty():
			mode = "slope"
		else:
			return _fail("距离类型只支持 slope（斜距）或 horiz（平距），输入：%s" % m)
	if dist < 0.0:
		return _fail("距离不能为负数（输入 %.4f）" % dist)
	if absf(v) >= 90.0:
		return _fail("竖直角绝对值须小于 90°（输入 %s）" % GKAngles.deg_to_dms_str(v))
	var r := fwd_3d(x0, y0, h0, az, dist, v, hi, ht, mode == "slope", k)
	if r.is_empty():
		return _fail("三维坐标正算输入不合法")
	var vr := deg_to_rad(v)
	var d_horiz: float = r["d_horiz"]
	var dh: float = r["dh"]
	var f_ball: float = r["f_ballistic_m"]
	var mode_txt := "斜距" if mode == "slope" else "平距"
	var dh_formula := "Δh_镜 = S·sin v" if mode == "slope" else "Δh_镜 = D·tan v"
	var dist_sym := "S" if mode == "slope" else "D"
	return {
		"ok": true,
		"value": {
			"x_m": r["x"], "y_m": r["y"], "h_m": r["h"],
			"d_horiz_m": d_horiz, "dh_m": dh,
			"f_ballistic_m": f_ball,
			"slope_m": r["slope"],
			"az_deg": r["az_deg"], "v_deg": v, "dist_mode": mode_txt,
		},
		"steps": [
			_step("1. 计算平距", "D = S·cos v" if mode == "slope" else "D = 输入平距",
				"D = %s×cos %s" % [_f(dist), GKAngles.deg_to_dms_str(v)]
					if mode == "slope" else "D = %s m" % _f(dist),
				"D = %s m" % _f(d_horiz)),
			_step("2. 计算高差", dh_formula + " + i − t（i 仪器高，t 棱镜高）",
				"Δh = %s·sin %s + %s − %s" % [dist_sym, GKAngles.deg_to_dms_str(v), _f(hi), _f(ht)]
					if mode == "slope" else
					"Δh = %s·tan %s + %s − %s" % [_f(dist), GKAngles.deg_to_dms_str(v), _f(hi), _f(ht)],
				"Δh = %s m" % _f(dh - f_ball)),
			_step("3. 球气差改正", "f = (1−k)·D²/(2R)，k=%.2f，R=%.4f m" % [k, EARTH_R_M],
				"f = (1−%s)×%s²/(2×%s)" % [_f(k, 2), _f(d_horiz), _f(EARTH_R_M, 4)],
				"f = %s m（单向观测恒为正；对向观测取均值时球气差相互抵消）" % _f(f_ball)),
			_step("4. 平面坐标正算", "Δx = D·sin α；Δy = D·cos α",
				"Δx = %s·sin %s；Δy = %s·cos %s" % [
					_f(d_horiz), GKAngles.deg_to_dms_str(r["az_deg"]),
					_f(d_horiz), GKAngles.deg_to_dms_str(r["az_deg"])],
				"x = %s m，y = %s m" % [_f(r["x"]), _f(r["y"])]),
			_step("5. 待定点高程", "H_P = H_0 + Δh + f",
				"H = %s + %s + %s" % [_f(h0), _f(dh - f_ball), _f(f_ball)],
				"H = %s m" % _f(r["h"])),
		],
		"formula": "三维坐标正算：D = S·cos v，Δh = S·sin v + i − t，"
			+ "f = (1−k)·D²/(2R)（球气差，单向恒为正、对向取均值时相互抵消），"
			+ "H_P = H_0 + Δh + f；平面同 A1。竖直角仰角为正；输入 %s。" % mode_txt,
		"error": "",
	}

## 三维坐标反算。输入：{x0_m, y0_m, h0_m, x_m, y_m, h_m, hi_m, ht_m, k?}。
## 反算竖直角为几何角（指向棱镜中心，不含球气差）；另行输出球气差改正 f 供对向检核。
static func inverse_3d(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x0 := _num(p, "x0_m", "测站 x", bad)
	var y0 := _num(p, "y0_m", "测站 y", bad)
	var h0 := _num(p, "h0_m", "测站高程", bad)
	var x := _num(p, "x_m", "目标点 x", bad)
	var y := _num(p, "y_m", "目标点 y", bad)
	var h := _num(p, "h_m", "目标点高程", bad)
	var hi := _num(p, "hi_m", "仪器高", bad)
	var ht := _num(p, "ht_m", "棱镜高", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var k := K_DEFAULT
	if p.has("k") and p.get("k") != null and not (p.get("k") is String and String(p.get("k")).strip_edges().is_empty()):
		var kk := _num(p, "k", "大气折光系数", bad)
		if not bad.is_empty():
			return _fail(_join_bad(bad))
		k = kk
	if k < 0.0 or k >= 1.0:
		return _fail("大气折光系数 k 应在 [0, 1) 内（默认 %.2f，输入 %s）" % [K_DEFAULT, _f(k, 4)])
	var r := inv_3d(x0, y0, h0, x, y, h, hi, ht)
	if r.is_empty():
		return _fail("两点平面位置重合，边长与方位角无定义")
	var d_horiz: float = r["d_horiz"]
	var dh: float = r["dh"]
	var v: float = r["v_deg"]
	var az: float = r["az_deg"]
	var f_ball := (1.0 - k) * d_horiz * d_horiz / (2.0 * EARTH_R_M)
	return {
		"ok": true,
		"value": {
			"d_horiz_m": d_horiz, "slope_m": r["slope"],
			"v_deg": v, "v_dms": GKAngles.deg_to_dms_str(v),
			"az_deg": az, "az_dms": GKAngles.deg_to_dms_str(az),
			"dh_m": dh,
			"f_ballistic_m": f_ball,
		},
		"steps": [
			_step("1. 平面反算", "D = √(Δx²+Δy²)；α = atan2(Δx, Δy)",
				"D、α 由坐标差直接计算",
				"D = %s m，α = %s" % [_f(d_horiz), GKAngles.deg_to_dms_str(az)]),
			_step("2. 棱镜中心高差", "Δh_镜 = (H_P + t) − (H_0 + i)",
				"Δh = (%s + %s) − (%s + %s)" % [_f(h), _f(ht), _f(h0), _f(hi)],
				"Δh = %s m" % _f(dh)),
			_step("3. 竖直角与斜距", "v = atan(Δh / D)；S = √(D² + Δh²)",
				"v = atan(%s / %s)；S = √(%s² + %s²)" % [_f(dh), _f(d_horiz), _f(d_horiz), _f(dh)],
				"v = %s，S = %s m" % [GKAngles.deg_to_dms_str(v), _f(r["slope"])]),
			_step("4. 球气差改正（参考）", "f = (1−k)·D²/(2R)，k=%.2f，R=%.4f m" % [k, EARTH_R_M],
				"f = (1−%s)×%s²/(2×%s)" % [_f(k, 2), _f(d_horiz), _f(EARTH_R_M, 4)],
				"f = %s m（反算竖直角为几何角，未含 f；对向观测取均值时 f 相互抵消）" % _f(f_ball)),
		],
		"formula": "三维坐标反算：v = atan(Δh_镜/D)，S = √(D²+Δh²)。"
			+ "竖直角指向棱镜中心（已含仪高 i、棱镜高 t 改正），仰角为正；"
			+ "球气差 f = (1−k)·D²/(2R) 仅作参考输出（对向观测取均值时相互抵消）。",
		"error": "",
	}

# ---------- 协议与解析小工具（M5 各文件各自持有，避免 core 横向依赖） ----------

static func _step(title: String, formula: String, substitution: String, result: String) -> Dictionary:
	return {"title": title, "formula": formula, "substitution": substitution, "result": result}

## 方位角 → 象限名（[0,90)北东、[90,180)南东、[180,270)南西、[270,360)北西）
static func _quadrant_name(az_deg: float) -> String:
	var az := GKAngles.normalize_deg(az_deg)
	if az < 90.0:
		return "北东（Ⅰ）"
	if az < 180.0:
		return "南东（Ⅱ）"
	if az < 270.0:
		return "南西（Ⅲ）"
	return "北西（Ⅳ）"

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}

static func _f(v: float, n := 4) -> String:
	var fmt := "%." + str(n) + "f"
	return fmt % v

static func _join_bad(bad: Array) -> String:
	var out := ""
	for i in bad.size():
		if i > 0:
			out += "；"
		out += String(bad[i])
	return out

## 数值输入：接受 float/int/数字字符串；缺失或非法记入 bad 并返回 NAN
static func _num(p: Dictionary, key: String, label: String, bad: Array) -> float:
	if not p.has(key):
		bad.append("缺少输入项「%s」" % label)
		return NAN
	var v: Variant = p[key]
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return f
		bad.append("「%s」数值非有限" % label)
		return NAN
	if v is String:
		var t := String(v).strip_edges().replace("−", "-")
		if t.is_empty():
			bad.append("请输入「%s」" % label)
			return NAN
		if t.is_valid_float():
			var f2 := t.to_float()
			if is_finite(f2):
				return f2
		bad.append("「%s」不是有效数字：%s" % [label, t])
		return NAN
	bad.append("「%s」输入类型不支持" % label)
	return NAN

## 角度输入：字符串可写十进制度（30.5）或度分秒（30 30 00 / 30°30′00″）
static func _ang(p: Dictionary, key: String, label: String, bad: Array) -> float:
	if not p.has(key):
		bad.append("缺少输入项「%s」" % label)
		return NAN
	var v: Variant = p[key]
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return f
		bad.append("「%s」数值非有限" % label)
		return NAN
	if v is String:
		var t := String(v).strip_edges()
		if t.is_empty():
			bad.append("请输入「%s」" % label)
			return NAN
		var deg := GKAngles.parse_dms(t)
		if is_nan(deg):
			bad.append("「%s」不是有效角度：%s（可输 30.5 或 30 30 00）" % [label, t])
			return NAN
		return deg
	bad.append("「%s」输入类型不支持" % label)
	return NAN
