# core/ellipsoid/geodesic.gd —— A11 大地线正反解（Karney 算法）
#
# 移植声明：本文件为 GitHub geographiclib/geographiclib-js v2.2.0（MIT/X11 License，
# Copyright (c) Charles Karney）src/Geodesic.js、src/GeodesicLine.js、src/Math.js 的
# 逐行 GDScript 移植（ARCHITECTURE.md §4 GK-M2 指定移植底本）。算法出处：
#   Charles F. F. Karney, Algorithms for geodesics, J. Geodesy 87, 43-55 (2013),
#   https://doi.org/10.1007/s00190-012-0578-z
# 结构对应：Math.js → 本文件静态数学函数；Geodesic.js → GKGeodesic 类本体；
# GeodesicLine.js → _make_line_state/_gen_position（以状态字典承载 line 对象）。
# 验收容差：s12 相对 1e-9、方位角 1e-8°（GeodTest.dat 50 万行级数据口径）。
class_name GKGeodesic
extends RefCounted

# ---------- Math.js 常量（原样） ----------
const DIGITS := 53
const EPSILON := 2.220446049250313e-16        # pow(0.5, 52)
const DEG := PI / 180.0
const TINY := 1.4916681462400413e-154          # sqrt(2^-1074 / 2^-52) = 2^-511
const TOL0 := EPSILON
const TOL1 := 200.0 * TOL0
const TOL2 := 1.4901161193847656e-8            # sqrt(TOL0)
const TOLB := TOL0
const XTHRESH := 1.4901161193847656e-5         # 1000 * TOL2
const MAXIT1 := 20
const MAXIT2 := MAXIT1 + DIGITS + 10           # 83

# ---------- 级数阶数与能力位（Geodesic.js 原样） ----------
const GEODESIC_ORDER := 6
const N_A1 := GEODESIC_ORDER
const N_A2 := GEODESIC_ORDER
const N_A3 := GEODESIC_ORDER
const N_C1 := GEODESIC_ORDER
const N_C1P := GEODESIC_ORDER
const N_C2 := GEODESIC_ORDER
const N_C3 := GEODESIC_ORDER
const N_C4 := GEODESIC_ORDER

const CAP_NONE := 0
const CAP_C1 := 1 << 0
const CAP_C1P := 1 << 1
const CAP_C2 := 1 << 2
const CAP_C3 := 1 << 3
const CAP_C4 := 1 << 4
const OUT_ALL := 0x7F80
const NONE := 0
const ARC := 1 << 6
const LATITUDE := (1 << 7) | CAP_NONE
const LONGITUDE := (1 << 8) | CAP_C3
const AZIMUTH := (1 << 9) | CAP_NONE
const DISTANCE := (1 << 10) | CAP_C1
const STANDARD := LATITUDE | LONGITUDE | AZIMUTH | DISTANCE
const DISTANCE_IN := (1 << 11) | CAP_C1 | CAP_C1P
const REDUCEDLENGTH := (1 << 12) | CAP_C1 | CAP_C2
const GEODESICSCALE := (1 << 13) | CAP_C1 | CAP_C2
const AREA := (1 << 14) | CAP_C4
const LONG_UNROLL := 1 << 15
const OUT_MASK := OUT_ALL | LONG_UNROLL
# 本实现的输出全集：STANDARD + 约化长度 + 大地线尺度 + 面积
const OUT_FULL := STANDARD | REDUCEDLENGTH | GEODESICSCALE | AREA

# ---------- Math.js 静态函数（逐行移植） ----------

static func _sq(x: float) -> float:
	return x * x

static func _hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)

static func _cbrt(x: float) -> float:
	var y := pow(absf(x), 1.0 / 3.0)
	if x > 0.0:
		return y
	elif x < 0.0:
		return -y
	return x

static func _log1p(x: float) -> float:
	var y := 1.0 + x
	var z := y - 1.0
	if z == 0.0:
		return x
	return x * log(y) / z

static func _atanh(x: float) -> float:
	var y := absf(x)
	y = 0.5 * _log1p(2.0 * y / (1.0 - y))
	if x > 0.0:
		return y
	elif x < 0.0:
		return -y
	return x

static func _copysign(x: float, y: float) -> float:
	var neg := y < 0.0 or (y == 0.0 and 1.0 / y < 0.0)
	return -absf(x) if neg else absf(x)

## JS Math.round（向 +∞ 取半）：GDScript roundf 向远离零取半，半整数处不同
static func _js_round(x: float) -> int:
	return int(floor(x + 0.5))

## m.sum：误差-free 和 u+v = s+t
static func _sum(u: float, v: float) -> Dictionary:
	var s := u + v
	var up := s - v
	var vpp := s - up
	up -= u
	vpp -= v
	var t := s
	if s != 0.0:  # JS: s ? ... : s（含 -0 视为 0）
		t = 0.0 - (up + vpp)
	return {"s": s, "t": t}

## m.polyval：N 阶多项式（首项系数在前），p 为系数数组，s 为起始下标
static func _polyval(n: int, p: Array, s: int, x: float) -> float:
	var y := 0.0
	var i := s
	if n >= 0:
		y = float(p[i])
		i += 1
	var k := n
	while k > 0:
		k -= 1
		y = y * x + float(p[i])
		i += 1
	return y

## m.AngRound：把极接近 0 的值粗化到 1/16 量级
static func _ang_round(x: float) -> float:
	var z := 1.0 / 16.0
	var y := absf(x)
	if y < z:
		y = z - (z - y)
	return _copysign(y, x)

## m.remainder：x mod y，余数区间 [−y/2, y/2]
static func _remainder(x: float, y: float) -> float:
	x = fmod(x, y)
	if x < -y / 2.0:
		return x + y
	elif x < y / 2.0:
		return x
	return x - y

## m.AngNormalize：归一到 [−180, 180]
static func _ang_normalize(x: float) -> float:
	var y := _remainder(x, 360.0)
	if absf(y) == 180.0:
		return _copysign(180.0, x)
	return y

## m.LatFix：|x| > 90 → NaN
static func _lat_fix(x: float) -> float:
	return NAN if absf(x) > 90.0 else x

## m.AngDiff：误差-free 角差，d + e = y − x mod 360°
static func _ang_diff(x: float, y: float) -> Dictionary:
	var r := _sum(_remainder(-x, 360.0), _remainder(y, 360.0))
	r = _sum(_remainder(float(r["s"]), 360.0), float(r["t"]))
	var d := float(r["s"])
	var e := float(r["t"])
	if d == 0.0 or absf(d) == 180.0:
		var src := (y - x) if e == 0.0 else -e
		d = _copysign(d, src)
	return {"d": d, "e": e}

## m.sincosd：角度制 sin/cos（先精确归约到 [−45,45]）
static func _sincosd(x: float) -> Dictionary:
	var d := fmod(x, 360.0)
	var q := _js_round(d / 90.0)
	d -= 90.0 * float(q)
	var r := d * DEG
	var s := sin(r)
	var c := cos(r)
	if absf(d) == 45.0:
		c = sqrt(0.5)
		s = _copysign(c, r)
	elif absf(d) == 30.0:
		c = sqrt(0.75)
		s = _copysign(0.5, r)
	var sinx := 0.0
	var cosx := 0.0
	match q & 3:
		0:
			sinx = s
			cosx = c
		1:
			sinx = c
			cosx = -s
		2:
			sinx = -s
			cosx = -c
		_:
			sinx = -c
			cosx = s
	if sinx == 0.0:
		sinx = _copysign(sinx, x)
	return {"s": sinx, "c": cosx}

## m.sincosde：归约角 + 修正量的角度制 sin/cos
static func _sincosde(x: float, t: float) -> Dictionary:
	var d := fmod(x, 360.0)
	var q := _js_round(d / 90.0)
	d = _ang_round((d - 90.0 * float(q)) + t)
	var r := d * DEG
	var s := sin(r)
	var c := cos(r)
	if absf(d) == 45.0:
		c = sqrt(0.5)
		s = _copysign(c, r)
	elif absf(d) == 30.0:
		c = sqrt(0.75)
		s = _copysign(0.5, r)
	var sinx := 0.0
	var cosx := 0.0
	match q & 3:
		0:
			sinx = s
			cosx = c
		1:
			sinx = c
			cosx = -s
		2:
			sinx = -s
			cosx = -c
		_:
			sinx = -c
			cosx = s
	if sinx == 0.0:
		sinx = _copysign(sinx, x + t)
	return {"s": sinx, "c": cosx}

## m.atan2d：角度制 atan2，结果 [−180, 180]
static func _atan2d(y: float, x: float) -> float:
	var q := 0
	if absf(y) > absf(x):
		var tmp := y
		y = x
		x = tmp
		q = 2
	if _copysign(1.0, x) < 0.0:
		x = -x
		q += 1
	var ang := atan2(y, x) / DEG
	match q:
		1:
			ang = _copysign(180.0, y) - ang
		2:
			ang = 90.0 - ang
		3:
			ang = -90.0 + ang
		_:
			pass
	return ang

## SinCosSeries：Clenshaw 求和（Geodesic.js 原样）
## sinp=true: Σ c[i]·sin(2i·x)；false: Σ c[i]·cos((2i+1)·x)
static func _sin_cos_series(sinp: bool, sinx: float, cosx: float, c: PackedFloat64Array) -> float:
	var k := c.size()
	var n := k - (1 if sinp else 0)
	var ar := 2.0 * (cosx - sinx) * (cosx + sinx)
	var y0 := float(c[k - 1]) if (n % 2 == 1) else 0.0
	var y1 := 0.0
	if n % 2 == 1:
		k -= 1
	n = n / 2  # 整除（n 此时为偶数）
	while n > 0:
		n -= 1
		k -= 1
		y1 = ar * y0 - y1 + c[k]
		k -= 1
		y0 = ar * y1 - y0 + c[k]
	if sinp:
		return 2.0 * sinx * cosx * y0
	return cosx * (y0 - y1)

# ---------- 级数系数表（Geodesic.js 原样） ----------

const A1M1F_COEFF := [1, 4, 64, 0, 256]
const C1F_COEFF := [
	-1, 6, -16, 32,
	-9, 64, -128, 2048,
	9, -16, 768,
	3, -5, 512,
	-7, 1280,
	-7, 2048,
]
const C1PF_COEFF := [
	205, -432, 768, 1536,
	4005, -4736, 3840, 12288,
	-225, 116, 384,
	-7173, 2695, 7680,
	3467, 7680,
	38081, 61440,
]
const A2M1F_COEFF := [-11, -28, -192, 0, 256]
const C2F_COEFF := [
	1, 2, 16, 32,
	35, 64, 384, 2048,
	15, 80, 768,
	7, 35, 512,
	63, 1280,
	77, 2048,
]
const A3_COEFF := [
	-3, 128,
	-2, -3, 64,
	-1, -3, -1, 16,
	3, -1, -2, 8,
	1, -1, 2,
	1, 1,
]
const C3_COEFF := [
	3, 128,
	2, 5, 128,
	-1, 3, 3, 64,
	-1, 0, 1, 8,
	-1, 1, 4,
	5, 256,
	1, 3, 128,
	-3, -2, 3, 64,
	1, -3, 2, 32,
	7, 512,
	-10, 9, 384,
	5, -9, 5, 192,
	7, 512,
	-14, 7, 512,
	21, 2560,
]
const C4_COEFF := [
	97, 15015,
	1088, 156, 45045,
	-224, -4784, 1573, 45045,
	-10656, 14144, -4576, -858, 45045,
	64, 624, -4576, 6864, -3003, 15015,
	100, 208, 572, 3432, -12012, 30030, 45045,
	1, 9009,
	-2944, 468, 135135,
	5792, 1040, -1287, 135135,
	5952, -11648, 9152, -2574, 135135,
	-64, -624, 4576, -6864, 3003, 135135,
	8, 10725,
	1856, -936, 225225,
	-8448, 4992, -1144, 225225,
	-1440, 4160, -4576, 1716, 225225,
	-136, 63063,
	1024, -208, 105105,
	3584, -3328, 1144, 315315,
	-128, 135135,
	-2560, 832, 405405,
	128, 99099,
]

## astroid：解 k⁴+2k³−(x²+y²−1)k²−2y²k−y² = 0 的正根（Geodesic.js 原样）
static func _astroid(x: float, y: float) -> float:
	var p := _sq(x)
	var q := _sq(y)
	var r := (p + q - 1.0) / 6.0
	var k := 0.0
	if not (q == 0.0 and r <= 0.0):
		var s := p * q / 4.0
		var r2 := _sq(r)
		var r3 := r * r2
		var disc := s * (s + 2.0 * r3)
		var u := r
		if disc >= 0.0:
			var t3 := s + r3
			t3 += -sqrt(disc) if t3 < 0.0 else sqrt(disc)
			var t := _cbrt(t3)
			u += t + (r2 / t if t != 0.0 else 0.0)
		else:
			var ang := atan2(sqrt(-disc), -(s + r3))
			u += 2.0 * r * cos(ang / 3.0)
		var v := sqrt(_sq(u) + q)
		var uv := (q / (v - u)) if u < 0.0 else (u + v)
		var w := (uv - q) / (2.0 * v)
		k = uv / (sqrt(uv + _sq(w)) + w)
	return k

static func _a1m1f(eps: float) -> float:
	var p := N_A1 / 2  # floor((6)/2)=3（N_A1 偶数）
	var t := _polyval(p, A1M1F_COEFF, 0, _sq(eps)) / float(A1M1F_COEFF[p + 1])
	return (t + eps) / (1.0 - eps)

static func _c1f(eps: float) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(N_C1 + 1)
	var eps2 := _sq(eps)
	var d := eps
	var o := 0
	for l in range(1, N_C1 + 1):
		var p := floori(float(N_C1 - l) / 2.0)
		c[l] = d * _polyval(p, C1F_COEFF, o, eps2) / float(C1F_COEFF[o + p + 1])
		o += p + 2
		d *= eps
	return c

static func _c1pf(eps: float) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(N_C1P + 1)
	var eps2 := _sq(eps)
	var d := eps
	var o := 0
	for l in range(1, N_C1P + 1):
		var p := floori(float(N_C1P - l) / 2.0)
		c[l] = d * _polyval(p, C1PF_COEFF, o, eps2) / float(C1PF_COEFF[o + p + 1])
		o += p + 2
		d *= eps
	return c

static func _a2m1f(eps: float) -> float:
	var p := N_A2 / 2
	var t := _polyval(p, A2M1F_COEFF, 0, _sq(eps)) / float(A2M1F_COEFF[p + 1])
	return (t - eps) / (1.0 + eps)

static func _c2f(eps: float) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(N_C2 + 1)
	var eps2 := _sq(eps)
	var d := eps
	var o := 0
	for l in range(1, N_C2 + 1):
		var p := floori(float(N_C2 - l) / 2.0)
		c[l] = d * _polyval(p, C2F_COEFF, o, eps2) / float(C2F_COEFF[o + p + 1])
		o += p + 2
		d *= eps
	return c

# ---------- GKGeodesic 实例（对应 Geodesic.js 构造器） ----------

var a := 0.0
var f := 0.0
var f1 := 1.0
var e2 := 0.0
var ep2 := 0.0
var n := 0.0
var b := 0.0
var c2 := 0.0   # 等面积半径的平方
var etol2 := 0.0
var _A3x := PackedFloat64Array()
var _C3x := PackedFloat64Array()
var _C4x := PackedFloat64Array()

## 构造：a 赤道半径（m），f 扁率。非法参数返回空实例（a=0），调用方以 is_valid() 判别。
func _init(p_a: float = 6378137.0, p_f: float = 1.0 / 298.257223563) -> void:
	a = p_a
	f = p_f
	f1 = 1.0 - f
	e2 = f * (2.0 - f)
	ep2 = e2 / _sq(f1)
	n = f / (2.0 - f)
	b = a * f1
	c2 = (_sq(a) + _sq(b) * (1.0 if e2 == 0.0 else _atanh(sqrt(e2)) / sqrt(absf(e2)))) / 2.0
	etol2 = 0.1 * TOL2 / sqrt(maxf(0.001, absf(f)) * minf(1.0, 1.0 - f / 2.0) / 2.0)
	if not (is_finite(a) and a > 0.0) or not (is_finite(b) and b > 0.0):
		a = 0.0  # 失败标记
		return
	_a3coeff()
	_c3coeff()
	_c4coeff()

func is_valid() -> bool:
	return a > 0.0

func _a3coeff() -> void:
	var o := 0
	var k := 0
	_A3x.resize(N_A3)
	var j := N_A3 - 1
	while j >= 0:
		var p := mini(N_A3 - j - 1, j)
		_A3x[k] = _polyval(p, A3_COEFF, o, n) / float(A3_COEFF[o + p + 1])
		k += 1
		o += p + 2
		j -= 1

func _c3coeff() -> void:
	var o := 0
	var k := 0
	_C3x.resize(N_C3 * (N_C3 - 1) / 2)
	for l in range(1, N_C3):
		var j := N_C3 - 1
		while j >= l:
			var p := mini(N_C3 - j - 1, j)
			_C3x[k] = _polyval(p, C3_COEFF, o, n) / float(C3_COEFF[o + p + 1])
			k += 1
			o += p + 2
			j -= 1

func _c4coeff() -> void:
	var o := 0
	var k := 0
	_C4x.resize(N_C4 * (N_C4 + 1) / 2)
	for l in range(0, N_C4):
		var j := N_C4 - 1
		while j >= l:
			var p := N_C4 - j - 1
			_C4x[k] = _polyval(p, C4_COEFF, o, n) / float(C4_COEFF[o + p + 1])
			k += 1
			o += p + 2
			j -= 1

func _a3f(eps: float) -> float:
	return _polyvalp(N_A3 - 1, _A3x, 0, eps)

func _c3f(eps: float) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(N_C3)
	var mult := 1.0
	var o := 0
	for l in range(1, N_C3):
		var p := N_C3 - l - 1
		mult *= eps
		c[l] = mult * _polyvalp(p, _C3x, o, eps)
		o += p + 1
	return c

func _c4f(eps: float) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(N_C4)
	var mult := 1.0
	var o := 0
	for l in range(0, N_C4):
		var p := N_C4 - l - 1
		c[l] = mult * _polyvalp(p, _C4x, o, eps)
		o += p + 1
		mult *= eps
	return c

## _polyval 的 PackedFloat64Array 版本（系数存实例内）
static func _polyvalp(n: int, p: PackedFloat64Array, s: int, x: float) -> float:
	var y := 0.0
	var i := s
	if n >= 0:
		y = p[i]
		i += 1
	var k := n
	while k > 0:
		k -= 1
		y = y * x + p[i]
		i += 1
	return y

# ---------- Lengths（Geodesic.js 原样；用实例暂存 C1a/C2a） ----------
var _C1a := PackedFloat64Array()
var _C2a := PackedFloat64Array()

## 返回 {s12b?, m12b, m0?, M12?, M21?}（缺少的量不在字典中）
func _lengths(eps: float, sig12: float, ssig1: float, csig1: float, dn1: float,
		ssig2: float, csig2: float, dn2: float, cbet1: float, cbet2: float,
		outmask: int) -> Dictionary:
	outmask &= OUT_MASK
	var vals := {}
	var m0x := 0.0
	var J12 := 0.0
	var A1 := 0.0
	var A2 := 0.0
	if outmask & (DISTANCE | REDUCEDLENGTH | GEODESICSCALE):
		A1 = _a1m1f(eps)
		_C1a = _c1f(eps)
		if outmask & (REDUCEDLENGTH | GEODESICSCALE):
			A2 = _a2m1f(eps)
			_C2a = _c2f(eps)
			m0x = A1 - A2
			A2 = 1.0 + A2
		A1 = 1.0 + A1
	if outmask & DISTANCE:
		var B1 := _sin_cos_series(true, ssig2, csig2, _C1a) - _sin_cos_series(true, ssig1, csig1, _C1a)
		vals["s12b"] = A1 * (sig12 + B1)
		if outmask & (REDUCEDLENGTH | GEODESICSCALE):
			var B2 := _sin_cos_series(true, ssig2, csig2, _C2a) - _sin_cos_series(true, ssig1, csig1, _C2a)
			J12 = m0x * sig12 + (A1 * B1 - A2 * B2)
	elif outmask & (REDUCEDLENGTH | GEODESICSCALE):
		for l in range(1, N_C2 + 1):
			_C2a[l] = A1 * _C1a[l] - A2 * _C2a[l]
		J12 = m0x * sig12 + (_sin_cos_series(true, ssig2, csig2, _C2a) - _sin_cos_series(true, ssig1, csig1, _C2a))
	if outmask & REDUCEDLENGTH:
		vals["m0"] = m0x
		vals["m12b"] = dn2 * (csig1 * ssig2) - dn1 * (ssig1 * csig2) - csig1 * csig2 * J12
	else:
		vals["m12b"] = NAN
	if outmask & GEODESICSCALE:
		var csig12 := csig1 * csig2 + ssig1 * ssig2
		var t := ep2 * (cbet1 - cbet2) * (cbet1 + cbet2) / (dn1 + dn2)
		vals["M12"] = csig12 + (t * ssig2 - csig2 * J12) * ssig1 / dn1
		vals["M21"] = csig12 - (t * ssig1 - csig1 * J12) * ssig2 / dn2
	return vals

# ---------- InverseStart（Geodesic.js 原样） ----------

## 返回 {sig12, salp1, calp1, salp2, calp2, dnm}
func _inverse_start(sbet1: float, cbet1: float, dn1: float, sbet2: float, cbet2: float,
		dn2: float, lam12: float, slam12: float, clam12: float) -> Dictionary:
	var vals := {"sig12": -1.0, "salp1": 0.0, "calp1": 0.0, "salp2": 0.0, "calp2": 0.0, "dnm": NAN}
	var sbet12 := sbet2 * cbet1 - cbet2 * sbet1
	var cbet12 := cbet2 * cbet1 + sbet2 * sbet1
	var sbet12a := sbet2 * cbet1
	sbet12a += cbet2 * sbet1

	var shortline := cbet12 >= 0.0 and sbet12 < 0.5 and cbet2 * lam12 < 0.5
	var omg12 := 0.0
	var somg12 := 0.0
	var comg12 := 0.0
	if shortline:
		var sbetm2 := _sq(sbet1 + sbet2)
		sbetm2 /= sbetm2 + _sq(cbet1 + cbet2)
		vals["dnm"] = sqrt(1.0 + ep2 * sbetm2)
		omg12 = lam12 / (f1 * float(vals["dnm"]))
		somg12 = sin(omg12)
		comg12 = cos(omg12)
	else:
		somg12 = slam12
		comg12 = clam12

	vals["salp1"] = cbet2 * somg12
	if comg12 >= 0.0:
		vals["calp1"] = sbet12 + cbet2 * sbet1 * _sq(somg12) / (1.0 + comg12)
	else:
		vals["calp1"] = sbet12a - cbet2 * sbet1 * _sq(somg12) / (1.0 - comg12)

	var ssig12 := _hypot(float(vals["salp1"]), float(vals["calp1"]))
	var csig12 := sbet1 * sbet2 + cbet1 * cbet2 * comg12
	if shortline and ssig12 < etol2:
		# 极短边
		vals["salp2"] = cbet1 * somg12
		if comg12 >= 0.0:
			vals["calp2"] = sbet12 - cbet1 * sbet2 * _sq(somg12) / (1.0 + comg12)
		else:
			vals["calp2"] = sbet12 - cbet1 * sbet2 * (1.0 - comg12)
		var t := _hypot(float(vals["salp2"]), float(vals["calp2"]))
		vals["salp2"] = float(vals["salp2"]) / t
		vals["calp2"] = float(vals["calp2"]) / t
		vals["sig12"] = atan2(ssig12, csig12)
	elif absf(n) > 0.1 or csig12 >= 0.0 or ssig12 >= 6.0 * absf(n) * PI * _sq(cbet1):
		# 零阶球面近似即可，无需 astroid
		pass
	else:
		# 近对跖：astroid 估计
		var lam12x := atan2(-slam12, -clam12)
		var x := 0.0
		var y := 0.0
		var lamscale := 0.0
		var betscale := 0.0
		if f >= 0.0:
			var k2 := _sq(sbet1) * ep2
			var eps := k2 / (2.0 * (1.0 + sqrt(1.0 + k2)) + k2)
			lamscale = f * cbet1 * _a3f(eps) * PI
			betscale = lamscale * cbet1
			x = lam12x / lamscale
			y = sbet12a / betscale
		else:
			var cbet12a := cbet2 * cbet1 - sbet2 * sbet1
			var bet12a := atan2(sbet12a, cbet12a)
			var nvals := _lengths(n, PI + bet12a, sbet1, -cbet1, dn1, sbet2, cbet2, dn2, cbet1, cbet2, REDUCEDLENGTH)
			var m12b: float = nvals["m12b"]
			var m0: float = nvals["m0"]
			x = -1.0 + m12b / (cbet1 * cbet2 * m0 * PI)
			betscale = (sbet12a / x) if x < -0.01 else (-f * _sq(cbet1) * PI)
			lamscale = betscale / cbet1
			y = lam12 / lamscale

		if y > -TOL1 and x > -1.0 - XTHRESH:
			# 剥离近割线情形
			if f >= 0.0:
				vals["salp1"] = minf(1.0, -x)
				vals["calp1"] = -sqrt(1.0 - _sq(float(vals["salp1"])))
			else:
				vals["calp1"] = maxf((0.0 if x > -TOL1 else -1.0), x)
				vals["salp1"] = sqrt(1.0 - _sq(float(vals["calp1"])))
		else:
			var k := _astroid(x, y)
			var omg12a := lamscale * ((-x * k / (1.0 + k)) if f >= 0.0 else (-y * (1.0 + k) / k))
			somg12 = sin(omg12a)
			comg12 = -cos(omg12a)
			vals["salp1"] = cbet2 * somg12
			vals["calp1"] = sbet12a - cbet2 * sbet1 * _sq(somg12) / (1.0 - comg12)
	# 起始估计合法性（JS 语义：NaN <= 0 为假 → 走归一化分支）
	if not (float(vals["salp1"]) <= 0.0):
		var t2 := _hypot(float(vals["salp1"]), float(vals["calp1"]))
		vals["salp1"] = float(vals["salp1"]) / t2
		vals["calp1"] = float(vals["calp1"]) / t2
	else:
		vals["salp1"] = 1.0
		vals["calp1"] = 0.0
	return vals

# ---------- Lambda12（Geodesic.js 原样） ----------

## 返回 {lam12, salp2, calp2, sig12, ssig1, csig1, ssig2, csig2, eps, domg12, dlam12?}
func _lambda12(sbet1: float, cbet1: float, dn1: float, sbet2: float, cbet2: float,
		dn2: float, salp1: float, calp1: float, slam120: float, clam120: float,
		diffp: bool) -> Dictionary:
	var vals := {}
	var t := 0.0
	if sbet1 == 0.0 and calp1 == 0.0:
		calp1 = -TINY
	var salp0 := salp1 * cbet1
	var calp0 := _hypot(calp1, salp1 * sbet1)
	var ssig1 := sbet1
	var somg1 := salp0 * sbet1
	var csig1 := calp1 * cbet1
	var comg1 := csig1
	t = _hypot(ssig1, csig1)
	ssig1 /= t
	csig1 /= t
	var salp2 := (salp0 / cbet2) if cbet2 != cbet1 else salp1
	var calp2 := 0.0
	if cbet2 != cbet1 or absf(sbet2) != -sbet1:
		# 注意：此处必须用未归一化的 calp1·cbet1（JS: m.sq(calp1 * cbet1)），
		# 不能用上面已归一化的 csig1 —— 归一化因子 t≠1 会引入 ~0.3° 级方位误差
		var inner := (cbet2 - cbet1) * (cbet1 + cbet2) if cbet1 < -sbet1 else (sbet1 - sbet2) * (sbet1 + sbet2)
		calp2 = sqrt(_sq(calp1 * cbet1) + inner) / cbet2
	else:
		calp2 = absf(calp1)
	var ssig2 := sbet2
	var somg2 := salp0 * sbet2
	var csig2 := calp2 * cbet2
	var comg2 := csig2
	t = _hypot(ssig2, csig2)
	ssig2 /= t
	csig2 /= t
	vals["sig12"] = atan2(maxf(0.0, csig1 * ssig2 - ssig1 * csig2), csig1 * csig2 + ssig1 * ssig2)
	var somg12 := maxf(0.0, comg1 * somg2 - somg1 * comg2)
	var comg12 := comg1 * comg2 + somg1 * somg2
	var eta := atan2(somg12 * clam120 - comg12 * slam120, comg12 * clam120 + somg12 * slam120)
	var k2 := _sq(calp0) * ep2
	vals["eps"] = k2 / (2.0 * (1.0 + sqrt(1.0 + k2)) + k2)
	var C3a := _c3f(float(vals["eps"]))
	var B312 := _sin_cos_series(true, ssig2, csig2, C3a) - _sin_cos_series(true, ssig1, csig1, C3a)
	vals["domg12"] = -f * _a3f(float(vals["eps"])) * salp0 * (float(vals["sig12"]) + B312)
	vals["lam12"] = eta + float(vals["domg12"])
	if diffp:
		if calp2 == 0.0:
			vals["dlam12"] = -2.0 * f1 * dn1 / sbet1
		else:
			var nvals := _lengths(float(vals["eps"]), float(vals["sig12"]), ssig1, csig1, dn1, ssig2, csig2, dn2, cbet1, cbet2, REDUCEDLENGTH)
			vals["dlam12"] = float(nvals["m12b"])
			vals["dlam12"] = float(vals["dlam12"]) * f1 / (calp2 * cbet2)
	vals["salp2"] = salp2
	vals["calp2"] = calp2
	vals["ssig1"] = ssig1
	vals["csig1"] = csig1
	vals["ssig2"] = ssig2
	vals["csig2"] = csig2
	return vals

# ---------- InverseInt（Geodesic.js InverseInt 原样） ----------

## 返回 {vals, salp1, calp1, salp2, calp2, converged, numit}
func _inverse_int(lat1: float, lon1: float, lat2: float, lon2: float, outmask: int) -> Dictionary:
	var vals := {}
	var converged := true
	var numit_used := 0
	# 经差（AngDiff 误差-free），结果在 [−180,180]
	lat1 = _lat_fix(lat1)
	lat2 = _lat_fix(lat2)
	vals["lat1"] = lat1
	vals["lat2"] = lat2
	lat1 = _ang_round(lat1)
	lat2 = _ang_round(lat2)
	var ad := _ang_diff(lon1, lon2)
	var lon12: float = ad["d"]
	var lon12s: float = ad["e"]
	vals["lon1"] = _ang_normalize(lon1)
	vals["lon2"] = _ang_normalize(lon2)
	var lonsign := _copysign(1.0, lon12)
	lon12 *= lonsign
	lon12s *= lonsign
	var lam12 := lon12 * DEG
	var tsc := _sincosde(lon12, lon12s)
	var slam12: float = tsc["s"]
	var clam12: float = tsc["c"]
	lon12s = (180.0 - lon12) - lon12s  # 补经差

	# 交换点位使 |B1| ≥ |B2|
	var swapp := -1 if (absf(lat1) < absf(lat2) or is_nan(lat2)) else 1
	if swapp < 0:
		lonsign *= -1.0
		var tmp := lat1
		lat1 = lat2
		lat2 = tmp
	# 使 B1 ≤ 0
	var latsign := _copysign(1.0, -lat1)
	lat1 *= latsign
	lat2 *= latsign

	tsc = _sincosd(lat1)
	var sbet1 := f1 * float(tsc["s"])
	var cbet1 := float(tsc["c"])
	var t := _hypot(sbet1, cbet1)
	sbet1 /= t
	cbet1 /= t
	cbet1 = maxf(TINY, cbet1)
	tsc = _sincosd(lat2)
	var sbet2 := f1 * float(tsc["s"])
	var cbet2 := float(tsc["c"])
	t = _hypot(sbet2, cbet2)
	sbet2 /= t
	cbet2 /= t
	cbet2 = maxf(TINY, cbet2)

	if cbet1 < -sbet1:
		if cbet2 == cbet1:
			sbet2 = _copysign(sbet1, sbet2)
	else:
		if absf(sbet2) == -sbet1:
			cbet2 = cbet1

	var dn1 := sqrt(1.0 + ep2 * _sq(sbet1))
	var dn2 := sqrt(1.0 + ep2 * _sq(sbet2))

	var sig12 := 0.0
	var calp1 := 0.0
	var salp1 := 0.0
	var calp2 := 0.0
	var salp2 := 0.0
	var ssig1 := 0.0
	var csig1 := 0.0
	var ssig2 := 0.0
	var csig2 := 0.0
	var eps := 0.0
	var omg12 := 0.0
	var somg12 := 2.0
	var comg12 := 0.0
	var domg12 := 0.0
	var s12x := 0.0
	var m12x := 0.0

	var meridian := lat1 == -90.0 or slam12 == 0.0
	if meridian:
		# 两端在同一条整子午线上
		calp1 = clam12
		salp1 = slam12
		calp2 = 1.0
		salp2 = 0.0
		ssig1 = sbet1
		csig1 = calp1 * cbet1
		ssig2 = sbet2
		csig2 = calp2 * cbet2
		sig12 = atan2(maxf(0.0, csig1 * ssig2 - ssig1 * csig2), csig1 * csig2 + ssig1 * ssig2)
		var nvals := _lengths(n, sig12, ssig1, csig1, dn1, ssig2, csig2, dn2, cbet1, cbet2,
				outmask | DISTANCE | REDUCEDLENGTH)
		s12x = float(nvals.get("s12b", 0.0))
		m12x = float(nvals["m12b"])
		if outmask & GEODESICSCALE:
			vals["M12"] = nvals.get("M12", NAN)
			vals["M21"] = nvals.get("M21", NAN)
		if sig12 < TOL2 or m12x >= 0.0:
			if sig12 < 3.0 * TINY or (sig12 < TOL0 and (s12x < 0.0 or m12x < 0.0)):
				sig12 = 0.0
				m12x = 0.0
				s12x = 0.0
			m12x *= b
			s12x *= b
			vals["a12"] = sig12 / DEG
		else:
			meridian = false

	if not meridian and sbet1 == 0.0 and (f <= 0.0 or lon12s >= f * 180.0):
		# 沿赤道的大地线
		calp1 = 0.0
		calp2 = 0.0
		salp1 = 1.0
		salp2 = 1.0
		s12x = a * lam12
		sig12 = lam12 / f1
		omg12 = lam12 / f1
		m12x = b * sin(sig12)
		if outmask & GEODESICSCALE:
			vals["M12"] = cos(sig12)
			vals["M21"] = cos(sig12)
		vals["a12"] = lon12 / f1
	elif not meridian:
		# 一般情形：InverseStart 起步 + Newton 迭代
		var nvals := _inverse_start(sbet1, cbet1, dn1, sbet2, cbet2, dn2, lam12, slam12, clam12)
		sig12 = float(nvals["sig12"])
		salp1 = float(nvals["salp1"])
		calp1 = float(nvals["calp1"])
		if sig12 >= 0.0:
			salp2 = float(nvals["salp2"])
			calp2 = float(nvals["calp2"])
			var dnm: float = nvals.get("dnm", 1.0)
			s12x = sig12 * b * dnm
			m12x = _sq(dnm) * b * sin(sig12 / dnm)
			if outmask & GEODESICSCALE:
				vals["M12"] = cos(sig12 / dnm)
				vals["M21"] = cos(sig12 / dnm)
			vals["a12"] = sig12 / DEG
			omg12 = lam12 / (f1 * dnm)
		else:
			# Newton 迭代：解 λ12(α1) − λ120 = 0，区间套保底
			var numit := 0
			var tripn := false
			var tripb := false
			var salp1a := TINY
			var calp1a := 1.0
			var salp1b := TINY
			var calp1b := -1.0
			var v := 0.0
			while true:
				nvals = _lambda12(sbet1, cbet1, dn1, sbet2, cbet2, dn2, salp1, calp1,
						slam12, clam12, numit < MAXIT1)
				v = float(nvals["lam12"])
				salp2 = float(nvals["salp2"])
				calp2 = float(nvals["calp2"])
				sig12 = float(nvals["sig12"])
				ssig1 = float(nvals["ssig1"])
				csig1 = float(nvals["csig1"])
				ssig2 = float(nvals["ssig2"])
				csig2 = float(nvals["csig2"])
				eps = float(nvals["eps"])
				domg12 = float(nvals["domg12"])
				var dv := float(nvals.get("dlam12", NAN))
				if tripb or not (absf(v) >= (8.0 if tripn else 1.0) * TOL0) or numit == MAXIT2:
					break
				if v > 0.0 and (numit < MAXIT1 or calp1 / salp1 > calp1b / salp1b):
					salp1b = salp1
					calp1b = calp1
				elif v < 0.0 and (numit < MAXIT1 or calp1 / salp1 < calp1a / salp1a):
					salp1a = salp1
					calp1a = calp1
				if numit < MAXIT1 and dv > 0.0:
					var dalp1 := -v / dv
					if absf(dalp1) < PI:
						var sdalp1 := sin(dalp1)
						var cdalp1 := cos(dalp1)
						var nsalp1 := salp1 * cdalp1 + calp1 * sdalp1
						if nsalp1 > 0.0:
							calp1 = calp1 * cdalp1 - salp1 * sdalp1
							salp1 = nsalp1
							t = _hypot(salp1, calp1)
							salp1 /= t
							calp1 /= t
							tripn = absf(v) <= 16.0 * TOL0
							numit += 1
							continue
				salp1 = (salp1a + salp1b) / 2.0
				calp1 = (calp1a + calp1b) / 2.0
				t = _hypot(salp1, calp1)
				salp1 /= t
				calp1 /= t
				tripn = false
				tripb = absf(salp1a - salp1) + (calp1a - calp1) < TOLB or absf(salp1 - salp1b) + (calp1 - calp1b) < TOLB
				numit += 1
			numit_used = numit
			converged = tripb or absf(v) <= 1e-12
			var lengthmask := outmask
			if outmask & (REDUCEDLENGTH | GEODESICSCALE):
				lengthmask = outmask | DISTANCE
			nvals = _lengths(eps, sig12, ssig1, csig1, dn1, ssig2, csig2, dn2, cbet1, cbet2, lengthmask)
			s12x = float(nvals.get("s12b", 0.0))
			m12x = float(nvals["m12b"])
			if outmask & GEODESICSCALE:
				vals["M12"] = nvals.get("M12", NAN)
				vals["M21"] = nvals.get("M21", NAN)
			m12x *= b
			s12x *= b
			vals["a12"] = sig12 / DEG
			if outmask & AREA:
				# omg12 = lam12 − domg12
				var sdomg12 := sin(domg12)
				var cdomg12 := cos(domg12)
				somg12 = slam12 * cdomg12 - clam12 * sdomg12
				comg12 = clam12 * cdomg12 + slam12 * sdomg12

	if outmask & DISTANCE:
		vals["s12"] = 0.0 + s12x
	if outmask & REDUCEDLENGTH:
		vals["m12"] = 0.0 + m12x

	if outmask & AREA:
		var salp0 := salp1 * cbet1
		var calp0 := _hypot(calp1, salp1 * sbet1)
		if calp0 != 0.0 and salp0 != 0.0:
			ssig1 = sbet1
			csig1 = calp1 * cbet1
			ssig2 = sbet2
			csig2 = calp2 * cbet2
			var k2 := _sq(calp0) * ep2
			eps = k2 / (2.0 * (1.0 + sqrt(1.0 + k2)) + k2)
			var A4 := _sq(a) * calp0 * salp0 * e2
			t = _hypot(ssig1, csig1)
			ssig1 /= t
			csig1 /= t
			t = _hypot(ssig2, csig2)
			ssig2 /= t
			csig2 /= t
			var C4a := _c4f(eps)
			var B41 := _sin_cos_series(false, ssig1, csig1, C4a)
			var B42 := _sin_cos_series(false, ssig2, csig2, C4a)
			vals["S12"] = A4 * (B42 - B41)
		else:
			vals["S12"] = 0.0
		if not meridian and somg12 == 2.0:
			somg12 = sin(omg12)
			comg12 = cos(omg12)
		var alp12 := 0.0
		if not meridian and comg12 > -0.7071 and sbet2 - sbet1 < 1.75:
			# tan(Γ/2) 展开（此处复用 domg12 变量名，与底本一致）
			domg12 = 1.0 + comg12
			var dbet1 := 1.0 + cbet1
			var dbet2 := 1.0 + cbet2
			alp12 = 2.0 * atan2(somg12 * (sbet1 * dbet2 + sbet2 * dbet1), domg12 * (sbet1 * sbet2 + dbet1 * dbet2))
		else:
			var salp12 := salp2 * calp1 - calp2 * salp1
			var calp12 := calp2 * calp1 + salp2 * salp1
			if salp12 == 0.0 and calp12 < 0.0:
				salp12 = TINY * calp1
				calp12 = -1.0
			alp12 = atan2(salp12, calp12)
		vals["S12"] = float(vals["S12"]) + c2 * alp12
		vals["S12"] = float(vals["S12"]) * swapp * lonsign * latsign

	# 换回原点位顺序并化算方位角
	if swapp < 0:
		var ts := salp2
		salp2 = salp1
		salp1 = ts
		var tc := calp2
		calp2 = calp1
		calp1 = tc
		if outmask & GEODESICSCALE:
			var tm: float = vals.get("M21", 0.0)
			vals["M21"] = vals.get("M12", 0.0)
			vals["M12"] = tm
	salp1 *= swapp * lonsign
	calp1 *= swapp * latsign
	salp2 *= swapp * lonsign
	calp2 *= swapp * latsign
	return {"vals": vals, "salp1": salp1, "calp1": calp1, "salp2": salp2, "calp2": calp2,
			"converged": converged, "numit": numit_used}

# ---------- GeodesicLine.js 移植（状态字典承载 line 对象） ----------

## 由 (lat1, lon1, azi1) 建 line 状态；salp1/calp1 同时给出时直接采用（InverseLine 口径）。
func _make_line_state(p_lat1: float, p_lon1: float, p_azi1: float,
		p_salp1 := NAN, p_calp1 := NAN) -> Dictionary:
	var st := {}
	var salp1 := p_salp1
	var calp1 := p_calp1
	var azi1 := p_azi1
	if is_nan(salp1) or is_nan(calp1):
		azi1 = _ang_normalize(azi1)
		var tz := _sincosd(_ang_round(azi1))
		salp1 = float(tz["s"])
		calp1 = float(tz["c"])
	var lat1 := _lat_fix(p_lat1)
	st["lat1"] = lat1
	st["lon1"] = p_lon1
	st["azi1"] = azi1
	st["salp1"] = salp1
	st["calp1"] = calp1
	st["a"] = a
	st["f"] = f
	st["f1"] = f1
	st["b"] = b
	st["c2"] = c2
	st["ep2"] = ep2
	var tz2 := _sincosd(_ang_round(lat1))
	var sbet1 := f1 * float(tz2["s"])
	var cbet1 := float(tz2["c"])
	var t := _hypot(sbet1, cbet1)
	sbet1 /= t
	cbet1 /= t
	cbet1 = maxf(TINY, cbet1)
	st["dn1"] = sqrt(1.0 + ep2 * _sq(sbet1))
	st["salp0"] = salp1 * cbet1
	st["calp0"] = _hypot(calp1, salp1 * sbet1)
	st["ssig1"] = sbet1
	st["somg1"] = float(st["salp0"]) * sbet1
	if sbet1 != 0.0 or calp1 != 0.0:
		st["csig1"] = cbet1 * calp1
	else:
		st["csig1"] = 1.0
	st["comg1"] = st["csig1"]
	t = _hypot(float(st["ssig1"]), float(st["csig1"]))
	st["ssig1"] = float(st["ssig1"]) / t
	st["csig1"] = float(st["csig1"]) / t
	st["k2"] = _sq(float(st["calp0"])) * ep2
	var eps := float(st["k2"]) / (2.0 * (1.0 + sqrt(1.0 + float(st["k2"]))) + float(st["k2"]))
	st["A1m1"] = _a1m1f(eps)
	st["C1a"] = _c1f(eps)
	st["B11"] = _sin_cos_series(true, float(st["ssig1"]), float(st["csig1"]), st["C1a"])
	var s := sin(float(st["B11"]))
	var c := cos(float(st["B11"]))
	st["stau1"] = float(st["ssig1"]) * c + float(st["csig1"]) * s
	st["ctau1"] = float(st["csig1"]) * c - float(st["ssig1"]) * s
	st["C1pa"] = _c1pf(eps)
	st["A2m1"] = _a2m1f(eps)
	st["C2a"] = _c2f(eps)
	st["B21"] = _sin_cos_series(true, float(st["ssig1"]), float(st["csig1"]), st["C2a"])
	st["C3a"] = _c3f(eps)
	st["A3c"] = -f * float(st["salp0"]) * _a3f(eps)
	st["B31"] = _sin_cos_series(true, float(st["ssig1"]), float(st["csig1"]), st["C3a"])
	st["C4a"] = _c4f(eps)
	st["A4"] = _sq(a) * float(st["calp0"]) * float(st["salp0"]) * e2
	st["B41"] = _sin_cos_series(false, float(st["ssig1"]), float(st["csig1"]), st["C4a"])
	return st

## GenPosition（GeodesicLine.js 原样；不启用 LONG_UNROLL）。
static func _gen_position(st: Dictionary, arcmode: bool, s12_a12: float, outmask: int) -> Dictionary:
	outmask &= OUT_MASK
	var vals := {"lat1": st["lat1"], "azi1": st["azi1"], "lon1": _ang_normalize(float(st["lon1"]))}
	if arcmode:
		vals["a12"] = s12_a12
	else:
		vals["s12"] = s12_a12
	var sig12 := 0.0
	var ssig12 := 0.0
	var csig12 := 0.0
	var B12 := 0.0
	if arcmode:
		sig12 = s12_a12 * DEG
		var tz := _sincosd(s12_a12)
		ssig12 = float(tz["s"])
		csig12 = float(tz["c"])
	else:
		var tau12 := s12_a12 / (float(st["b"]) * (1.0 + float(st["A1m1"])))
		var s := sin(tau12)
		var c := cos(tau12)
		B12 = -_sin_cos_series(true, float(st["stau1"]) * c + float(st["ctau1"]) * s,
				float(st["ctau1"]) * c - float(st["stau1"]) * s, st["C1pa"])
		sig12 = tau12 - (B12 - float(st["B11"]))
		ssig12 = sin(sig12)
		csig12 = cos(sig12)
		if absf(float(st["f"])) > 0.01:
			# |f|>1/100 时级数反演失准，补 1 轮 Newton（WGS84 实际不触发，保留与底本一致）
			var ssig2b := float(st["ssig1"]) * csig12 + float(st["csig1"]) * ssig12
			var csig2b := float(st["csig1"]) * csig12 - float(st["ssig1"]) * ssig12
			B12 = _sin_cos_series(true, ssig2b, csig2b, st["C1a"])
			var serr := (1.0 + float(st["A1m1"])) * (sig12 + (B12 - float(st["B11"]))) - s12_a12 / float(st["b"])
			sig12 -= serr / sqrt(1.0 + float(st["k2"]) * _sq(ssig2b))
			ssig12 = sin(sig12)
			csig12 = cos(sig12)
	# sig2 = sig1 + sig12
	var ssig2 := float(st["ssig1"]) * csig12 + float(st["csig1"]) * ssig12
	var csig2 := float(st["csig1"]) * csig12 - float(st["ssig1"]) * ssig12
	var dn2 := sqrt(1.0 + float(st["k2"]) * _sq(ssig2))
	var AB1 := 0.0
	if outmask & (DISTANCE | REDUCEDLENGTH | GEODESICSCALE):
		if arcmode or absf(float(st["f"])) > 0.01:
			B12 = _sin_cos_series(true, ssig2, csig2, st["C1a"])
		AB1 = (1.0 + float(st["A1m1"])) * (B12 - float(st["B11"]))
	var sbet2 := float(st["calp0"]) * ssig2
	var cbet2 := _hypot(float(st["salp0"]), float(st["calp0"]) * csig2)
	if cbet2 == 0.0:
		cbet2 = TINY
		csig2 = TINY
	var salp2 := float(st["salp0"])
	var calp2 := float(st["calp0"]) * csig2
	if arcmode and outmask & DISTANCE:
		vals["s12"] = float(st["b"]) * ((1.0 + float(st["A1m1"])) * sig12 + AB1)
	# 经度
	var somg2 := float(st["salp0"]) * ssig2
	var comg2 := csig2
	var omg12 := atan2(somg2 * float(st["comg1"]) - comg2 * float(st["somg1"]),
			comg2 * float(st["comg1"]) + somg2 * float(st["somg1"]))
	var lam12 := omg12 + float(st["A3c"]) * (sig12 + (_sin_cos_series(true, ssig2, csig2, st["C3a"]) - float(st["B31"])))
	var lon12 := lam12 / DEG
	vals["lon2"] = _ang_normalize(_ang_normalize(float(st["lon1"])) + _ang_normalize(lon12))
	if outmask & LATITUDE:
		vals["lat2"] = _atan2d(sbet2, float(st["f1"]) * cbet2)
	if outmask & AZIMUTH:
		vals["azi2"] = _atan2d(salp2, calp2)
	if outmask & (REDUCEDLENGTH | GEODESICSCALE):
		var B22 := _sin_cos_series(true, ssig2, csig2, st["C2a"])
		var AB2 := (1.0 + float(st["A2m1"])) * (B22 - float(st["B21"]))
		var J12 := (float(st["A1m1"]) - float(st["A2m1"])) * sig12 + (AB1 - AB2)
		if outmask & REDUCEDLENGTH:
			vals["m12"] = float(st["b"]) * ((dn2 * (float(st["csig1"]) * ssig2)
					- float(st["dn1"]) * (float(st["ssig1"]) * csig2))
					- float(st["csig1"]) * csig2 * J12)
		if outmask & GEODESICSCALE:
			var t := float(st["k2"]) * (ssig2 - float(st["ssig1"])) * (ssig2 + float(st["ssig1"]))
			t /= (float(st["dn1"]) + dn2)
			vals["M12"] = csig12 + (t * ssig2 - csig2 * J12) * float(st["ssig1"]) / float(st["dn1"])
			vals["M21"] = csig12 - (t * float(st["ssig1"]) - float(st["csig1"]) * J12) * ssig2 / dn2
	if outmask & AREA:
		var B42 := _sin_cos_series(false, ssig2, csig2, st["C4a"])
		var salp12 := 0.0
		var calp12 := 0.0
		if float(st["calp0"]) == 0.0 or float(st["salp0"]) == 0.0:
			salp12 = salp2 * float(st["calp1"]) - calp2 * float(st["salp1"])
			calp12 = calp2 * float(st["calp1"]) + salp2 * float(st["salp1"])
		else:
			if csig12 <= 0.0:
				salp12 = float(st["calp0"]) * float(st["salp0"]) * (float(st["csig1"]) * (1.0 - csig12) + ssig12 * float(st["ssig1"]))
			else:
				salp12 = float(st["calp0"]) * float(st["salp0"]) * (ssig12 * (float(st["csig1"]) * ssig12 / (1.0 + csig12) + float(st["ssig1"])))
			calp12 = _sq(float(st["salp0"])) + _sq(float(st["calp0"])) * float(st["csig1"]) * csig2
		vals["S12"] = float(st["c2"]) * atan2(salp12, calp12) + float(st["A4"]) * (B42 - float(st["B41"]))
	if not arcmode:
		vals["a12"] = sig12 / DEG
	return vals

# ---------- 公开数值接口 ----------

## 反解数值版：{lat1, lon1, lat2, lon2, azi1, azi2, s12, a12, m12, M12, M21, S12, converged, numit}
## 输入越界（|lat|>90）返回 {}。
func inverse_v(lat1: float, lon1: float, lat2: float, lon2: float) -> Dictionary:
	if not is_valid():
		return {}
	if not (is_finite(lat1) and is_finite(lon1) and is_finite(lat2) and is_finite(lon2)):
		return {}
	if absf(lat1) > 90.0 or absf(lat2) > 90.0:
		return {}
	var outmask := OUT_FULL & OUT_MASK
	var r := _inverse_int(lat1, lon1, lat2, lon2, outmask)
	var vals: Dictionary = r["vals"]
	vals["azi1"] = _atan2d(float(r["salp1"]), float(r["calp1"]))
	vals["azi2"] = _atan2d(float(r["salp2"]), float(r["calp2"]))
	vals["converged"] = bool(r["converged"])
	vals["numit"] = int(r["numit"])
	return vals

## 正解数值版（距离模式）：{lat1, lon1, azi1, lat2, lon2, azi2, s12, a12, m12, M12, M21, S12}
func direct_v(lat1: float, lon1: float, azi1: float, s12: float) -> Dictionary:
	if not is_valid():
		return {}
	if not (is_finite(lat1) and is_finite(lon1) and is_finite(azi1) and is_finite(s12)):
		return {}
	if absf(lat1) > 90.0:
		return {}
	var st := _make_line_state(lat1, lon1, azi1)
	return _gen_position(st, false, s12, OUT_FULL & OUT_MASK)

## 弧长模式正解（a12 给弧长、度）。
func arcdirect_v(lat1: float, lon1: float, azi1: float, a12: float) -> Dictionary:
	if not is_valid():
		return {}
	if not (is_finite(lat1) and is_finite(lon1) and is_finite(azi1) and is_finite(a12)):
		return {}
	if absf(lat1) > 90.0:
		return {}
	var st := _make_line_state(lat1, lon1, azi1)
	return _gen_position(st, true, a12, OUT_FULL & OUT_MASK)

## 大地线对象（正解沿线多点）：返回状态字典，配合 geodesic_position 使用。
func line(lat1: float, lon1: float, azi1: float) -> Dictionary:
	return _make_line_state(lat1, lon1, azi1)

## 沿 line 状态求 s12 处位置（数值版）。
static func geodesic_position(st: Dictionary, s12: float) -> Dictionary:
	return _gen_position(st, false, s12, OUT_FULL & OUT_MASK)

## WGS84 实例
static func wgs84() -> GKGeodesic:
	return GKGeodesic.new(6378137.0, 1.0 / 298.257223563)

## CGCS2000 实例
static func cgcs2000() -> GKGeodesic:
	return GKGeodesic.new(6378137.0, 1.0 / 298.257222101)

# ---------- §5 协议入口 ----------

## 从参数字典建实例：datum 名 或 a/inv_f；两者皆缺省 WGS84。
## 指定了未知 datum 名返回 null（不静默回落默认椭球）。
static func _geod_of(p: Dictionary) -> GKGeodesic:
	var datum := String(p.get("datum", ""))
	if datum != "":
		var el := GKEllipsoid.params(datum)
		if el.is_empty():
			return null
		return GKGeodesic.new(float(el["a"]), float(el["f"]))
	var a := float(p.get("a", 6378137.0))
	var inv_f := float(p.get("inv_f", 298.257223563))
	if a > 0.0 and inv_f > 0.0:
		return GKGeodesic.new(a, 1.0 / inv_f)
	return null

static func _fail(err: String, formula: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": err}

## §5 协议：大地线反解。p = {lat1_deg, lon1_deg, lat2_deg, lon2_deg, datum|a+inv_f}
static func inverse(p: Dictionary) -> Dictionary:
	var formula := "大地线反解（Karney 算法，逐行移植 geographiclib-js v2.2.0，MIT）"
	var geod := _geod_of(p)
	if geod == null or not geod.is_valid():
		return _fail("椭球参数缺失或不合法（需 datum 名或 a>0、1/f>0）", formula)
	var lat1 := float(p.get("lat1_deg", NAN))
	var lon1 := float(p.get("lon1_deg", NAN))
	var lat2 := float(p.get("lat2_deg", NAN))
	var lon2 := float(p.get("lon2_deg", NAN))
	for v in [lat1, lon1, lat2, lon2]:
		if not is_finite(v):
			return _fail("输入不是有效数值（两端经纬度需为数字）", formula)
	if absf(lat1) > 90.0 or absf(lat2) > 90.0:
		return _fail("纬度超出范围：|B| ≤ 90°", formula)
	var v := geod.inverse_v(lat1, lon1, lat2, lon2)
	if v.is_empty():
		return _fail("输入非法，无法反解", formula)
	if not bool(v.get("converged", false)) or not is_finite(float(v.get("s12", NAN))) \
			or not is_finite(float(v.get("azi1", NAN))) or not is_finite(float(v.get("azi2", NAN))):
		return _fail("近对跖情形迭代未收敛：两点接近对跖点时该解不稳定，建议改用分段的近似解或检查点位", formula)
	var steps := [
		{"title": "1. 规范化与辅助球面量",
			"formula": "β = atan((1−f)·tan φ)；经差 λ₁₂ 归一到 [−180°,180°]",
			"substitution": "B₁ = %s°，L₁ = %s°；B₂ = %s°，L₂ = %s°" % [String.num(lat1, 9), String.num(lon1, 9), String.num(lat2, 9), String.num(lon2, 9)],
			"result": "椭球 a = %s m，1/f = %s" % [String.num(geod.a, 3), String.num(1.0 / geod.f, 9)]},
		{"title": "2. Newton 迭代解 λ₁₂(α₁) = λ₁₂₀",
			"formula": "六阶 Clenshaw 级数（A1/C1/A2/C2/A3/C3）+ 区间套 Newton，容差 |λ12| < 2.22e-16 rad",
			"substitution": "迭代 %d 轮收敛" % int(v.get("numit", 0)),
			"result": "α₁ = %s°，α₂ = %s°" % [String.num(float(v["azi1"]), 9), String.num(float(v["azi2"]), 9)]},
		{"title": "3. 距离化算",
			"formula": "s₁₂ = b·A1·(σ₁₂ + B1(σ₂) − B1(σ₁))，σ₁₂ 由迭代给出",
			"substitution": "b = %s m" % String.num(geod.b, 4),
			"result": "s₁₂ = %s m（弧长 a₁₂ = %s°）" % [String.num(float(v["s12"]), 4), String.num(float(v["a12"]), 9)]},
	]
	return {
		"ok": true,
		"value": {
			"azi1_deg": float(v["azi1"]), "azi2_deg": float(v["azi2"]),
			"s12_m": float(v["s12"]), "a12_deg": float(v["a12"]),
			"m12_m": float(v.get("m12", NAN)), "S12_m2": float(v.get("S12", NAN)),
		},
		"steps": steps,
		"formula": formula,
		"error": "",
	}

## §5 协议：大地线正解。p = {lat1_deg, lon1_deg, azi1_deg, s12_m, datum|a+inv_f}
static func direct(p: Dictionary) -> Dictionary:
	var formula := "大地线正解（Karney 算法，逐行移植 geographiclib-js v2.2.0，MIT）"
	var geod := _geod_of(p)
	if geod == null or not geod.is_valid():
		return _fail("椭球参数缺失或不合法（需 datum 名或 a>0、1/f>0）", formula)
	var lat1 := float(p.get("lat1_deg", NAN))
	var lon1 := float(p.get("lon1_deg", NAN))
	var azi1 := float(p.get("azi1_deg", NAN))
	var s12 := float(p.get("s12_m", NAN))
	for v in [lat1, lon1, azi1, s12]:
		if not is_finite(v):
			return _fail("输入不是有效数值（起点经纬度/方位/距离需为数字）", formula)
	if absf(lat1) > 90.0:
		return _fail("纬度超出范围：|B| ≤ 90°", formula)
	var v := geod.direct_v(lat1, lon1, azi1, s12)
	if v.is_empty() or not is_finite(float(v.get("lat2", NAN))) or not is_finite(float(v.get("lon2", NAN))):
		return _fail("输入非法，无法正解", formula)
	var steps := [
		{"title": "1. 构造大地线（GeodesicLine）",
			"formula": "由 (B₁, L₁, α₁) 展开 A1/C1/A2/C2/A3/C3 六阶级数与 τ₁ = σ₁ + B11",
			"substitution": "B₁ = %s°，L₁ = %s°，α₁ = %s°，s₁₂ = %s m" % [String.num(lat1, 9), String.num(lon1, 9), String.num(azi1, 9), String.num(s12, 4)],
			"result": "椭球 a = %s m，1/f = %s" % [String.num(geod.a, 3), String.num(1.0 / geod.f, 9)]},
		{"title": "2. 求 σ₂ 并展开到端点",
			"formula": "τ₁₂ = s₁₂/(b·A1)；σ₁₂ = τ₁₂ − (B12 − B11)（|f|>0.01 时补 Newton 一轮）",
			"substitution": "b = %s m" % String.num(geod.b, 4),
			"result": "a₁₂ = %s°" % String.num(float(v.get("a12", NAN)), 9)},
		{"title": "3. 端点坐标与反方位角",
			"formula": "B₂ = atan2d(sinβ₂, (1−f)·cosβ₂)；L₂ = L₁ + λ₁₂；α₂ = atan2d(sinα₀, cosα₀·cosσ₂)",
			"substitution": "由展开级数求和给出",
			"result": "B₂ = %s°，L₂ = %s°，α₂ = %s°" % [String.num(float(v["lat2"]), 9), String.num(float(v["lon2"]), 9), String.num(float(v["azi2"]), 9)]},
	]
	return {
		"ok": true,
		"value": {
			"lat2_deg": float(v["lat2"]), "lon2_deg": float(v["lon2"]),
			"azi2_deg": float(v["azi2"]), "a12_deg": float(v.get("a12", NAN)),
			"m12_m": float(v.get("m12", NAN)), "S12_m2": float(v.get("S12", NAN)),
		},
		"steps": steps,
		"formula": formula,
		"error": "",
	}
