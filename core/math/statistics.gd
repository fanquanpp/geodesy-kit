# core/math/statistics.gd —— GK-M1 叶子库：测量统计（均值/中位数/中误差/贝塞尔/相对误差/莱依达）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M1）：
#   - 纯静态函数、零引擎依赖（extends RefCounted）；
#   - "中误差" = 样本标准差（贝塞尔公式，除以 n-1），为测量学口径；
#     population_* 为除以 n 的口径（教学对照用）；
#   - 空输入 / n<2：返回 NAN（调用方用 is_nan() 判别，不抛异常）；
#   - 排序使用 PackedFloat64Array.sort()，不修改调用方的原数组。
class_name GKStatistics
extends RefCounted

## 算术平均值；空表返回 NAN
static func mean(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return NAN
	var s := 0.0
	for x in v:
		s += x
	return s / v.size()

## 中位数；空表返回 NAN
static func median(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return NAN
	var s := PackedFloat64Array(v)
	s.sort()
	var n := s.size()
	if n % 2 == 1:
		return s[n / 2]
	return 0.5 * (s[n / 2 - 1] + s[n / 2])

## 样本方差（贝塞尔公式，除以 n-1）；n<2 返回 NAN
static func sample_variance(v: PackedFloat64Array) -> float:
	if v.size() < 2:
		return NAN
	var mu := mean(v)
	var ss := 0.0
	for x in v:
		ss += (x - mu) * (x - mu)
	return ss / (v.size() - 1)

## 总体方差（除以 n）；n<1 返回 NAN
static func population_variance(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return NAN
	var mu := mean(v)
	var ss := 0.0
	for x in v:
		ss += (x - mu) * (x - mu)
	return ss / v.size()

## 中误差（贝塞尔公式）：σ = √(Σv²/(n-1))
static func std_sample(v: PackedFloat64Array) -> float:
	var s2 := sample_variance(v)
	if is_nan(s2):
		return NAN
	return sqrt(s2)

## 总体标准差（除以 n）
static func std_population(v: PackedFloat64Array) -> float:
	var s2 := population_variance(v)
	if is_nan(s2):
		return NAN
	return sqrt(s2)

## 均方根 RMS = √(Σx²/n)；空表返回 NAN
static func rms(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return NAN
	var ss := 0.0
	for x in v:
		ss += x * x
	return sqrt(ss / v.size())

## 相对中误差 σ/|X|（无 X 归一）。|mean_val|<1e-15 返回 NAN。
static func relative_error(sigma: float, mean_val: float) -> float:
	if is_nan(sigma) or is_nan(mean_val) or absf(mean_val) < 1e-15:
		return NAN
	return absf(sigma) / absf(mean_val)

## 相对中误差比例值 → "1/k" 文本（测量口径，如 1/10000）。ratio<=0 返回 "∞"。
static func relative_fraction_text(ratio: float) -> String:
	if not is_finite(ratio) or ratio <= 0.0:
		return "∞"
	var k := 1.0 / ratio
	return "1/%d" % int(floor(k + 0.5))

## 莱依达准则（3σ）粗差剔除。
## 返回 {kept: PackedFloat64Array, removed: PackedFloat64Array, mean: float, sigma: float, k_sigma: float}
## n<2 或 σ 非有限时原样返回（kept=v，removed 空）。
static func pauta_outliers(v: PackedFloat64Array, k_sigma := 3.0) -> Dictionary:
	var mu := mean(v)
	var sigma := std_sample(v)
	var kept := PackedFloat64Array()
	var removed := PackedFloat64Array()
	if v.size() < 2 or not is_finite(sigma):
		return {"kept": PackedFloat64Array(v), "removed": removed, "mean": mu, "sigma": sigma, "k_sigma": k_sigma}
	for x in v:
		if absf(x - mu) <= k_sigma * sigma:
			kept.append(x)
		else:
			removed.append(x)
	return {"kept": kept, "removed": removed, "mean": mu, "sigma": sigma, "k_sigma": k_sigma}
