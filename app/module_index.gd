# app/module_index.gd —— 域名常量（v0.4：删除控制平差/路线曲线/土方断面三域，
# 保留 ellipsoid/projection/transform/cogo 4 域 33 个教学计算器）
# 施工纪律：任何施工者不得修改本文件；域名常量是渐进集成的唯一接缝。
class_name GKModuleIndex
extends RefCounted

const DOMAINS := ["ellipsoid", "projection", "transform", "cogo"]

# manifest 缺失时导航的兜底中文标题（manifest 存在时以其 title 为准）
const DOMAIN_TITLES := {
	"ellipsoid": "椭球与大地线",
	"projection": "坐标与投影",
	"transform": "坐标转换与高程拟合",
	"cogo": "坐标几何与交会",
}
