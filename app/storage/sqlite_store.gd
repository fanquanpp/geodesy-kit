# app/storage/sqlite_store.gd —— DataStore 的 SQLite 后端（godot-sqlite v4.9，MIT）
#
# 设计（架构 §6 决策①）：
#   - 单文件 user://geodesykit.db；统一表结构 store(table_name, rid, data, ts)，
#     行体为 JSON 文本 —— 与 JSON 后端保持同一"表=行字典数组"语义，业务零感知；
#   - SQL 安全（Mimosa 硬约束）：凡含变量的 SQL 一律 query_with_bindings 参数绑定；
#     仅 DDL 常量语句用 query()；
#   - v4.9 API（README+ClassDB 本会话实测）：open_db() / query_with_bindings(sql, Array)
#     返回 bool，SELECT 结果在 query_result 属性（键为 StringName，取值前归一为 String）；
#     last_insert_rowid 为整型属性。
class_name GKSQLiteStore
extends GKDataStore

const DB_PATH := "user://geodesykit.db"

var _db: SQLite = null
var _open := false

func _init() -> void:
	if not ClassDB.class_exists(GKDataStore.SQLITE_CLASS):
		return
	_db = SQLite.new()  # GDExtension 注册的类；Node 基类，无需入树即可工作
	_db.path = DB_PATH
	_open = _db.open_db()
	if _open:
		# DDL：常量语句，无外部输入
		_db.query("CREATE TABLE IF NOT EXISTS store (table_name TEXT NOT NULL, rid INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL, ts REAL NOT NULL);")
		_db.query("CREATE INDEX IF NOT EXISTS idx_store_table ON store(table_name);")

func backend_name() -> String:
	return "sqlite"

## 创建是否成功（供工厂判断是否降级 JSON）
func open_ok() -> bool:
	return _open and _db != null

func load_table(table: String) -> Array:
	if not _ok_table(table):
		return []
	if not _exec("SELECT rid, data FROM store WHERE table_name = ? ORDER BY rid ASC;", [table]):
		return []
	var out := []
	for r: Dictionary in _db.query_result:
		var obj: Variant = JSON.parse_string(_s(r.get("data")))
		if obj is Dictionary:
			obj["rid"] = int(r.get("rid", 0))
			out.append(obj)
	return out

func save_table(table: String, rows: Array) -> bool:
	if not _ok_table(table):
		return false
	if not _exec("DELETE FROM store WHERE table_name = ?;", [table]):
		return false
	for row: Dictionary in rows:
		if append_row(table, row) < 0:
			return false
	return true

## 原生参数绑定查询（供点库/历史等后续需要索引查询时使用）
func query(sql: String, params: Array = []) -> Array:
	if not _open:
		return []
	if not _exec(sql, params):
		return []
	return _normalize(_db.query_result)

## 追加一行并返回分配的 rid（失败返回 -1）
func append_row(table: String, row: Dictionary) -> int:
	if not _ok_table(table):
		return -1
	var ok: bool = _exec(
		"INSERT INTO store (table_name, data, ts) VALUES (?, ?, ?);",
		[table, JSON.stringify(row), Time.get_unix_time_from_system()])
	if not ok:
		return -1
	return int(_db.last_insert_rowid)

## 按 rid 删除
func delete_row(table: String, rid: int) -> bool:
	if not _ok_table(table) or rid <= 0:
		return false
	return _exec("DELETE FROM store WHERE table_name = ? AND rid = ?;", [table, rid])

## 按 rid 整行替换（保留 rid）
func update_row(table: String, rid: int, row: Dictionary) -> bool:
	if not _ok_table(table) or rid <= 0:
		return false
	return _exec(
		"UPDATE store SET data = ?, ts = ? WHERE table_name = ? AND rid = ?;",
		[JSON.stringify(row), Time.get_unix_time_from_system(), table, rid])

func close() -> void:
	if _open and _db != null:
		_db.close_db()
		_open = false

func _exec(sql: String, params: Array) -> bool:
	if not _open:
		return false
	return bool(_db.query_with_bindings(sql, params))

## 表名白名单校验 + 连接状态（SQLite 不支持绑定表名/列名，硬约束下只走白名单）
func _ok_table(table: String) -> bool:
	if not _open or table.is_empty():
		return false
	for c in table:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true

## query_result 键为 StringName：归一为 String 键的 Dictionary
func _normalize(rows: Array) -> Array:
	var out := []
	for r: Dictionary in rows:
		var d := {}
		for k: Variant in r.keys():
			d[String(k)] = r[k]
		out.append(d)
	return out

func _s(v: Variant) -> String:
	if v is String:
		return v
	if v is StringName:
		return String(v)
	return str(v)
