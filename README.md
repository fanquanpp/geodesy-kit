# GeodesyKit

面向测绘 / GIS / 遥感 / 地质专业学生的**全离线计算器**。唯一职能：计算与数据处理——不做制图、不做 GIS 平台、不做账号体系。

- 引擎：Godot 4.7（GDScript，`gl_compatibility` 渲染）
- 架构：`docs/ARCHITECTURE.md`（总纲；与 `DEVELOPMENT_PLAN.md` 冲突处以前者为准）
- 平台矩阵：**Windows / Android / iOS** 三端（iOS 出包必须 macOS + Xcode）

## 运行方式

```bash
# 编辑器打开
godot --editor --path .

# 运行
godot --path .

# 全量单元测试（headless，退出码非 0 即失败）
godot --headless --path . --script res://tests/run_tests.gd

# 资源导入（首次/新增资源后）
godot --headless --path . --import

# 主题再生成（改配色后）
godot --headless --path . --script res://themes/build_theme.gd
```

## 目录速览

```
core/      纯计算内核（8 个施工域 + math 叶子库；零引擎依赖）
data/      参数库 JSON（ellipsoids / crs_presets / tolerance…）+ geoids/EGM2008
app/       应用服务（模块注册表 / 设置 / 历史 / 收藏 / 点库 / storage 双后端）
platform/  引擎 I/O 收口（剪贴板 / 文件）
scenes/    main 导航壳 + nav 页 + widgets 计算器契约基类 + calculators/<域>/
themes/    main.tres / dark.tres（Noto Sans SC 中文字体随包）
tests/     run_tests.gd 统一入口；每域一个子目录，runner 自动收集
assets/    fonts/（NotoSansSC Regular+Bold + OFL 许可副本）
```

## 模块接入契约（施工者必读）

1. 只新增/修改自己的 `core/<域>/`、`scenes/calculators/<域>/`、`tests/<域>/` 与新增 data JSON；共享文件（project.godot / themes / app / platform / scenes/main.tscn / scenes/nav / scenes/widgets / tests/run_tests.gd 等）不得改。
2. 在 `scenes/calculators/<域>/manifest.json` 自描述条目（id/name/keywords/scene/example），导航/搜索/收藏全部自动出现。
3. 计算器场景根脚本继承 `res://scenes/widgets/calculator_base.gd`，实现 `run()`（§5 forward 协议）、`get_inputs()/set_inputs()`。
4. `app/module_index.gd` 的 8 个域名常量已预填且此后只读。

## 离线与安全声明

- **纯离线**：无网络请求、无账号、无遥测；工程内禁止 `HTTPRequest` / `JavaScriptBridge`。
- **无凭据**：仓库内不含任何签名/密钥文件；`*.keystore`、`*.jks`、`*.p12` 等已进 `.gitignore`，签名凭据只在导出对话框或本机环境变量中提供。
- **数据本地化**：所有用户数据（设置/历史/收藏/点库/报告）存 `user://`（Windows 注册表目录 / Android 沙盒 / iOS 沙盒），SQLite 读写一律参数绑定。
- **教学定位**：所有计算结果标注公式出处与精度口径；报告导出尾注"教学演示用途，不替代生产级平差/工程软件"。

## 第三方组件与许可

| 组件 | 许可 | 用途 |
|---|---|---|
| Noto Sans SC（notofonts/noto-cjk） | SIL OFL 1.1（副本见 `assets/fonts/LICENSE-NotoSansSC-OFL1.1.txt`） | 全局中文字体，随包分发 |
| godot-sqlite v4.9（2shady4u） | MIT（见 `addons/godot-sqlite/LICENSE.md`） | 历史/收藏/设置/点库持久化 |
| geographiclib-js / chrisveness/geodesy | MIT | 大地线/投影算法移植底本（仅参考注释，不打包） |
