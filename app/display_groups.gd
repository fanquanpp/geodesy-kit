# app/display_groups.gd —— 导航展示分组（重新规划的分类，P9）
#
# 为什么存在：原 7 个 manifest 域（椭球/投影/转换/几何/平差/路线/工具）按施工
# 域划分，条目数 5–19 不等，用户反馈「重新规划分类」。本模块把 65 个条目按
# 使用场景重组为 8 个展示组；manifest 域结构不动（施工纪律），只在 UI 层重映射。
# 条目以 id 前缀/语义归组，未列入映射表的条目回退原域组（渐进接入不丢条目）。
class_name GKDisplayGroups
extends RefCounted

## 展示组定义（顺序即导航顺序）
## icon 字段保留为组级兜底（组标题已不挂图标——4.7.2 add_title_bar_control
## 实测不生效，见 home_page.gd 同注释；条目图标走 DOMAIN_ICONS/entry_icon）。
const GROUPS := [
	{"key": "coords", "title": "坐标计算", "icon": "res://assets/icons/gk-m5-geometry-intersection.svg"},
	{"key": "proj", "title": "投影换算", "icon": "res://assets/icons/gk-m3-projection-zones.svg"},
	{"key": "datum", "title": "基准转换", "icon": "res://assets/icons/gk-m4-coordinate-transform.svg"},
	{"key": "intersect", "title": "交会定点", "icon": "res://assets/icons/gk-m5-geometry-intersection.svg"},
	{"key": "control", "title": "控制平差", "icon": "res://assets/icons/gk-m6-control-adjustment.svg"},
	{"key": "route", "title": "路线曲线", "icon": "res://assets/icons/gk-d-route-alignment.svg"},
	{"key": "earthwork", "title": "土方断面", "icon": "res://assets/icons/gk-e-earthwork-section.svg"},
	{"key": "util", "title": "查询工具", "icon": "res://assets/icons/gk-m2-ellipsoid-geodesic.svg"},
]

## 条目 id → 展示组 key（未列入者回退原 manifest 域映射，见 _fallback_group）
const ENTRY_GROUPS := {
	# —— 坐标计算（正反算/三维/点位关系）——
	"a1_polar_fwd": "coords", "a2_polar_inv": "coords",
	"a1_fwd_3d": "coords", "a2_inv_3d": "coords",
	"b7_affine": "coords", "b8_point_line": "coords",
	"b5_convert": "coords", "b5_propagate": "coords",
	"b6_area": "coords",
	# —— 投影换算（高斯/UTM/UPS/墨卡托/兰勃特/MGRS/分幅）——
	"a3_gauss_fwd": "proj", "a3_gauss_inv": "proj",
	"a4_zone_switch": "proj", "a5_zone_query": "proj",
	"a7_utm_fwd": "proj", "a7_utm_inv": "proj",
	"sheet_gbt13989": "proj", "sheet_gbt13989_lookup": "proj",
	# —— 基准转换（七参/四参/高程拟合/ITRF/RTK/BLH-XYZ）——
	"a6_blh_xyz": "datum", "a9_bursa": "datum", "a8_four_param": "datum",
	"a10_height_fit": "datum", # —— 交会定点（前方/侧方/后方/方位距离）——
	"b1_fwd_ang": "intersect",
	"b1_side": "intersect", "b1_resection": "intersect",
	"b2_az_dist": "intersect", "b9_circle_3p": "intersect", "b9_arc": "intersect", "b9_arc_3p": "intersect",
	# —— 控制平差（导线/水准/网平差/精度/限差）——
	"c1_open_traverse": "control", "c2_closed_traverse": "control",
	"c3_connect_traverse": "control", "c4_no_orient_traverse": "control",
	"c6_level_route": "control", "c7_level_net": "control",
	"c8_tolerance": "control", "c9_accuracy": "control", "c13_trig_height": "control",
	# —— 路线曲线（要素/缓和/中线/竖曲/放样/超高）——
	"b3_curve_elements": "route", "b4_spiral": "route",
	"d1_alignment_jd": "route", "d2_alignment_el": "route",
	"d3_vertical_curve": "route", "d4_stakeout": "route",
	# —— 土方断面 ——
	"e1_grid_volume": "earthwork", "e2_section_volume": "earthwork",
	"e3_dtm_volume": "earthwork", "e4_dist_slope": "earthwork",
	"e5_plumb": "earthwork", "e6_profile": "earthwork",
	# —— 查询工具（椭球参数/大地线/恒向线/高程异常）——
	"m2_1_ellipsoid_params": "util", "a11_geodesic": "util",
	"a12_rhumb": "util", "f2_geoid_egm2008": "util",
	"a15_kml_point": "util",
}

## manifest 域 → 兜底展示组（映射表未收录的条目按原域归组）
const DOMAIN_FALLBACK := {
	"ellipsoid": "util", "projection": "proj", "transform": "datum",
	"cogo": "coords", "adjustment": "control", "route": "route",
	"tools": "util",
}

## 展示分组数据源：[{key, title, icon, entries}]（仅含非空组，按 GROUPS 顺序）。
## entries 复用 catalog 的归一化条目（manifest 字段原样）；入参为 catalog.entries()。
static func group_entries(catalog_entries: Array) -> Array:
	var out: Array = []
	for g: Dictionary in GROUPS:
		out.append({
			"key": g["key"], "title": g["title"], "icon": g["icon"],
			"entries": [],
		})
	var by_key := {}
	for item: Dictionary in out:
		by_key[item["key"]] = item
	for e: Dictionary in catalog_entries:
		var id := String(e.get("id", ""))
		var gkey := String(ENTRY_GROUPS.get(id, DOMAIN_FALLBACK.get(e.get("domain", ""), "util")))
		if by_key.has(gkey):
			(by_key[gkey]["entries"] as Array).append(e)
	# 过滤空组（保持 GROUPS 顺序）
	return out.filter(func(item: Dictionary) -> bool: return not (item["entries"] as Array).is_empty())

## 单条目 → 展示组 key（与 group_entries 同一规则：映射表优先，未收录按域兜底）。
## 供搜索结果行等同源场景使用，不依赖 group_entries 全量遍历。
static func entry_group(entry_id: String, entry: Dictionary) -> String:
	if ENTRY_GROUPS.has(entry_id):
		return String(ENTRY_GROUPS[entry_id])
	return String(DOMAIN_FALLBACK.get(entry.get("domain", ""), "util"))

## 展示组 key → 图标路径（未登记/空 key 返回 ""）
static func group_icon(group_key: String) -> String:
	for g: Dictionary in GROUPS:
		if String(g["key"]) == group_key:
			return String(g["icon"])
	return ""

## 条目 → 图标路径：按 manifest 域取域图标（条目级不再复用展示组图标——
## route 域的 D 线路与 E 土方条目曾共用工形拱图标，辨识度差，已拆分）。
## 域 → 图标映射与各域 manifest 顶层 icon 同源。
const DOMAIN_ICONS := {
	"cogo": "res://assets/icons/gk-m5-geometry-intersection.svg",
	"projection": "res://assets/icons/gk-m3-projection-zones.svg",
	"transform": "res://assets/icons/gk-m4-coordinate-transform.svg",
	"adjustment": "res://assets/icons/gk-m6-control-adjustment.svg",
	"route": "res://assets/icons/gk-d-route-alignment.svg",
	"earthwork": "res://assets/icons/gk-e-earthwork-section.svg",
	"ellipsoid": "res://assets/icons/gk-m2-ellipsoid-geodesic.svg",
	"tools": "res://assets/icons/gk-m1-math-core.svg",
}

## route 域内 D 前缀（线路）→ 线路图标；E 前缀（土方）→ 土方图标
static func entry_icon(entry_id: String, entry: Dictionary) -> String:
	var domain := String(entry.get("domain", ""))
	if domain == "route":
		if entry_id.begins_with("e"):
			return String(DOMAIN_ICONS["earthwork"])
		return String(DOMAIN_ICONS["route"])
	if DOMAIN_ICONS.has(domain):
		return String(DOMAIN_ICONS[domain])
	# 未登记域：回退展示组图标（保持旧口径不丢图标）
	return group_icon(entry_group(entry_id, entry))
