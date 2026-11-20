# core/topics/photogrammetry.gd —— GK-M8-7（I-摄影测量与遥感）
#
# 内容：共线方程正算 / 单像空间后方交会（Gauss-Newton 迭代最小二乘，数值雅可比，
#       与 GKErrProp.propagate 的数值微分口径一致）/ 立体像对前方交会（线性初始化 +
#       迭代精化）/ 航摄设计（比例尺、GSD、地面覆盖、航向基线与旁向间隔）/ 遥感指数
#       （NDVI/EVI/SAVI/NDWI/MNDWI/NDBI/NBR/BAI/VARI/NDSI + 自定义表达式）。
#
# 坐标系约定（与分派权威构造向量自洽，见 _scripts/gen_vectors_b.py）：
#   - 外方位元素 (Xs,Ys,Zs,φ,ω,κ)，φ-ω-κ 主轴系，R = R_φ·R_ω·R_κ，角度单位度（内部弧度）；
#   - 共线方程：x = −f·[a₁(X−Xs)+b₁(Y−Ys)+c₁(Z−Zs)]/[a₃(X−Xs)+b₃(Y−Ys)+c₃(Z−Zs)]（y 同理，
#     aᵢbᵢcᵢ 为 R 的第 1/2/3 列）；天顶摄影 κ=180° 时像点 = (−fX/H, −fY/H)（倒像），
#     与构造向量"物点(±20,±15,0)→像点(∓20,∓15)、比例尺 1:100"一致；
#   - 像平面坐标以主点为原点、f 为焦距（可含 x0/y0 主点坐标）。
#
# 自定义表达式经引擎 Expression 求值：Expression 为引擎核心纯计算类型（无 I/O、非 Node），
# 与地基 GKErrProp 使用 Callable 的口径一致；表达式语法与 M1-7 expression_calc 约定对齐
# （波段变量 b1..bn），M1-7 就位后可平移替换。
#
# 设计约定同 core/astro/solar.gd 头注。
class_name GKPhoto
extends RefCounted

const MAX_ITER := 50
const CONV_TOL := 1e-10

# 内置遥感指数表（bands 为所需波段键；expression 使用波段变量名或 b1..bn）
const DEFAULT_INDEXES := [
	{"key": "NDVI", "name_cn": "归一化植被指数", "bands": ["nir", "red"],
		"expression": "(nir-red)/(nir+red)", "note": "植被长势/覆盖度"},
	{"key": "EVI", "name_cn": "增强型植被指数", "bands": ["nir", "red", "blue"],
		"expression": "2.5*(nir-red)/(nir+6.0*red-7.5*blue+1.0)", "note": "反射率输入（0-1），抗大气与土壤背景"},
	{"key": "SAVI", "name_cn": "土壤调节植被指数", "bands": ["nir", "red"],
		"expression": "1.5*(nir-red)/(nir+red+0.5)", "note": "反射率输入（0-1），L=0.5"},
	{"key": "NDWI", "name_cn": "归一化水体指数(McFeeters)", "bands": ["green", "nir"],
		"expression": "(green-nir)/(green+nir)", "note": "水体提取"},
	{"key": "MNDWI", "name_cn": "改进归一化水体指数(Xu)", "bands": ["green", "swir1"],
		"expression": "(green-swir1)/(green+swir1)", "note": "水体/建筑区分，优于 NDWI"},
	{"key": "NDBI", "name_cn": "归一化建筑指数", "bands": ["swir1", "nir"],
		"expression": "(swir1-nir)/(swir1+nir)", "note": "建成区提取"},
	{"key": "NBR", "name_cn": "归一化燃烧指数", "bands": ["nir", "swir2"],
		"expression": "(nir-swir2)/(nir+swir2)", "note": "火烧迹地/dNBR 变化检测"},
	{"key": "BAI", "name_cn": "燃烧面积指数", "bands": ["red", "nir"],
		"expression": "1.0/((0.1-red)*(0.1-red)+(0.2-nir)*(0.2-nir))", "note": "反射率输入（0-1）"},
	{"key": "VARI", "name_cn": "可见光大气阻抗指数", "bands": ["green", "red", "blue"],
		"expression": "(green-red)/(green+red-blue)", "note": "仅可见光，无人机常用"},
	{"key": "NDSI", "name_cn": "归一化雪指数", "bands": ["green", "swir1"],
		"expression": "(green-swir1)/(green+swir1)", "note": "积雪提取（与 MNDWI 同形，波段位不同）"},
]

## φ-ω-κ 主轴系旋转矩阵 R = R_φ·R_ω·R_κ（3×3 Array×PackedFloat64Array 行主序）
static func rot_matrix(phi_deg: float, omega_deg: float, kappa_deg: float) -> Array:
	var phi := deg_to_rad(phi_deg)
	var om := deg_to_rad(omega_deg)
	var ka := deg_to_rad(kappa_deg)
	var c1 := cos(phi)
	var s1 := sin(phi)
	var c2 := cos(om)
	var s2 := sin(om)
	var c3 := cos(ka)
	var s3 := sin(ka)
	# R_φ·R_ω·R_κ 展开式（摄影测量学教材标准）
	var r11 := c1 * c3 - s1 * s2 * s3
	var r12 := -c1 * s3 - s1 * s2 * c3
	var r13 := s1 * c2
	var r21 := c2 * s3
	var r22 := c2 * c3
	var r23 := -s2
	var r31 := s1 * c3 + c1 * s2 * s3
	var r32 := -s1 * s3 + c1 * s2 * c3
	var r33 := c1 * c2
	return [
		PackedFloat64Array([r11, r12, r13]),
		PackedFloat64Array([r21, r22, r23]),
		PackedFloat64Array([r31, r32, r33]),
	]

## 共线方程正算：物点 → 像平面坐标 [x, y]（w≤0 时返回 [NAN, NAN] 表示该点不在像方）
static func project(ext: Dictionary, pt: Array) -> Array:
	var f := float(ext.get("f", 100.0))
	var x0 := float(ext.get("x0", 0.0))
	var y0 := float(ext.get("y0", 0.0))
	var r := rot_matrix(float(ext.get("phi_deg", 0.0)), float(ext.get("omega_deg", 0.0)), float(ext.get("kappa_deg", 0.0)))
	var dx := float(pt[0]) - float(ext.get("Xs", 0.0))
	var dy := float(pt[1]) - float(ext.get("Ys", 0.0))
	var dz := float(pt[2]) - float(ext.get("Zs", 0.0))
	# R 各列
	var u: float = (r[0] as PackedFloat64Array)[0] * dx + (r[1] as PackedFloat64Array)[0] * dy + (r[2] as PackedFloat64Array)[0] * dz
	var v: float = (r[0] as PackedFloat64Array)[1] * dx + (r[1] as PackedFloat64Array)[1] * dy + (r[2] as PackedFloat64Array)[1] * dz
	var w: float = (r[0] as PackedFloat64Array)[2] * dx + (r[1] as PackedFloat64Array)[2] * dy + (r[2] as PackedFloat64Array)[2] * dz
	if absf(w) < 1e-15:
		return [NAN, NAN]
	return [-f * u / w + x0, -f * v / w + y0]

## 共线方程正算（§5 协议）
## p: {f, Xs, Ys, Zs, phi_deg, omega_deg, kappa_deg, x0=0, y0=0,
##     points: "X,Y,Z;X,Y,Z;..."（物点列表）}
static func collinearity(p: Dictionary) -> Dictionary:
	var ext: Variant = _ext_from(p)
	if ext is String:
		return _err(ext)
	var pts: Variant = _parse_points(String(p.get("points", "")), 3)
	if pts is String:
		return _err(pts)
	var lines := []
	var out_pts := []
	for pt: Array in pts:
		var img := project(ext, pt)
		if is_nan(float(img[0])):
			return _err("物点 (%.3f, %.3f, %.3f) 投影分母为零（射线平行于像面），无法成像" % [float(pt[0]), float(pt[1]), float(pt[2])])
		out_pts.append({"x": float(img[0]), "y": float(img[1])})
		lines.append("(%.3f, %.3f, %.3f) → (%.4f, %.4f)" % [float(pt[0]), float(pt[1]), float(pt[2]), float(img[0]), float(img[1])])
	var value := {"n_points": pts.size()}
	for i in pts.size():
		value["x%d" % (i + 1)] = out_pts[i]["x"]
		value["y%d" % (i + 1)] = out_pts[i]["y"]
	var steps := [
		{"title": "1. 外方位元素与旋转矩阵",
			"formula": "R = R_φ·R_ω·R_κ（φ-ω-κ 主轴系）",
			"substitution": "φ=%.4f°，ω=%.4f°，κ=%.4f°，f=%.3f" % [float(ext["phi_deg"]), float(ext["omega_deg"]), float(ext["kappa_deg"]), float(ext["f"])],
			"result": "R 三列即 aᵢbᵢcᵢ 系数"},
		{"title": "2. 共线方程逐点投影",
			"formula": "x = −f·[a₁(X−Xs)+b₁(Y−Ys)+c₁(Z−Zs)]/[a₃(X−Xs)+b₃(Y−Ys)+c₃(Z−Zs)]（y 用第 2 列）",
			"substitution": "\n".join(lines),
			"result": "%d 个物点已投影" % pts.size()},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "共线方程（中心投影构像方程）；天顶摄影 κ=180° 时像点倒像，比例尺 1:m = f/(H−Z)",
			"error": ""}

## 单像空间后方交会（§5 协议）
## p: {f, x0=0, y0=0, controls: "X,Y,Z,x,y;..."（≥3 个控制点，建议 ≥4）,
##     init_Xs/init_Ys/init_Zs/init_phi_deg/...（可选初值）}
static func resection(p: Dictionary) -> Dictionary:
	var f := float(p.get("f", NAN))
	if not is_finite(f) or f <= 0.0:
		return _err("焦距 f 非法：应为正数（mm 或 m，与控制点像坐标同单位制）")
	var controls: Variant = _parse_controls(String(p.get("controls", "")))
	if controls is String:
		return _err(controls)
	var n: int = controls.size()
	if n < 3:
		return _err("控制点不足：空间后方交会至少需要 3 个平高控制点（6 个观测方程 = 6 个未知数），建议 4 个以上以便检核")
	# 共面守卫：全部控制点共面时外方位存在双解（平面场景不确定性），静默解算会给出
	# 残差为零的错误答案——必须有非共面点组（n=3 时无法判别，在 formula 尾注提示）
	if n >= 4:
		var o: Array = controls[0]
		var v1 := Vector3(float(controls[1][0]) - float(o[0]), float(controls[1][1]) - float(o[1]), float(controls[1][2]) - float(o[2]))
		var v2 := Vector3(float(controls[2][0]) - float(o[0]), float(controls[2][1]) - float(o[1]), float(controls[2][2]) - float(o[2]))
		var scale := maxf(v1.length(), v2.length())
		var coplanar := true
		for i in range(3, n):
			var vi := Vector3(float(controls[i][0]) - float(o[0]), float(controls[i][1]) - float(o[1]), float(controls[i][2]) - float(o[2]))
			scale = maxf(scale, vi.length())
			if absf(v1.cross(v2).dot(vi)) > 1e-6 * scale * scale * scale:
				coplanar = false
				break
		if coplanar:
			return _err("控制点全部共面：平面场景下外方位元素存在双解（残差可能为零但解不唯一），请加入不同高度的控制点")
	# 初值：控制点质心 + 摄影估算航高；κ 存在 0°/180°（正像/倒像）两个收敛盆地，
	# 天顶倒像摄影（κ≈180°）从 κ=0 初值出发法方程奇异 —— 多初值策略：
	# 用户给定 init_phi/omega/kappa 时按用户初值单次解算，否则 κ₀∈{0,90,180,270} 各试
	# 一次并取像点残差 RMS 最小者（教学工具的稳健性处理，诚实标注于 formula）。
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	for c: Array in controls:
		cx += float(c[0]); cy += float(c[1]); cz += float(c[2])
	cx /= n; cy /= n; cz /= n
	var d_obj := 0.0
	var d_img := 0.0
	for c: Array in controls:
		d_obj = maxf(d_obj, sqrt(pow(float(c[0]) - cx, 2.0) + pow(float(c[1]) - cy, 2.0)))
		d_img = maxf(d_img, sqrt(pow(float(c[3]) - float(p.get("x0", 0.0)), 2.0) + pow(float(c[4]) - float(p.get("y0", 0.0)), 2.0)))
	var z_init := float(p.get("init_Zs", NAN))
	if not is_finite(z_init):
		z_init = cz + (f * d_obj / d_img if d_img > 1e-12 else 1000.0 * f)
	var x0 := float(p.get("x0", 0.0))
	var y0 := float(p.get("y0", 0.0))
	var best_res: Variant = null
	var best_rms := INF
	var iters := 0
	if p.has("init_phi_deg") or p.has("init_omega_deg") or p.has("init_kappa_deg"):
		var par0 := PackedFloat64Array([
			float(p.get("init_Xs", cx)), float(p.get("init_Ys", cy)), z_init,
			deg_to_rad(float(p.get("init_phi_deg", 0.0))),
			deg_to_rad(float(p.get("init_omega_deg", 0.0))),
			deg_to_rad(float(p.get("init_kappa_deg", 0.0))),
		])
		var box0 := []
		var res0: Variant = _gn_solve(par0, controls, f, x0, y0, 6, box0)
		if res0 is String:
			return _err(res0)
		best_res = res0
		best_rms = float(res0[0])
		iters = int(box0[0]) if not box0.is_empty() else 0
	else:
		for kappa0: float in [0.0, 90.0, 180.0, 270.0]:
			var park := PackedFloat64Array([cx, cy, z_init, 0.0, 0.0, deg_to_rad(kappa0)])
			var boxk := []
			var resk: Variant = _gn_solve(park, controls, f, x0, y0, 6, boxk)
			if resk is String:
				continue
			var rmsk: float = float(resk[0])
			if rmsk < best_rms:
				best_rms = rmsk
				best_res = resk
				iters = int(boxk[0]) if not boxk.is_empty() else 0
	if best_res == null:
		return _err("多初值下法方程均奇异：控制点几何不佳（近于共线/共圆或过分集中），请调整控制点布置")
	var rms: float = best_rms
	var par_out: PackedFloat64Array = best_res[1]
	var value := {
		"Xs_m": par_out[0], "Ys_m": par_out[1], "Zs_m": par_out[2],
		"phi_deg": rad_to_deg(par_out[3]), "omega_deg": rad_to_deg(par_out[4]), "kappa_deg": rad_to_deg(par_out[5]),
		"rms_px": rms,
		"iters": iters,
		"n_points": n,
	}
	var steps := [
		{"title": "1. 初值",
			"formula": "Xs⁰/Ys⁰ = 控制点质心；Zs⁰ = Z̄ + f·D物/D像",
			"substitution": "质心 (%.3f, %.3f, %.3f)，D物=%.3f，D像=%.3f" % [cx, cy, cz, d_obj, d_img],
			"result": "(%.4f, %.4f, %.4f)" % [par_out[0], par_out[1], par_out[2]]},
		{"title": "2. 迭代最小二乘（Gauss-Newton，数值雅可比）",
			"formula": "v = 共线方程计算值 − 观测值；JᵀJ·Δ = −Jᵀv（6 未知数：Xs,Ys,Zs,φ,ω,κ）",
			"substitution": "%d 个控制点 → %d 个观测方程" % [n, 2 * n],
			"result": "迭代 %d 次收敛，像点残差 RMS = %.6f" % [iters, rms]},
		{"title": "3. 外方位元素解",
			"formula": "Xs=%.4f，Ys=%.4f，Zs=%.4f，φ=%.4f°，ω=%.4f°，κ=%.4f°",
			"substitution": "6 个未知数",
			"result": "已输出到结果区（角度为 φ-ω-κ 主轴系）"},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "单像空间后方交会（共线方程线性化迭代 LS，κ 多初值取残差最小解）；n=3 无多余观测，控制点须非共面，建议 ≥4 点检核粗差",
			"error": ""}

## 立体像对前方交会（§5 协议）
## p: {f, ext_left: {Xs,Ys,Zs,phi_deg,omega_deg,kappa_deg}, pt_left: "x,y",
##     ext_right: 同构, pt_right: "x,y", x0/y0 可选}
static func forward_intersection(p: Dictionary) -> Dictionary:
	var f := float(p.get("f", NAN))
	if not is_finite(f) or f <= 0.0:
		return _err("焦距 f 非法：应为正数")
	var e1: Variant = _ext_from(p.get("ext_left", {}) if p.get("ext_left", {}) is Dictionary else {})
	if e1 is String:
		return _err("左片外方位：" + e1)
	var e2: Variant = _ext_from(p.get("ext_right", {}) if p.get("ext_right", {}) is Dictionary else {})
	if e2 is String:
		return _err("右片外方位：" + e2)
	var pl: Variant = _parse_pair(String(p.get("pt_left", "")))
	if pl is String:
		return _err("左片像点：" + pl)
	var pr: Variant = _parse_pair(String(p.get("pt_right", "")))
	if pr is String:
		return _err("右片像点：" + pr)
	var x0 := float(p.get("x0", 0.0))
	var y0 := float(p.get("y0", 0.0))
	# 线性初始化：像方光线方向 d = R·[x−x0, y−y0, −f]ᵀ，X = Xs + λ·dx（λ1/λ2 为未知数）
	var d1 := _ray_dir(e1, float(pl[0]) - x0, float(pl[1]) - y0)
	var d2 := _ray_dir(e2, float(pr[0]) - x0, float(pr[1]) - y0)
	if d1.is_empty() or d2.is_empty():
		return _err("像方光线方向退化")
	var a := []
	var b := PackedFloat64Array()
	# X − λ1·dx1 = Xs1；X − λ2·dx2 = Xs2（Y/Z 同理）
	for k in 3:
		var r1 := PackedFloat64Array([0.0, 0.0, 0.0, -d1[k], 0.0])
		r1[k] = 1.0
		a.append(r1)
		b.append(float(e1[["Xs", "Ys", "Zs"][k]]))
		var r2 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, -d2[k]])
		r2[k] = 1.0
		a.append(r2)
		b.append(float(e2[["Xs", "Ys", "Zs"][k]]))
	var ata := GKMatrix.multiply(GKMatrix.transpose(a), a)
	var atb := GKMatrix.mat_vec(GKMatrix.transpose(a), b)
	if ata.is_empty() or atb.is_empty():
		return _err("线性初始化方程组退化（像对基线近于零或光线平行）")
	var sol := GKMatrix.solve(ata, atb)
	if sol.is_empty():
		return _err("线性初始化无解：检查两片外方位与像点输入（光线不相交）")
	var par := PackedFloat64Array([sol[0], sol[1], sol[2]])
	var obs := [[float(pl[0]), float(pl[1])], [float(pr[0]), float(pr[1])]]
	var exts := [e1, e2]
	var iters_box := []
	var res: Variant = _gn_solve_xyz(par, obs, exts, f, x0, y0, iters_box)
	if res is String:
		return _err(res)
	var iters: int = iters_box[0] if not iters_box.is_empty() else 0
	var rms: float = res[0]
	var par_out: PackedFloat64Array = res[1]
	var value := {
		"X_m": par_out[0], "Y_m": par_out[1], "Z_m": par_out[2],
		"rms_px": rms,
		"iters": iters,
		"ray_scale_left": sol[3],
		"ray_scale_right": sol[4],
	}
	var steps := [
		{"title": "1. 像方光线方向（地面坐标系）",
			"formula": "d = R·[x−x0, y−y0, −f]ᵀ",
			"substitution": "左 (%.4f, %.4f)，右 (%.4f, %.4f)" % [float(pl[0]), float(pl[1]), float(pr[0]), float(pr[1])],
			"result": "d₁=(%.4f, %.4f, %.4f)，d₂=(%.4f, %.4f, %.4f)" % [d1[0], d1[1], d1[2], d2[0], d2[1], d2[2]]},
		{"title": "2. 线性化初值（含射线比例因子 λ）",
			"formula": "X = Xs + λ·dx（5 未知数 LS：X,Y,Z,λ₁,λ₂）",
			"substitution": "法方程 5×5 求解",
			"result": "初值 (%.4f, %.4f, %.4f)，λ₁=%.4f，λ₂=%.4f" % [par[0], par[1], par[2], sol[3], sol[4]]},
		{"title": "3. 迭代精化（共线方程 LS）",
			"formula": "4 个共线方程对 (X,Y,Z) 线性化迭代",
			"substitution": "迭代 %d 次" % iters,
			"result": "物方点 (%.4f, %.4f, %.4f)，残差 RMS = %.6f" % [par_out[0], par_out[1], par_out[2], rms]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "立体像对前方交会（光线前方交会 + 共线方程迭代 LS）",
			"error": ""}

## 航摄设计（§5 协议）
## p: {f_m 焦距(m), pixel_um 像元(μm), img_w_px, img_h_px, H_m 相对航高,
##     forward_overlap 航向重叠度(0-1), side_overlap 旁向重叠度(0-1),
##     area_w_m/area_h_m 可选（测区宽/长，估算像片数与航线数）}
static func flight_design(p: Dictionary) -> Dictionary:
	var f := float(p.get("f_m", NAN))
	var pixel := float(p.get("pixel_um", NAN)) * 1e-6
	var w_px := float(p.get("img_w_px", NAN))
	var h_px := float(p.get("img_h_px", NAN))
	var h_flight := float(p.get("H_m", NAN))
	var fwd := float(p.get("forward_overlap", NAN))
	var side := float(p.get("side_overlap", NAN))
	if not is_finite(f) or f <= 0.0:
		return _err("焦距 f 非法：应为正（米）")
	if not is_finite(pixel) or pixel <= 0.0:
		return _err("像元尺寸非法：应为正（微米）")
	if not is_finite(w_px) or not is_finite(h_px) or w_px < 1.0 or h_px < 1.0:
		return _err("影像行列数非法：应为正像素数")
	if not is_finite(h_flight) or h_flight <= 0.0:
		return _err("相对航高 H 非法：应为正（米，相对摄区基准面）")
	if not is_finite(fwd) or fwd < 0.0 or fwd >= 1.0 or not is_finite(side) or side < 0.0 or side >= 1.0:
		return _err("重叠度非法：航向/旁向重叠度应在 [0, 1)（常用航向 0.60~0.65、旁向 0.30~0.35）")
	var scale := h_flight / f
	var gsd := pixel * scale
	var cov_w := w_px * gsd
	var cov_h := h_px * gsd
	var baseline := cov_w * (1.0 - fwd)
	var strip_gap := cov_h * (1.0 - side)
	var value := {
		"scale_denom": scale,          # 1:m 的 m
		"gsd_m": gsd,
		"coverage_w_m": cov_w,
		"coverage_h_m": cov_h,
		"baseline_m": baseline,        # 航向摄影基线
		"strip_gap_m": strip_gap,      # 旁向航线间隔
	}
	var extra := ""
	var has_area := p.has("area_w_m") and p.has("area_h_m")
	if has_area:
		var aw := float(p.get("area_w_m", NAN))
		var ah := float(p.get("area_h_m", NAN))
		if not is_finite(aw) or not is_finite(ah) or aw <= 0.0 or ah <= 0.0:
			return _err("测区宽/长非法：应为正（米）")
		# 航线沿宽方向敷设：每条航线照片数 = ceil((长 − 覆盖)/基线)+1，航线数 = ceil((宽 − 覆盖)/间隔)+1
		var n_photo := int(ceil(maxf((ah - cov_w), 0.0) / baseline)) + 1
		var n_line := int(ceil(maxf((aw - cov_h), 0.0) / strip_gap)) + 1
		value["photos_per_line"] = n_photo
		value["lines"] = n_line
		value["photos_total"] = n_photo * n_line
		extra = "，航线沿测区长边方向敷设估算"
	var steps := [
		{"title": "1. 摄影比例尺与 GSD",
			"formula": "1:m = 1:(H/f)；GSD = 像元×H/f",
			"substitution": "H=%.1f m，f=%.4f m，像元=%.1f μm" % [h_flight, f, pixel * 1e6],
			"result": "1:%.1f，GSD = %.4f m" % [scale, gsd]},
		{"title": "2. 单片地面覆盖",
			"formula": "覆盖宽 = 行×GSD，覆盖高 = 列×GSD",
			"substitution": "%.0f×%.4f 与 %.0f×%.4f" % [w_px, gsd, h_px, gsd],
			"result": "%.2f m × %.2f m" % [cov_w, cov_h]},
		{"title": "3. 航向基线与旁向航线间隔",
			"formula": "B = 覆盖宽×(1−航向重叠)；D = 覆盖高×(1−旁向重叠)",
			"substitution": "航向重叠 %.0f%%，旁向重叠 %.0f%%" % [fwd * 100.0, side * 100.0],
			"result": "B = %.2f m，D = %.2f m%s" % [baseline, strip_gap, extra]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "航摄设计基本关系：1:m=H/f，GSD=像元·H/f，B=覆盖×(1−P航向)，D=覆盖×(1−P旁向)",
			"error": ""}

## 遥感指数（§5 协议）
## p: {bands: {red:0.2, nir:0.8, ...}（键名见 DEFAULT_INDEXES.bands）,
##     custom_expression 可选（变量 b1..bn），custom_bands 可选（b1..bn 对应的波段名数组）}
static func remote_index(p: Dictionary) -> Dictionary:
	var bands_v: Variant = p.get("bands", {})
	if not (bands_v is Dictionary) or (bands_v as Dictionary).is_empty():
		return _err("缺少波段值：请至少提供 red/nir 等波段反射率或 DN")
	var bands: Dictionary = bands_v
	for k: String in bands.keys():
		if not is_finite(float(bands[k])):
			return _err("波段 %s 数值非法" % k)
	var value := {}
	var used := []
	for idx: Dictionary in DEFAULT_INDEXES:
		var ok_all := true
		var vars := {}
		for bk: String in idx["bands"]:
			if bands.has(bk):
				vars[bk] = float(bands[bk])
			else:
				ok_all = false
				break
		if not ok_all:
			continue
		var v: Variant = _eval_expression(String(idx["expression"]), vars)
		if v is String:
			continue  # 分母为零等 → 该指数跳过（结果中注明）
		value[String(idx["key"])] = v
		used.append(String(idx["key"]))
	if used.is_empty() and not p.has("custom_expression"):
		return _err("提供的波段不足以计算任何内置指数（常见需 red+nir）")
	var steps := []
	for k: String in used:
		for idx: Dictionary in DEFAULT_INDEXES:
			if String(idx["key"]) == k:
				steps.append({"title": "%s（%s）" % [k, idx["name_cn"]],
					"formula": String(idx["expression"]),
					"substitution": String(idx["note"]),
					"result": "%.9f" % float(value[k])})
	var formula := "遥感指数（归一化比值类，输入线性反射率/DN；BAI/EVI/SAVI 需 0-1 反射率）"
	if p.has("custom_expression"):
		var expr := String(p["custom_expression"])
		var vars := {}
		var names: Array = p.get("custom_bands", [])
		var idx := 1
		for nm: Variant in names:
			if bands.has(String(nm)):
				vars["b%d" % idx] = float(bands[String(nm)])
			idx += 1
		if vars.is_empty():
			return _err("自定义表达式缺少波段映射：请提供 custom_bands 数组（b1..bn 依次对应）")
		var cv: Variant = _eval_expression(expr, vars)
		if cv is String:
			return _err(cv)
		value["custom_index"] = cv
		steps.append({"title": "自定义表达式", "formula": expr,
			"substitution": "变量：" + ", ".join(vars.keys()),
			"result": "%.9f" % cv})
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 单个指数求值（静态接口，供测试与外部复用）：失败返回错误文本
static func eval_index(expression: String, vars: Dictionary) -> Variant:
	return _eval_expression(expression, vars)

# ---------- 内部工具 ----------

## 数值雅可比 Gauss-Newton（中差分，与 GKErrProp.propagate 微分口径一致）
## 后方交会：未知数 par[0..5] = Xs,Ys,Zs,φ,ω,κ（controls != null，焦距固定 f_fixed）；
## 前方交会：未知数 par[0..2] = X,Y,Z（controls == null，按片用 exts 外方位）。
## 成功返回 RMS（像元），失败返回错误文本；迭代次数经 iters_box 数组传出。
static func _gn_solve(par: PackedFloat64Array, controls: Array, f: float,
		x0: float, y0: float, n_unknown: int, iters_box: Array) -> Variant:
	var obs := []
	for c: Array in controls:
		obs.append([float(c[3]), float(c[4])])
	return _gn_core(par, obs, [], controls, f, x0, y0, n_unknown, iters_box)

static func _gn_solve_xyz(par: PackedFloat64Array, obs: Array, exts: Array,
		f: float, x0: float, y0: float, iters_box: Array) -> Variant:
	return _gn_core(par, obs, exts, null, f, x0, y0, 3, iters_box)

static func _gn_core(par: PackedFloat64Array, obs: Array, exts: Array,
		controls: Variant, f: float, x0: float, y0: float,
		n_unknown: int, iters_box: Array) -> Variant:
	var n := obs.size()
	var m := 2 * n
	var p_cur := PackedFloat64Array(par)
	var rms_last := _residual_rms(p_cur, obs, exts, controls, f, x0, y0)
	if not is_finite(rms_last):
		return "迭代初值下残差非有限（投影分母为零），请检查输入"
	var iters := 0
	for iter in MAX_ITER:
		iters = iter + 1
		var res := _residuals(p_cur, obs, exts, controls, f, x0, y0)
		# 数值雅可比（按列：中差分）
		var jac := []
		for u in n_unknown:
			var h := 1e-6 * maxf(1.0, absf(p_cur[u]))
			var pp := PackedFloat64Array(p_cur)
			var pm := PackedFloat64Array(p_cur)
			pp[u] = p_cur[u] + h
			pm[u] = p_cur[u] - h
			var rp := _residuals(pp, obs, exts, controls, f, x0, y0)
			var rm := _residuals(pm, obs, exts, controls, f, x0, y0)
			var col := PackedFloat64Array()
			col.resize(m)
			for k in m:
				col[k] = (rp[k] - rm[k]) / (2.0 * h)
			jac.append(col)
		# 法方程 JᵀJ·Δ = −Jᵀv
		var jtj := []   # 嵌套 Array（cast 写回陷阱，见 core/math/matrix.gd 头注）
		var jtr := PackedFloat64Array()
		jtr.resize(n_unknown)
		for u in n_unknown:
			var row := []
			row.resize(n_unknown)
			jtj.append(row)
			jtr[u] = 0.0
		for u in n_unknown:
			for v2 in n_unknown:
				var s := 0.0
				for k in m:
					s += (jac[u] as PackedFloat64Array)[k] * (jac[v2] as PackedFloat64Array)[k]
				jtj[u][v2] = s
			var sr := 0.0
			for k in m:
				sr += (jac[u] as PackedFloat64Array)[k] * res[k]
			jtr[u] = -sr   # 法方程 JᵀJ·Δ = −Jᵀv（残差 v = 计算 − 观测）
		var delta := GKMatrix.solve(jtj, jtr)
		if delta.is_empty():
			return "法方程奇异：点几何不佳（控制点共线或近于共圆），无法解算"
		var p_new := PackedFloat64Array(p_cur)
		for u in n_unknown:
			p_new[u] = p_cur[u] + delta[u]
		var rms_new := _residual_rms(p_new, obs, exts, controls, f, x0, y0)
		# 步长控制：RMS 增大则折半步长（最多 5 次）
		var tries := 0
		while is_finite(rms_new) and rms_new > rms_last and tries < 5:
			tries += 1
			for u in n_unknown:
				p_new[u] = p_cur[u] + delta[u] * pow(0.5, float(tries))
			rms_new = _residual_rms(p_new, obs, exts, controls, f, x0, y0)
		if not is_finite(rms_new):
			return "迭代发散（残差非有限）：请检查输入数据"
		var maxd := 0.0
		for u in n_unknown:
			maxd = maxf(maxd, absf(p_new[u] - p_cur[u]))
		p_cur = p_new
		rms_last = rms_new
		if maxd < CONV_TOL:
			break
	iters_box.append(iters)
	return [rms_last, p_cur]   # PackedFloat64Array 传参为拷贝，须把收敛参数带出（trap：直接改 par 无效）

## 残差向量（像元）：后方交会（controls != null）或前方交会（controls == null）
static func _residuals(par: PackedFloat64Array, obs: Array, exts: Array,
		controls: Variant, f: float, x0: float, y0: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if controls != null:
		var ext := {"f": f, "x0": x0, "y0": y0,
			"Xs": par[0], "Ys": par[1], "Zs": par[2],
			"phi_deg": rad_to_deg(par[3]), "omega_deg": rad_to_deg(par[4]), "kappa_deg": rad_to_deg(par[5])}
		for c: Array in controls:
			var img := project(ext, [c[0], c[1], c[2]])
			out.append(float(img[0]) - float(c[3]))
			out.append(float(img[1]) - float(c[4]))
	else:
		for i in obs.size():
			var e: Dictionary = exts[i]
			var e2 := {}
			for k: String in e.keys():
				e2[k] = e[k]
			e2["f"] = f
			e2["x0"] = x0
			e2["y0"] = y0
			var img := project(e2, [par[0], par[1], par[2]])
			out.append(float(img[0]) - float(obs[i][0]))
			out.append(float(img[1]) - float(obs[i][1]))
	return out

static func _residual_rms(par: PackedFloat64Array, obs: Array, exts: Array,
		controls: Variant, f: float, x0: float, y0: float) -> float:
	var res := _residuals(par, obs, exts, controls, f, x0, y0)
	var s := 0.0
	for v in res:
		if not is_finite(v):
			return INF
		s += v * v
	return sqrt(s / float(res.size()))

## 像方光线方向 d = R·[x, y, −f]ᵀ（地面坐标系，未归一化）
static func _ray_dir(ext: Dictionary, x: float, y: float) -> PackedFloat64Array:
	var f := float(ext.get("f", 100.0))
	var r := rot_matrix(float(ext.get("phi_deg", 0.0)), float(ext.get("omega_deg", 0.0)), float(ext.get("kappa_deg", 0.0)))
	var v := PackedFloat64Array([x, y, -f])
	var out := PackedFloat64Array()
	out.resize(3)
	for i in 3:
		var s := 0.0
		for j in 3:
			s += (r[i] as PackedFloat64Array)[j] * v[j]
		out[i] = s
	return out

## 外方位元素字典校验与默认值
static func _ext_from(p: Dictionary) -> Variant:
	var f := float(p.get("f", NAN))
	if not is_finite(f) or f <= 0.0:
		return "焦距 f 非法：应为正数"
	for key in ["Xs", "Ys", "Zs", "phi_deg", "omega_deg", "kappa_deg"]:
		if not is_finite(float(p.get(key, NAN))):
			return "外方位元素缺失或非法：%s" % key
	return {
		"f": f,
		"x0": float(p.get("x0", 0.0)), "y0": float(p.get("y0", 0.0)),
		"Xs": float(p["Xs"]), "Ys": float(p["Ys"]), "Zs": float(p["Zs"]),
		"phi_deg": float(p["phi_deg"]), "omega_deg": float(p["omega_deg"]), "kappa_deg": float(p["kappa_deg"]),
	}

## 解析 "X,Y,Z;X,Y,Z;..." 物点列表（每组 3 个数）
static func _parse_points(text: String, per: int) -> Variant:
	var t := text.strip_edges().replace("，", ",").replace("；", ";").replace(" ", "")
	if t.is_empty():
		return "物点列表为空：格式应为 X,Y,Z;X,Y,Z;…"
	for rec in t.split(";", false):
		var parts: PackedStringArray = rec.split(",")
		if parts.size() != per:
			return "物点格式错误（应为每组 %d 个数，逗号分隔）：%s" % [per, rec]
		for s in parts:
			if not s.is_valid_float():
				return "物点含非数值字段：%s" % rec
	var out := []
	for rec in t.split(";", false):
		var parts: PackedStringArray = rec.split(",")
		var row := []
		for s in parts:
			row.append(s.to_float())
		out.append(row)
	return out

## 解析 "X,Y,Z,x,y;..." 控制点列表（每组 5 个数）
static func _parse_controls(text: String) -> Variant:
	var pts: Variant = _parse_points(text, 5)
	if pts is String:
		if String(pts).contains("每组 3"):
			return "控制点格式错误：应为 X,Y,Z,x,y（物方 3 坐标 + 像点 2 坐标），分号分隔"
		return pts
	return pts

## 解析 "x,y"
static func _parse_pair(text: String) -> Variant:
	var pts: Variant = _parse_points(text, 2)
	if pts is String:
		return "格式应为 x,y（像平面坐标）"
	if (pts as Array).size() != 1:
		return "只需一个像点 x,y"
	return pts[0]

## 表达式求值（引擎 Expression；变量名 k=v）。失败返回错误文本。
static func _eval_expression(expression: String, vars: Dictionary) -> Variant:
	var expr := Expression.new()
	var names := PackedStringArray()
	var values := PackedFloat64Array()
	for k: String in vars.keys():
		names.append(k)
		values.append(float(vars[k]))
	var err := expr.parse(expression, names)
	if err != OK:
		return "表达式解析失败：%s（%s）" % [expression, expr.get_error_text()]
	var result: Variant = expr.execute(values, null, true)
	if expr.has_execute_failed():
		return "表达式计算失败：%s（%s）" % [expression, expr.get_error_text()]
	if not (result is float or result is int):
		return "表达式结果不是数值：%s" % expression
	var v := float(result)
	if not is_finite(v):
		return "表达式结果非有限值（可能分母为零）：%s" % expression
	return v

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
