# core/ellipsoid/ellipsoid.gd —— 椭球常数库（CGCS2000 / 克拉索夫斯基 / IUGG75 / WGS84 / GRS80 等）
#
# 设计约定（docs/ARCHITECTURE.md §1.1 / §4）：
#   - 纯静态函数、零引擎依赖（extends RefCounted）；只存几何常数（a、1/f），
#     物理常数（GM、ω、J2）不在本类职责内（M2 施工时按需扩展，只增不改）；
#   - 派生量全部由 a、f 计算，避免手抄错（DEVELOPMENT_PLAN.md §5 原则）：
#       b = a(1−f)；e² = 2f − f²；e′² = e²/(1−e²)
#   - 未知名查表失败返回 {}，调用方判空。
class_name GKEllipsoid
extends RefCounted

# 内置椭球：inv_f = 1/f（扁率倒数）。数值取自各标准官方文本。
const BUILTIN := {
	"CGCS2000": {
		"name_cn": "CGCS2000（2000 国家大地坐标系）",
		"a": 6378137.0,
		"inv_f": 298.257222101,  # GB 22021-2008
		"source": "GB 22021-2008 国家大地测量基本技术规定",
	},
	"GRS80": {
		"name_cn": "GRS80（IUGG 1979）",
		"a": 6378137.0,
		"inv_f": 298.257222101,  # 理论值 1/f=298.257222100882711，惯用 6 位截断值
		"source": "IUGG 1979 莫尔比奥决议（Geodetic Reference System 1980）",
	},
	"WGS84": {
		"name_cn": "WGS84",
		"a": 6378137.0,
		"inv_f": 298.257223563,  # NIMA TR8350.2
		"source": "NIMA TR8350.2（美国国家影像与测绘局）",
	},
	"KRASOVSKY": {
		"name_cn": "克拉索夫斯基椭球（北京 54）",
		"a": 6378245.0,
		"inv_f": 298.3,
		"source": "克拉索夫斯基 1940（苏联 1942 坐标系 / 北京 54 采用）",
	},
	"IUGG75": {
		"name_cn": "IUGG 1975（西安 80 / IAG-75）",
		"a": 6378140.0,
		"inv_f": 298.257,
		"source": "IUGG 1975 决议（1980 西安坐标系采用）",
	},
	"INTERNATIONAL1924": {
		"name_cn": "International 1924（海福特椭球）",
		"a": 6378388.0,
		"inv_f": 297.0,
		"source": "IUGG 1924 马德里决议（经典 UTM 采用）",
	},
}

## 内置椭球键名列表（稳定顺序：中国常用在前）
static func list_builtin() -> Array:
	return ["CGCS2000", "GRS80", "WGS84", "KRASOVSKY", "IUGG75", "INTERNATIONAL1924"]

## 按名取内置椭球参数（含派生量）。未知名返回 {}。
static func params(name: String) -> Dictionary:
	if not BUILTIN.has(name):
		return {}
	var base: Dictionary = BUILTIN[name]
	var d := derived(base.a, base.inv_f)
	if d.is_empty():
		return {}
	d["name_cn"] = base["name_cn"]
	d["source"] = base["source"]
	return d

## 由 a、1/f 计算派生几何量：{a, inv_f, f, b, e2, ep2}。
## 校验：a>0、inv_f>0，失败返回 {}。
static func derived(a: float, inv_f: float) -> Dictionary:
	if not (is_finite(a) and is_finite(inv_f)) or a <= 0.0 or inv_f <= 0.0:
		return {}
	var f := 1.0 / inv_f
	var b := a * (1.0 - f)
	var e2 := 2.0 * f - f * f
	var ep2 := e2 / (1.0 - e2)
	return {
		"a": a,
		"inv_f": inv_f,
		"f": f,
		"b": b,
		"e2": e2,
		"ep2": ep2,
	}


# ---------------------------------------------------------------------------
# M2 施工追加（只增不改）：曲率半径与弧长派生量
# ---------------------------------------------------------------------------

const ARC_TERMS := 10  # 子午线弧长级数项数；e^(2k) 在 k=10 时 < 1e-25，截断误差远小于 1 纳米

## 卯酉圈曲率半径 N(B) = a/√(1−e²·sin²B)（米）。非法输入返回 NAN。
static func radius_prime_vertical(a: float, e2: float, lat_deg: float) -> float:
	if not _arc_input_ok(a, e2, lat_deg):
		return NAN
	var s := sin(deg_to_rad(lat_deg))
	return a / sqrt(1.0 - e2 * s * s)


## 子午圈曲率半径 M(B) = a(1−e²)/(1−e²·sin²B)^(3/2)（米）。非法输入返回 NAN。
static func radius_meridian(a: float, e2: float, lat_deg: float) -> float:
	if not _arc_input_ok(a, e2, lat_deg):
		return NAN
	var s := sin(deg_to_rad(lat_deg))
	var w := 1.0 - e2 * s * s
	return a * (1.0 - e2) / (w * sqrt(w))


## 子午线弧长 X(B)：赤道起沿子午圈到纬度 B 的弧长（米）。
## 级数：X = a(1−e²)·Σ_k c_k·e^(2k)·I_k(B)，其中 c_k=(2k+1)!!/(2k)!! 来自
## (1−e²sin²B)^(−3/2) 二项式展开；I_k(B)=∫₀^B sin^(2k)u·du 递推求积。
## 精度：截断误差 < 1e-9 m（ARC_TERMS=10）；与 pyproj Geod 沿子午线大地线长度一致。
## 非法输入（a<=0、e2 越界、|B|>90）返回 NAN。
static func meridian_arc(a: float, e2: float, lat_deg: float) -> float:
	if not _arc_input_ok(a, e2, lat_deg):
		return NAN
	var b_rad := deg_to_rad(lat_deg)
	var sb := sin(b_rad)
	var cb := cos(b_rad)
	var m0 := a * (1.0 - e2)
	var ik := b_rad            # I_0 = B
	var ck := 1.0              # (2k+1)!!/(2k)!!
	var ek := 1.0              # e2^k
	var s := ik
	for k in range(1, ARC_TERMS + 1):
		var sk := sb
		for _j in range(2 * k - 2):
			sk *= sb           # sin^(2k-1)B
		ik = (2.0 * k - 1.0) / (2.0 * k) * ik - sk * cb / (2.0 * k)
		ck = ck * (2.0 * k + 1.0) / (2.0 * k)
		ek *= e2
		s += ck * ek * ik
	return m0 * s


## 子午线弧长反解：由赤道起算的弧长 x（米）反求纬度 B（度）。
## Newton 迭代 B -= (X(B)−x)/M(B)，最多 12 轮，收敛判据 |ΔB| < 1e-13 rad。
## 未收敛或非法输入返回 NAN。
static func meridian_arc_inverse(a: float, e2: float, arc_m: float) -> float:
	if not is_finite(a) or not is_finite(e2) or not is_finite(arc_m):
		return NAN
	if a <= 0.0 or e2 < 0.0 or e2 >= 1.0:
		return NAN
	var b_rad := arc_m / a  # 初值（X(B)/B ≤ a，略偏小，Newton 单调收敛）
	for _i in range(12):
		var x := meridian_arc(a, e2, rad_to_deg(b_rad))
		var dm := radius_meridian(a, e2, rad_to_deg(b_rad))
		if not (is_finite(x) and is_finite(dm)) or dm == 0.0:
			return NAN
		var step := (x - arc_m) / dm
		b_rad -= step
		if b_rad > PI / 2.0:
			b_rad = PI / 2.0
		elif b_rad < -PI / 2.0:
			b_rad = -PI / 2.0
		if absf(step) < 1e-13:
			return rad_to_deg(b_rad)
	return rad_to_deg(b_rad)


## 平行圈弧长：纬度 B 处经差 ΔL 的平行圈弧长 = N·cosB·ΔL(rad)（米）。
## |B|>90 或非法输入返回 NAN。
static func parallel_arc(a: float, e2: float, lat_deg: float, dlon_deg: float) -> float:
	if not _arc_input_ok(a, e2, lat_deg) or not is_finite(dlon_deg):
		return NAN
	var n := radius_prime_vertical(a, e2, lat_deg)
	return n * cos(deg_to_rad(lat_deg)) * deg_to_rad(dlon_deg)


## 平均半径 R1 = (2a+b)/3（GeographicLib 约定；WGS84 = 6371008.7714 m）。
static func mean_radius(a: float, b: float) -> float:
	if not (is_finite(a) and is_finite(b)) or a <= 0.0 or b <= 0.0:
		return NAN
	return (2.0 * a + b) / 3.0


## 等面积半径 R2（米）。由 c2 = R2² = (a² + b²·atanh(E)/E)/2，E=√e²。
## e2=0 时退化为球（atanh 项取 b²）。非法输入返回 NAN。
static func authalic_radius(a: float, e2: float) -> float:
	if not is_finite(a) or not is_finite(e2) or a <= 0.0 or e2 < 0.0 or e2 >= 1.0:
		return NAN
	var b := a * sqrt(1.0 - e2)
	if e2 == 0.0:
		return sqrt(a * a / 2.0 + b * b / 2.0)
	var e := sqrt(e2)
	var c2 := (a * a + b * b * atanh_e(e) / e) / 2.0
	return sqrt(c2)


## atanh 的稳定实现（GDScript 无内置）：0.5·log1p(2x/(1−x))。
static func atanh_e(x: float) -> float:
	if not is_finite(x) or absf(x) >= 1.0:
		return NAN
	var y := absf(x)
	var t := 2.0 * y / (1.0 - y)
	var lp := t if t == 0.0 else t * log(1.0 + t) / ((1.0 + t) - 1.0)
	y = 0.5 * lp
	return y if x >= 0.0 else -y


static func _arc_input_ok(a: float, e2: float, lat_deg: float) -> bool:
	if not (is_finite(a) and is_finite(e2) and is_finite(lat_deg)):
		return false
	if a <= 0.0 or e2 < 0.0 or e2 >= 1.0:
		return false
	return absf(lat_deg) <= 90.0
