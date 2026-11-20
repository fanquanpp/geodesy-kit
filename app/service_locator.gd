# app/service_locator.gd —— 服务装配点（替代 autoload 的显式组合根）
#
# 为什么不用 autoload：headless --script（tests/run_tests.gd）不经过正常场景启动流程，
# autoload 依赖会破坏"core/服务层可独立测试"的地基目标。改为静态注册表：
# main.gd（组合根）调用 bootstrap()，计算器场景经 GKCalculatorBase 读取服务。
# 幂等：重复 bootstrap() 不重复建实例。
class_name GKServices
extends RefCounted

static var store: GKDataStore
static var catalog: GKModuleCatalog
static var settings: GKSettings
static var history: GKHistory
static var favorites: GKFavorites
static var points: GKPoints
static var _bootstrapped := false

## 装配全部服务（幂等）。store 后端自动选择（SQLite→JSON 降级，见 data_store.gd）。
static func bootstrap() -> void:
	if _bootstrapped:
		return
	store = GKDataStore.create()
	catalog = GKModuleCatalog.new()
	settings = GKSettings.new(store)
	history = GKHistory.new(store)
	favorites = GKFavorites.new(store)
	points = GKPoints.new(store)
	_bootstrapped = true

## 是否已装配
static func ready_state() -> bool:
	return _bootstrapped

## 模块目录惰性加载：返回 catalog（首次调用时 load_all）
static func ensure_catalog() -> GKModuleCatalog:
	bootstrap()
	if catalog.count() == 0 and catalog.by_domain().is_empty():
		catalog.load_all()
	return catalog

## 退出前落盘收尾
static func shutdown() -> void:
	if _bootstrapped and store != null:
		store.close()
	_bootstrapped = false
