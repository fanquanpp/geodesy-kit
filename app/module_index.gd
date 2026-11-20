# app/module_index.gd —— 域名常量（M0 预填 8 个施工域；集成期增补 tools=G 组工具）
# 施工纪律：任何施工者不得修改本文件；域名常量是渐进集成的唯一接缝。
class_name GKModuleIndex
extends RefCounted

const DOMAINS := ["ellipsoid", "projection", "transform", "cogo",
                  "adjustment", "route", "astro", "topics", "tools"]

# manifest 缺失时导航的兜底中文标题（manifest 存在时以其 title 为准）
const DOMAIN_TITLES := {
	"ellipsoid": "椭球与大地线",
	"projection": "坐标与投影",
	"transform": "坐标转换与高程拟合",
	"cogo": "坐标几何与交会",
	"adjustment": "控制测量与平差",
	"route": "路线、曲线与土方",
	"astro": "天文与时间",
	"topics": "专题计算（GNSS/摄影/GIS/地质）",
	"tools": "批量与工具（G 组）",
}
