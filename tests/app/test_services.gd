# tests/app/test_services.gd —— app 服务层与主题资源回归（M0 地基自检）
# 覆盖：DataStore 双后端、settings/history/favorites/points、module_catalog、主题与字体。
extends "res://tests/test_case_base.gd"

const DataStore := preload("res://app/storage/data_store.gd")
const GKSettingsScript := preload("res://app/settings.gd")
const GKHistoryScript := preload("res://app/history.gd")
const GKFavoritesScript := preload("res://app/favorites.gd")
const GKPointsScript := preload("res://app/points.gd")
const Catalog := preload("res://app/module_catalog.gd")

func _cleanup_tables(store: GKDataStore) -> void:
	store.save_table("settings", [])
	store.save_table("history", [])
	store.save_table("favorites", [])
	store.save_table("points", [])

func test_sqlite_extension_available_and_store_roundtrip() -> void:
	# godot-sqlite v4.9 已入包（addons/godot-sqlite），headless 亦必须可加载
	assert_true(ClassDB.class_exists("SQLite"), "GDExtension 注册 SQLite 类")
	var store: GKDataStore = DataStore.create()
	assert_true(store.backend_name() == "sqlite" or store.backend_name() == "json",
			"后端应为 sqlite 或 json（实测=%s）" % store.backend_name())
	_cleanup_tables(store)
	var rid: int = store.append_row("history", {"title": "中文标题", "inputs": {"a": 1}})
	assert_true(rid > 0, "append_row 返回有效 rid")
	var rows := store.load_table("history")
	assert_eq(rows.size(), 1, "回读行数")
	assert_eq(String(rows[0]["title"]), "中文标题", "中文往返")
	assert_int_eq(int(rows[0]["rid"]), rid, "rid 回填")
	assert_true(store.update_row("history", rid, {"title": "改后"}), "update_row")
	assert_eq(String(store.load_table("history")[0]["title"]), "改后", "更新生效")
	assert_true(store.delete_row("history", rid), "delete_row")
	assert_eq(store.load_table("history").size(), 0, "删除后为空")
	store.close()

func test_json_store_roundtrip() -> void:
	var js := preload("res://app/storage/json_store.gd").new()
	assert_eq(js.backend_name(), "json", "JSON 后端名")
	_cleanup_tables(js)
	assert_true(js.save_table("points", [{"name": "A", "x_m": 1.0}]), "保存")
	var rows: Array = js.load_table("points")
	assert_eq(rows.size(), 1, "读回行数")
	assert_almost_eq(float(rows[0]["x_m"]), 1.0, 1e-15, "数值往返")
	var base_store: GKDataStore = preload("res://app/storage/data_store.gd").new()
	assert_eq(base_store.load_table("不存在表").size(), 0, "基类 load_table 返回空")
	assert_false(base_store.save_table("t", []), "基类 save_table 返回 false")

func test_settings_persistence_and_validation() -> void:
	var store: GKDataStore = DataStore.create()
	_cleanup_tables(store)
	var s1: GKSettings = GKSettingsScript.new(store)
	assert_almost_eq(float(s1.get_value("decimals")), 4.0, 1e-12, "默认小数位")
	assert_true(s1.set_value("decimals", 6), "合法设置")
	assert_false(s1.set_value("decimals", 13), "越界拒绝")
	assert_false(s1.set_value("ui_scale", 1.1), "非档位拒绝")
	assert_false(s1.set_value("unknown_key", 1), "未知键拒绝")
	# 新实例读回（持久化验证）
	var s2: GKSettings = GKSettingsScript.new(store)
	assert_int_eq(s2.get_decimals(), 6, "设置持久化读回")
	assert_eq(String(s2.get_value("unit_system")), "SI", "默认单位制")
	s1.set_value("decimals", 4)  # 恢复默认
	store.close()

func test_history_favorites_points() -> void:
	var store: GKDataStore = DataStore.create()
	_cleanup_tables(store)
	var h: GKHistory = GKHistoryScript.new(store)
	var base: int = h.list(0).size()
	var rid: int = h.add("a1_demo", "演示计算器", {"x_m": 100.0}, {"ok": true, "value": {"x_m": 200.0}})
	assert_true(rid > 0, "历史 rid")
	assert_int_eq(h.list(0).size(), base + 1, "历史追加")
	assert_int_eq(h.list_by_entry("a1_demo", 0).size(), 1, "按条目过滤")
	var rows: Array = h.list(0)
	assert_eq(String(rows[0]["entry_id"]), "a1_demo", "最新在前")
	assert_true(h.remove(rid), "删除历史")
	var fav: GKFavorites = GKFavoritesScript.new(store)
	assert_true(fav.toggle("a1_demo"), "收藏")
	assert_true(fav.is_favorite("a1_demo"), "已收藏")
	assert_eq(int(fav.list().size()), 1, "收藏列表")
	assert_false(fav.toggle("a1_demo"), "再切一次取消")
	var p: GKPoints = GKPointsScript.new(store)
	var prid: int = p.add_point({"name": "P1", "x_m": 500.0, "y_m": 1000.0})
	assert_true(prid > 0, "点库新增")
	assert_int_eq(p.add_point({"name": "", "x_m": 1.0, "y_m": 2.0}), -1, "无名拒绝")
	assert_int_eq(p.add_point({"name": "X", "x_m": NAN, "y_m": 2.0}), -1, "非有限坐标拒绝")
	assert_int_eq(p.find_by_name("P1", true).size(), 1, "按名查找")
	assert_true(p.update_point(prid, {"h_m": 42.0}), "更新高程")
	var pts: Array = p.list_points()
	assert_almost_eq(float(pts[0]["h_m"]), 42.0, 1e-12, "高程读回")
	assert_true(p.remove_point(prid), "删点")
	store.close()

func test_catalog_production_path_and_injection() -> void:
	# 集成期修订（原 test_catalog_with_no_manifests_and_injection）：
	# Wave 1 后 8 个域 manifest 已全部就位，工程内 load_all() 不再为空——
	# 原"无 manifest 静默为空"前提失效（M8 报告：cogo manifest 入位即失效）。
	# 现按生产路径断言真实装载；"空目录"前提改用不存在的临时目录验证。
	var cat: GKModuleCatalog = Catalog.new()
	var order: Array = cat.load_all()
	assert_true(order.size() > 0, "工程 manifest 就位后 load_all 非空（实际=%d）" % order.size())
	assert_false(cat.by_domain().is_empty(), "导航树非空")
	assert_false(cat.search("").is_empty(), "空搜索返回全部条目")
	assert_true(cat.entry("不存在的id_xyz").is_empty(), "未知 id 为空")
	# 条目 scene 文件真实存在（坏 scene 条目在 normalize 阶段被跳过）
	for e: Dictionary in cat.entries():
		assert_true(ResourceLoader.exists(String(e["scene"])), "条目场景存在：" + String(e["id"]))
	# 域标题来自 manifest title（或 DOMAIN_TITLES 兜底），非空
	var by_all: Dictionary = cat.by_domain()
	for domain: String in by_all:
		assert_false(String(by_all[domain]["title"]).is_empty(), "域标题非空：" + domain)
	# 注入测试（load_manifest_file + add_entries 契约）
	# 注入测试（load_manifest_file + add_entries 契约）：独立 catalog 实例上验证，
	# 生产 catalog 已装载 88 条目，注入计数须带上其基数。
	var inj_cat: GKModuleCatalog = Catalog.new()
	var tmp := "user://test_manifest.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"domain": "ellipsoid", "title": "椭球与大地线",
		"entries": [
			{"id": "t1_ok", "name": "有效条目", "keywords": "测试 demo", "scene": "res://icon.svg"},
			{"id": "t2_bad", "name": "场景缺失", "scene": "res://不存在的场景.tscn"},
		],
	}))
	f.close()
	var entries: Array = inj_cat.load_manifest_file(tmp)
	assert_eq(entries.size(), 1, "场景缺失条目被跳过")
	assert_eq(String(entries[0]["id"]), "t1_ok", "有效条目保留")
	inj_cat.add_entries(entries, "ellipsoid")
	inj_cat.add_entries(entries, "ellipsoid")  # 重复 id → 丢弃后者
	assert_eq(inj_cat.count(), 1, "id 查重")
	assert_eq(String(inj_cat.entry("t1_ok")["domain"]), "ellipsoid", "域归一")
	var found: Array = inj_cat.search("demo")
	assert_eq(found.size(), 1, "keywords 命中")
	var found2: Array = inj_cat.search("有效")
	assert_eq(found2.size(), 1, "name 包含命中")
	var by_domain: Dictionary = inj_cat.by_domain()
	assert_eq(String(by_domain["ellipsoid"]["title"]), "椭球与大地线", "域标题兜底")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	# 空 manifest 目录路径：静默为空、不阻断（原"无 manifest"前提在独立 catalog 上验证）
	var empty_cat: GKModuleCatalog = Catalog.new()
	assert_eq(empty_cat.load_manifest_file("res://scenes/calculators/不存在的目录/manifest.json").size(), 0,
			"缺失 manifest 文件静默返回空")

func test_theme_and_fonts() -> void:
	# 字体随包（Android 厂商回退不可控 → 自带 Noto Sans SC，OFL 1.1）
	var reg := "res://assets/fonts/NotoSansSC-Regular.otf"
	var bold := "res://assets/fonts/NotoSansSC-Bold.otf"
	assert_true(FileAccess.file_exists(reg), "Regular 字体存在")
	assert_true(FileAccess.file_exists(bold), "Bold 字体存在")
	var regf := load(reg)
	assert_true(regf != null, "Regular 可加载为 FontFile")
	var main := load("res://themes/main.tres") as Theme
	assert_true(main != null, "main.tres 可加载")
	if main != null:
		assert_true(main.default_font != null, "默认字体已挂接")
		assert_eq(main.get_type_variation_base("Header"), &"Label", "Header 变体基类")
		assert_eq(main.get_type_variation_base("Muted"), &"Label", "Muted 变体基类")
		assert_eq(main.get_type_variation_base("Card"), &"PanelContainer", "Card 变体基类")
		assert_eq(main.get_type_variation_base("PrimaryButton"), &"Button", "PrimaryButton 变体基类")
		assert_true(main.has_color("font_color", "ErrorLabel"), "限差/错误语义色")
		assert_true(main.get_meta("bg_color", null) != null, "清屏色元数据")
		assert_int_eq(int(main.get_font_size("font_size", "Header")), 40, "标题字号")
	var dark := load("res://themes/dark.tres") as Theme
	assert_true(dark != null, "dark.tres 可加载")
	if dark != null:
		assert_eq(dark.get_type_variation_base("Header"), &"Label", "dark Header 变体")
