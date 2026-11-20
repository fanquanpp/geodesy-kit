# core/math/errprop.gd —— GK-M1 叶子库：误差传播定律（协方差传播律的标量形式）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M1）：
#   - 纯静态函数、零引擎依赖（extends RefCounted）；
#   - 假定各观测量互相独立（协方差为 0）；相关情形由施工模块另行处理；
#   - 通用路径 propagate() 用数值中差分求偏导，仅依赖 Callable（引擎核心类型，
#     非 Node），符合"core 禁止引擎 API"的评审口径；
#   - 非有限输入返回 NAN，不抛异常。
class_name GKErrProp
extends RefCounted

## 线性组合 z = Σ c_i·x_i（x_i 独立）：σz = √(Σ c_i²·σ_i²)
## 例：σ(x+y) = √(σx²+σy²)；σ(k·x) = |k|·σx。长度不一致返回 NAN。
static func linear_sigma(coeffs: PackedFloat64Array, sigmas: PackedFloat64Array) -> float:
	if coeffs.size() != sigmas.size() or coeffs.is_empty():
		return NAN
	var ss := 0.0
	for i in coeffs.size():
		if not is_finite(sigmas[i]):
			return NAN
		ss += coeffs[i] * coeffs[i] * sigmas[i] * sigmas[i]
	return sqrt(ss)

## 乘积/商的相对中误差合成：(σz/z)² = (σx/x)² + (σy/y)²
static func product_relative_sigma(rel_x: float, rel_y: float) -> float:
	if not is_finite(rel_x) or not is_finite(rel_y):
		return NAN
	return sqrt(rel_x * rel_x + rel_y * rel_y)

## 通用传播定律：z = f(x1..xn)，σz² = Σ (∂f/∂x_i)²·σ_i²
## fn: Callable，接收 Array[float] 参数并返回 float（纯函数）。
## 偏导用中差分，步长 h_i = h·max(1, |x_i|)。fn 不可调用/结果非有限 → NAN。
static func propagate(fn: Callable, values: PackedFloat64Array, sigmas: PackedFloat64Array, h := 1e-6) -> float:
	if values.is_empty() or values.size() != sigmas.size() or not fn.is_valid():
		return NAN
	var ss := 0.0
	for i in values.size():
		if not is_finite(values[i]) or not is_finite(sigmas[i]):
			return NAN
		var hi := h * maxf(1.0, absf(values[i]))
		var vp := Array(values)
		var vm := Array(values)
		vp[i] = values[i] + hi
		vm[i] = values[i] - hi
		var f1: float = fn.call(vp)
		var f2: float = fn.call(vm)
		if not is_finite(f1) or not is_finite(f2):
			return NAN
		var dfdx := (f1 - f2) / (2.0 * hi)
		ss += dfdx * dfdx * sigmas[i] * sigmas[i]
	return sqrt(ss)
