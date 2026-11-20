# core/math/units.gd —— GK-M1-5 叶子库：测量常用单位换算（长度 / 面积）
#
# 换算因数全部为定义精确值（国际协议 / 国家标准口径，非量测近似值）：
#   1 ft（国际英尺）    = 0.3048 m             （1959 年国际码协议，定义精确）
#   1 us_survey_ft      = 1200/3937 m          （美制测图英尺，定义精确；
#                                              比国际英尺长约 2×10⁻⁶ 倍，测量旧资料换算必须区分）
#   1 mi（国际英里）    = 1609.344 m           （= 5280 ft × 0.3048，定义精确）
#   1 mu（亩）          = 2000/3 m²            （1 亩 = 60 平方丈，1 丈 = 10/3 m，定义精确）
#   1 ha（公顷）        = 10000 m²             （= 15 亩，定义精确）
#   1 acre（英亩）      = 4046.8564224 m²      （= 43560 international ft²，定义精确）
#
# 设计约定（沿用地基 GK-M1 四文件纪律）：
#   - 纯静态函数、零引擎依赖（extends RefCounted）；
#   - convert 一律"先乘出发因数归一到基准（m / m²），再除以目标因数"；
#   - 未知单位名 / 跨量纲 / 非有限输入 → 返回 NAN（is_nan 判别，不抛异常）；
#   - 单位键名用稳定英文短名（m/ft/us_survey_ft/m2/mu/ha/acre/...），
#     中文别名经 _ALIAS 映射接受；G5 全局单位制格式化后续按需只增不改。
#
# 权威向量：tests/mathk/test_units.gd
#   【权威·定义精确】1 英亩=4046.8564224 m²、1 亩=2000/3 m²；
#   面积例 152000 m² = 228 亩 = 15.2 公顷 = 37.560018 英亩（ARCHITECTURE.md §4 GK-M1）。
class_name GKUnits
extends RefCounted

## 长度因数表（→ 米）
const LENGTH_TO_M := {
	"m": 1.0,
	"km": 1000.0,
	"ft": 0.3048,
	"us_survey_ft": 1200.0 / 3937.0,
	"mi": 1609.344,
}

## 面积因数表（→ 平方米）
const AREA_TO_M2 := {
	"m2": 1.0,
	"mu": 2000.0 / 3.0,
	"ha": 10000.0,
	"acre": 4046.8564224,
	"km2": 1000000.0,
	"ft2": 0.3048 * 0.3048,
	"us_survey_ft2": (1200.0 / 3937.0) * (1200.0 / 3937.0),
}

## 中文别名 → 英文短名（仅接受两表内的目标键；两表共用的别名按量纲分表解析）
const _ALIAS := {
	"米": "m",
	"公里": "km",
	"千米": "km",
	"英尺": "ft",
	"测图英尺": "us_survey_ft",
	"美制测图英尺": "us_survey_ft",
	"英里": "mi",
	"平方米": "m2",
	"亩": "mu",
	"公顷": "ha",
	"英亩": "acre",
	"平方公里": "km2",
	"平方英尺": "ft2",
}

## 长度换算。未知单位/非有限输入 → NAN。
static func convert_length(value: float, from_unit: String, to_unit: String) -> float:
	return _convert(value, from_unit, to_unit, LENGTH_TO_M)

## 面积换算。未知单位/非有限输入 → NAN。
static func convert_area(value: float, from_unit: String, to_unit: String) -> float:
	return _convert(value, from_unit, to_unit, AREA_TO_M2)

## 长度 → 米
static func to_meter(value: float, from_unit: String) -> float:
	return _convert(value, from_unit, "m", LENGTH_TO_M)

## 米 → 目标长度单位
static func from_meter(value_m: float, to_unit: String) -> float:
	return _convert(value_m, "m", to_unit, LENGTH_TO_M)

## 面积 → 平方米
static func to_m2(value: float, from_unit: String) -> float:
	return _convert(value, from_unit, "m2", AREA_TO_M2)

## 平方米 → 目标面积单位
static func from_m2(value_m2: float, to_unit: String) -> float:
	return _convert(value_m2, "m2", to_unit, AREA_TO_M2)

## 面积一屏换算：{m2, mu, ha, acre, km2}（输入按平方米计）。
## 非有限输入返回 {}（is_empty 判别）。供 B6 面积计算器与 G5 单位制直接取用。
static func area_breakdown(value_m2: float) -> Dictionary:
	if not is_finite(value_m2):
		return {}
	return {
		"m2": value_m2,
		"mu": value_m2 / AREA_TO_M2["mu"],
		"ha": value_m2 / AREA_TO_M2["ha"],
		"acre": value_m2 / AREA_TO_M2["acre"],
		"km2": value_m2 / AREA_TO_M2["km2"],
	}

## 长度单位键名清单（稳定顺序 = 表内声明顺序）
static func list_length_units() -> Array:
	return LENGTH_TO_M.keys()

## 面积单位键名清单（稳定顺序 = 表内声明顺序）
static func list_area_units() -> Array:
	return AREA_TO_M2.keys()

# ---------- 内部工具 ----------

## 通用换算：value × F(from) ÷ F(to)。未知单位/非有限输入 → NAN。
static func _convert(value: float, from_unit: String, to_unit: String, table: Dictionary) -> float:
	if not is_finite(value):
		return NAN
	var fk := _resolve(from_unit, table)
	var tk := _resolve(to_unit, table)
	if fk == "" or tk == "":
		return NAN
	return value * table[fk] / table[tk]

## 单位名解析：先按英文短名，再按中文别名。未命中返回 ""。
static func _resolve(unit: String, table: Dictionary) -> String:
	var key := unit.strip_edges()
	if table.has(key):
		return key
	if _ALIAS.has(key):
		var canon: String = _ALIAS[key]
		if table.has(canon):
			return canon
	return ""
