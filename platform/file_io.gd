# platform/file_io.gd —— 文件读写封装（引擎 I/O 统一收口）
#
# 职责：res:// 只读、user:// 读写、桌面端"另存为"路径提示。
# KMZ 打包（ZIPPacker）在 Wave 2 报告导出时接入（引擎内置类已验证存在）。
class_name GKFileIO
extends RefCounted

## 读文本文件。失败返回 ""（is_empty 结合 ok 出参判别）。
static func read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

## 写文本（user:// 或绝对路径）。res:// 只读工程内禁止写入，返回 false。
static func write_text(path: String, text: String) -> bool:
	if path.begins_with("res://"):
		return false
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

## 读 JSON 文件 → Variant（损坏返回 null）
static func read_json(path: String) -> Variant:
	var text := read_text(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)

## 列目录下指定后缀的文件名（递归 depth=0 仅当前层）。目录不存在返回 []。
static func list_files(dirpath: String, suffix := "") -> Array:
	var out := []
	var d := DirAccess.open(dirpath)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and (suffix.is_empty() or f.ends_with(suffix)):
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
