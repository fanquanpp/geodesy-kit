# core/astro/magdecl.gd —— GK-M8-3（F5）磁偏角 WMM（世界地磁模型球谐合成）
#
# 算法移植自 NOAA/NGA 官方 WMM C 程序谱系（WMM_SubLibrary / geomag，美国政府作品，
# 公共领域；本会话经 _scripts 调研留档与官方 WMM2025_TestValues.txt 全部 100 行复核）：
#   1) 大地坐标（WGS84）→ 地心球坐标：p = (h+rc)cosφ，z = (h+rc(1−e²))sinφ，
#      rc = a/√(1−e²sin²φ)，φ' = atan2(z,p)，r = √(p²+z²)；
#   2) Schmidt 半归一化缔合勒让德函数 P̄_n^m(sinφ') 及其对 φ' 导数（递推）；
#   3) 球谐求和（系数 + 年变率内插到 decyear）：
#      B_r = Σ (n+1)(rₑ/r)^(n+2)·[g·cos mλ + h·sin mλ]·P̄
#      X'  = −Σ (rₑ/r)^(n+2)·[g·cos mλ + h·sin mλ]·dP̄/dφ'
#      Y'  = (1/cosφ')·Σ (rₑ/r)^(n+2)·m·[g·sin mλ − h·cos mλ]·P̄
#      其中 rₑ = 6371.2 km（地磁参考半径，官方程序口径，与 WGS84 a=6378.137 不同——
#      这是官方 C 程序的实际行为，经官方测试值逐行验证）；
#   4) 地心 → 大地坐标旋转：d = √(a²cos²φ+b²sin²φ)，ca=(h+d)/r，sa=(a²−b²)cosφ·sinφ/(r·d)，
#      X = X'·ca + Z'·sa，Z = −X'·sa + Z'·ca（Z' = −B_r），Y = Y'；
#   5) D = atan2(Y,X)，I = atan2(Z,√(X²+Y²))，H = √(X²+Y²)，F = √(X²+Y²+Z²)。
#
# 系数数据：data/wmm.json（WMM2025，NGA 官方发布，公共领域；由 app 装载后经 p.coeffs
# 传入——core 不读盘）。本模块本会话已对照官方 WMM2025 测试值 100 行全部吻合
# （D/I ≤0.005°，H/F ≤2 nT），原"SKIP-WMM-DATA"占位升级为正式断言。
class_name GKMagDecl
extends RefCounted

const WGS84_A_KM := 6378.137           # WGS84 赤道半径（km）
const WGS84_B_KM := 6356.7523142       # WGS84 极半径（km）
const REF_RADIUS_KM := 6371.2          # 地磁参考半径 rₑ（官方程序口径）

## flat 系数下标（data/wmm.json 存储顺序 = WMM.COF 行序：(1,0),(1,1),(2,0),…）
static func coef_idx(n: int, m: int) -> int:
	# n(n+1)/2：n ≤ 13 时乘积为精确偶数，浮点除后取整无误
	return int(n * (n + 1) / 2.0) + m - 1

## 日期 → 十进制年（decyear）：年 + (年内序数−1 + 当日小数)/年天数
static func decyear_from_date(year: int, month: int, day: int) -> float:
	var doy := GKTimeSys.day_of_year(year, month, day)
	if doy == 0:
		return NAN
	var days := 366 if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0 else 365
	return float(year) + float(doy - 1) / float(days)

## 系数表自检：data JSON 是否包含本模块所需的完整字段
static func coeffs_valid(c: Dictionary) -> bool:
	if c.is_empty():
		return false
	var n_max := int(c.get("n_max", 0))
	if n_max < 1 or n_max > 13:
		return false
	var need := coef_idx(n_max, n_max) + 1
	for key in ["g", "h", "g_dot", "h_dot"]:
		var arr: Array = c.get(key, [])
		if not (arr is Array) or arr.size() < need:
			return false
	return c.has("epoch")

## 计算入口（§5 协议）
## p: {coeffs（data/wmm.json 内容）, lat_deg, lon_deg, alt_km=0.0,
##     decyear（二选一）或 year/month/day}
static func declination(p: Dictionary) -> Dictionary:
	var c: Dictionary = p.get("coeffs", {})
	if not coeffs_valid(c):
		return _err("WMM 系数数据未就位或格式不符（data/wmm.json 需含 epoch/n_max/g/h/g_dot/h_dot）")
	var lat := float(p.get("lat_deg", NAN))
	var lon := float(p.get("lon_deg", NAN))
	var alt_km := float(p.get("alt_km", 0.0))
	var decyear := float(p.get("decyear", NAN))
	if is_nan(decyear):
		decyear = decyear_from_date(int(p.get("year", 0)), int(p.get("month", 0)), int(p.get("day", 0)))
	if is_nan(decyear):
		return _err("日期非法：无法换算十进制年（检查年月日）")
	if is_nan(lat) or absf(lat) > 90.0:
		return _err("纬度非法：|纬度| ≤ 90°")
	if is_nan(lon) or lon > 180.0 or lon < -180.0:
		return _err("经度非法：−180° ≤ 经度 ≤ 180°（东经为正）")
	if not is_finite(alt_km) or alt_km < -5.0 or alt_km > 1000.0:
		return _err("高程非法：应约在 −5 ~ 1000 km（WGS84 椭球面起算）")
	var epoch := float(c["epoch"])
	var n_max := int(c["n_max"])
	var g: Array = c["g"]
	var h: Array = c["h"]
	var gd: Array = c["g_dot"]
	var hd: Array = c["h_dot"]
	var model := String(c.get("model", "WMM"))
	var warning := ""
	if decyear < epoch or decyear > epoch + 5.0:
		warning = " decyear=%.1f 超出模型有效期 %.1f–%.1f，结果仅供教学参考" % [decyear, epoch, epoch + 5.0]

	# 1) 大地 → 地心球坐标
	var phi := deg_to_rad(lat)
	var sinp := sin(phi)
	var cosp := cos(phi)
	var a2 := WGS84_A_KM * WGS84_A_KM
	var b2 := WGS84_B_KM * WGS84_B_KM
	var e2 := (a2 - b2) / a2
	var rc := WGS84_A_KM / sqrt(1.0 - e2 * sinp * sinp)
	var pp := (alt_km + rc) * cosp
	var zz := (alt_km + rc * (1.0 - e2)) * sinp
	var r := sqrt(pp * pp + zz * zz)
	var phig := atan2(zz, pp)
	var x := sin(phig)          # = cosθ（θ 为余纬）
	var ct := cos(phig)         # = sinθ

	# 2) Schmidt 半归一化勒让德函数与导数（dP̄/dφ'）
	# 用嵌套 Array 而非 Array×PackedFloat64Array：cast 写回陷阱见 core/math/matrix.gd 头注
	var P := []
	var dP := []
	for i in range(n_max + 1):
		var prow := []
		for j in range(n_max + 1):
			prow.append(0.0)   # 显式补 0（resize 留 Nil，读时会是 Nil 而非 0）
		P.append(prow)
		var drow := []
		for j in range(n_max + 1):
			drow.append(0.0)
		dP.append(drow)
	P[0][0] = 1.0
	P[1][0] = x
	dP[1][0] = ct
	P[1][1] = ct
	dP[1][1] = -x
	for n in range(2, n_max + 1):
		for m in range(0, n + 1):
			var pv := 0.0
			var dv := 0.0
			if n == m:
				var k := sqrt((2.0 * n - 1.0) / (2.0 * n))
				pv = ct * k * P[n - 1][n - 1]
				dv = -x * k * P[n - 1][n - 1] + ct * k * dP[n - 1][n - 1]
			elif n - 1 == m:
				var k2 := sqrt(2.0 * n - 1.0)
				pv = x * k2 * P[n - 1][m]
				dv = ct * k2 * P[n - 1][m] + x * k2 * dP[n - 1][m]
			else:
				var k1 := sqrt(float(n * n - m * m))
				var k3 := sqrt((n - 1.0) * (n - 1.0) - m * m)
				pv = ((2.0 * n - 1.0) * x * P[n - 1][m]
						- k3 * P[n - 2][m]) / k1
				dv = ((2.0 * n - 1.0) * (ct * P[n - 1][m]
						+ x * dP[n - 1][m])
						- k3 * dP[n - 2][m]) / k1
			P[n][m] = pv
			dP[n][m] = dv

	# 3) 球谐求和
	var dt := decyear - epoch
	var lam := deg_to_rad(lon)
	var br := 0.0
	var bt := 0.0
	var bl := 0.0
	for n in range(1, n_max + 1):
		for m in range(0, n + 1):
			var i := coef_idx(n, m)
			var gn := float(g[i]) + dt * float(gd[i])
			var hn := float(h[i]) + dt * float(hd[i])
			var cosm := cos(m * lam)
			var sinm := sin(m * lam)
			var cu := gn * cosm + hn * sinm
			var su := gn * sinm - hn * cosm
			var ar2 := pow(REF_RADIUS_KM / r, float(n + 2))
			br += (n + 1.0) * ar2 * cu * P[n][m]
			bt += ar2 * cu * dP[n][m]
			bl += ar2 * m * su * P[n][m] / ct
	var xg := -bt   # 地心北分量
	var yg := bl    # 东分量
	var zg := -br   # 地心下分量

	# 4) 地心 → 大地坐标旋转（官方 ca/sa 精确式）
	var d := sqrt(a2 * cosp * cosp + b2 * sinp * sinp)
	var ca := (alt_km + d) / r
	var sa := (a2 - b2) * cosp * sinp / (r * d)
	var bx := xg * ca + zg * sa
	var bz := -xg * sa + zg * ca
	var by := yg

	# 5) 要素
	var bh := sqrt(bx * bx + by * by)
	var dec := rad_to_deg(atan2(by, bx))
	var inc := rad_to_deg(atan2(bz, bh))
	var f := sqrt(bx * bx + by * by + bz * bz)

	var value := {
		"decl_deg": dec,
		"incl_deg": inc,
		"h_nt": bh,
		"x_nt": bx,
		"y_nt": by,
		"z_nt": bz,
		"f_nt": f,
		"decyear": decyear,
		"model": model,
	}
	if warning != "":
		value["warning"] = warning
	var steps := [
		{"title": "1. 大地坐标 → 地心球坐标（WGS84）",
			"formula": "p=(h+rc)cosφ，z=(h+rc(1−e²))sinφ，rc=a/√(1−e²sin²φ)；φ'=atan2(z,p)，r=√(p²+z²)",
			"substitution": "φ=%.4f°，λ=%.4f°，h=%.2f km" % [lat, lon, alt_km],
			"result": "φ'=%.6f°，r=%.6f km" % [rad_to_deg(phig), r]},
		{"title": "2. Schmidt 半归一化勒让德函数（递推）",
			"formula": "P̄ₙⁿ = sinθ'·√((2n−1)/2n)·P̄ₙ₋₁ⁿ⁻¹；P̄ₙₘ = [(2n−1)cosθ'·P̄ₙ₋₁ₘ − √((n−1)²−m²)·P̄ₙ₋₂ₘ]/√(n²−m²)",
			"substitution": "模型 %s，n_max=%d，系数含年变率内插 Δt=%.3f 年" % [model, n_max, dt],
			"result": "P̄ₙₘ(sinφ')、dP̄ₙₘ/dφ' 计算完成"},
		{"title": "3. 球谐求和（rₑ = %.1f km 官方口径）" % REF_RADIUS_KM,
			"formula": "B_r=Σ(n+1)(rₑ/r)^(n+2)·[g cos+h sin]·P̄；X'=−Σ(rₑ/r)^(n+2)·[g cos+h sin]·dP̄/dφ'；Y'=Σ m(rₑ/r)^(n+2)·[g sin−h cos]·P̄/cosφ'",
			"substitution": "%d 个球谐系数项求和" % (coef_idx(n_max, n_max) + 1),
			"result": "地心分量 X'=%.3f，Y'=%.3f，Z'=%.3f nT" % [xg, yg, zg]},
		{"title": "4. 地心 → 大地坐标旋转",
			"formula": "ca=(h+d)/r，sa=(a²−b²)cosφ·sinφ/(r·d)；X=X'·ca+Z'·sa，Z=−X'·sa+Z'·ca",
			"substitution": "ca=%.9f，sa=%.9f" % [ca, sa],
			"result": "X=%.3f，Y=%.3f，Z=%.3f nT" % [bx, by, bz]},
		{"title": "5. 磁偏角 / 磁倾角 / 强度",
			"formula": "D=atan2(Y,X)，I=atan2(Z,H)，H=√(X²+Y²)，F=√(X²+Y²+Z²)",
			"substitution": "H=%.3f nT" % bh,
			"result": "D=%.4f°（%s），I=%.4f°，F=%.1f nT" % [dec, "东偏" if dec >= 0.0 else "西偏", inc, f]},
	]
	var formula := "WMM 球谐模型（%s，有效期 %.1f–%.1f）；D 正=东偏，真北 = 磁北 + D%s" % [
		model, epoch, epoch + 5.0, warning]
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
