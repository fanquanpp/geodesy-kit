# app/data_service.gd —— 数据装载服务（ARCHITECTURE.md §2 app 层职责）
#
# 职责：把 res://data/ 下的 JSON 与 PGM 文件读入内存，以 Dictionary/PackedByteArray
# 或解析后的对象传参进 core（core 不读盘，GK-M2 实现要点）。
# 说明：本文件由 GK-M2 施工按模块要点新建（PGM 读盘放 app/data_service.gd），
# 仅提供装载原语与 EGM2008 格网缓存；其余 JSON 表的接入由后续模块/集成者按需扩展（只增不改）。
class_name GKDataService
extends RefCounted

const GEOID_PATH := "res://data/geoids/egm2008-5.pgm"

static var _geoid_cache: GKGeoidEGM2008.Grid = null

## 读 res:// 路径原始字节。失败返回空 PackedByteArray（is_empty 判别）。
static func load_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("数据文件无法读取：%s（错误 %s）" % [path, str(FileAccess.get_open_error())])
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes

## 读 res:// 路径 JSON 并解析为 Dictionary/Array。失败返回 {}（判别 error 键或用 is_empty）。
static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("JSON 文件无法读取：%s（错误 %s）" % [path, str(FileAccess.get_open_error())])
		return {"error": "文件无法读取：%s" % path}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"error": "JSON 解析失败：%s" % path}
	return parsed

## EGM2008 5′ 格网（缓存单例）。读盘/解析失败返回 null。
## 用法：var g := GKDataService.egm2008_grid(); g.height(lat, lon)
static func egm2008_grid() -> GKGeoidEGM2008.Grid:
	if _geoid_cache != null:
		return _geoid_cache
	var bytes := load_bytes(GEOID_PATH)
	if bytes.is_empty():
		return null
	var grid := GKGeoidEGM2008.make_grid(bytes)
	if grid != null:
		_geoid_cache = grid
	return grid

## 清空缓存（测试用）。
static func clear_cache() -> void:
	_geoid_cache = null
