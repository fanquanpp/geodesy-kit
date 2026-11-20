# app/module_catalog.gd —— 模块注册表唯一入口（ARCHITECTURE.md §3）
#
# 契约要点：
#   - 每个施工域在 scenes/calculators/<域>/manifest.json 自描述（§3.2 契约）；
#   - manifest 缺失/损坏：静默跳过，不阻断启动；条目缺 scene 文件：跳过并 push_warning；
#   - id 全局唯一：重复 id 后到者丢弃并 push_warning；
#   - 施工者不得修改本文件（app/ 共享白名单）。
class_name GKModuleCatalog
extends RefCounted

var _entries: Dictionary = {}       # id -> 归一化条目（含 domain 字段）
var _order: Array = []              # 加载顺序的 id（导航稳定排序用）
var _domains_loaded: Array = []     # 有 manifest 的域
var _domain_entries: Dictionary = {}  # domain -> Array[id]
var _domain_icons: Dictionary = {}    # domain -> 图标路径（manifest 顶层 icon；缺失为 ""）

func load_all() -> Array:
	_entries.clear()
	_order.clear()
	_domains_loaded.clear()
	_domain_entries.clear()
	_domain_icons.clear()
	for domain: String in GKModuleIndex.DOMAINS:
		var path := "res://scenes/calculators/%s/manifest.json" % domain
		if not FileAccess.file_exists(path):
			continue  # 静默跳过：渐进集成，施工域未就位属正常状态
		var entries := load_manifest_file(path)
		if entries.is_empty():
			continue
		add_entries(entries, domain)
		_domain_icons[domain] = _read_manifest_icon(path)
		if not _domains_loaded.has(domain):
			_domains_loaded.append(domain)
	return _order.duplicate()

## 读取 manifest 顶层 icon 字段（缺失/损坏返回 ""）
func _read_manifest_icon(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return ""
	return String(parsed.get("icon", ""))

## 域图标路径（导航分类卡用；未登记返回 ""，调用方按首字方块兜底）
func domain_icon(domain: String) -> String:
	return String(_domain_icons.get(domain, ""))

## 解析单个 manifest.json → 归一化条目数组。文件缺失/JSON 损坏返回 []。
## 供 load_all 与测试复用；不负责查重（查重在 add_entries）。
func load_manifest_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("模块 manifest 无法读取：%s" % path)
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("模块 manifest 不是 JSON 对象：%s" % path)
		return []
	var raw: Array = parsed.get("entries", [])
	var out := []
	for e: Dictionary in raw:
		var norm := _normalize_entry(e, String(parsed.get("domain", "")), path)
		if not norm.is_empty():
			out.append(norm)
	return out

## 登记条目（测试可直接注入）。id 冲突丢弃后者并 push_warning。
## 首次实际登记某域条目时，该域进入已加载域列表（导航树可见）。
func add_entries(entries: Array, domain: String) -> void:
	var added := false
	for e: Dictionary in entries:
		var id: String = e.get("id", "")
		if id.is_empty() or _entries.has(id):
			if not id.is_empty():
				push_warning("模块条目 id 重复，丢弃后者：%s（%s）" % [id, domain])
			continue
		if String(e.get("domain", "")) == "":
			e["domain"] = domain
		_entries[id] = e
		_order.append(id)
		added = true
		var ed: String = e["domain"]
		if not _domain_entries.has(ed):
			_domain_entries[ed] = []
		_domain_entries[ed].append(id)
	if added and not _domains_loaded.has(domain):
		_domains_loaded.append(domain)

func _normalize_entry(e: Variant, domain: String, src_path: String) -> Dictionary:
	if not (e is Dictionary):
		push_warning("manifest 条目不是对象，跳过：%s" % src_path)
		return {}
	var id := String(e.get("id", ""))
	var name := String(e.get("name", ""))
	var scene := String(e.get("scene", ""))
	if id.is_empty() or name.is_empty() or scene.is_empty():
		push_warning("manifest 条目缺 id/name/scene，跳过：%s（id=%s）" % [src_path, id])
		return {}
	if not ResourceLoader.exists(scene):
		push_warning("条目场景不存在，跳过：%s → %s" % [id, scene])
		return {}
	return {
		"id": id,
		"name": name,
		"keywords": String(e.get("keywords", "")),
		"scene": scene,
		"domain": domain,
		"formula_ref": String(e.get("formula_ref", "")),
		"example": e.get("example", {}) if e.get("example", {}) is Dictionary else {},
		"favorite_default": bool(e.get("favorite_default", false)),
	}

## 按功能编号取条目；不存在返回 {}
func entry(id: String) -> Dictionary:
	return _entries.get(id, {})

## 全部条目（加载顺序）
func entries() -> Array:
	var out := []
	for id: String in _order:
		out.append(_entries[id])
	return out

## 全局搜索：name 包含（不区分大小写）OR keywords 任一分词命中。
## 空查询返回全部条目。
func search(query: String) -> Array:
	var q := query.strip_edges()
	if q.is_empty():
		return entries()
	var ql := q.to_lower()
	var out := []
	for id: String in _order:
		var e: Dictionary = _entries[id]
		if String(e["name"]).to_lower().contains(ql):
			out.append(e)
			continue
		var kw := String(e["keywords"]).to_lower()
		var hit := false
		for token in q.split(" ", false):
			if not token.is_empty() and kw.contains(token.to_lower()):
				hit = true
				break
		if hit:
			out.append(e)
	return out

## 导航树数据源：{domain: {title, entries: Array}}（仅含已加载域）
func by_domain() -> Dictionary:
	var out := {}
	for domain: String in _domains_loaded:
		var list := []
		for id: String in _domain_entries.get(domain, []):
			list.append(_entries[id])
		out[domain] = {
			"title": String(GKModuleIndex.DOMAIN_TITLES.get(domain, domain)),
			"entries": list,
		}
	return out

## 已登记条目总数
func count() -> int:
	return _order.size()
