# GeodesyKit 架构设计（ARCHITECTURE.md 完整版）

> 面向 GIS / 测绘 / 遥感 / 地质专业学生的全量离线计算器。
> 本文档是 DEVELOPMENT_PLAN.md（`DEVELOPMENT_PLAN.md`）的修订与深化，冲突处以本文为准。
> 引擎：Godot 4.7.2（本机实测 `Godot Engine v4.7.2.stable.steam.ed1daf0bf`，Steam 版位于
> `c:/atian/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`）。
> 平台范围（用户最新决定）：**Windows / Android / iOS 三端**。macOS 已放弃；
> Linux / Web 不在本次范围（`DEVELOPMENT_PLAN.md:5` 的六端范围废止，导出预设只写三端）。
> 渲染方式按官方建议调整，移动端兼容性优先（见 §1.3）。

---

## 0. 本文档的已实测事实与诚实声明

**本会话已实测通过（编写本文前逐项运行）：**

| 检查 | 命令 / 证据 | 结果 |
|---|---|---|
| 测试向量复核 | `python -I _scripts/verify_vectors.py`（Python 3.14.6 + pyproj 3.8.0 + geographiclib 2.1） | GeodTest.dat 3 行 0.0 mm；GN7-2 算例逐位一致；高斯 6 阶级数与 pyproj 差 ≤0.14 mm；水准网间接/条件双法一致；太阳 3 例与 pvlib 互差 ≤0.007° |
| 构造向量生成 | `python -I _scripts/gen_vectors_b.py` | B/E/I 组与 UPS/墨卡托/兰勃特/MGRS/恒向线向量全部生成并自洽检核（见 §6 各模块向量表） |
| UTM19N 全精度复核 | `pyproj EPSG:32619`，输入 (43.642556, −70.252228) | E=399002.5708, N=4832935.3412，与调研向量一致（早期脚本用了截断输入造成的差异已排除） |
| SQLite 三端预编译产物 | `gh release download v4.9 --repo 2shady4u/godot-sqlite` → addons.zip 72,102,324 B，`unzip -l` 列 bin/ | Windows x86_64 DLL、Android arm64+x86_64 .so（debug/release）、iOS 设备+模拟器 xcframework **全部存在**（另含 linux/macos/web 产物） |
| Noto Sans SC 资源与许可 | `gh release download Sans2.004 --repo notofonts/noto-cjk --pattern 18_NotoSansSC.zip`（50,077,940 B）；`gh api repos/notofonts/noto-cjk/contents/Sans/LICENSE` | 7 个字重 + LICENSE；许可原文 **SIL Open Font License 1.1**（可随包分发、可商用） |
| 测试框架两种退出码 | Steam Godot `--headless --script res://tests/run_tests.gd` | 全过 → 进程退出码 **0**；注入临时失败用例 → **1**；断言消息中文可读 |
| 引擎 API | `ClassDB.class_exists()`（headless 脚本实测） | ZIPPacker / ZIPReader / FoldableContainer / Expression / FileAccess / DirAccess 均存在 |
| GDScript 陷阱 | 本会话实测 | `"%g" % x` **不被 GDScript format 支持**（返回原串并报 variant 错误），必须用 `%.12f`/`str()`；三元运算符与 `%` 混用有优先级陷阱，断言基类已改为显式 if/else |

**落地时需补（本会话无法/未验证，相关模块施工者与集成者负责）：**

1. `F5 磁偏角（WMM）`：无本会话验证向量。`data/wmm.json` 系数取自 NGA 官方发布（美国政府作品，公共领域），实现后用 NOAA/NCEI WMM 计算器抽样比对，测试标注 `SKIP-WMM-DATA` 直到数据就位。
2. `C8 限差表`：`data/tolerance.json` 各等级限差公式需对照《工程测量标准》GB 50026 等规范文本逐条核读后填入（沿用调研结论：本会话未逐条核读规范限差表）。
3. `F7 ITRF 历元传播`：官方 ITRF 转换参数表（ITRF 发布，公共领域）落地时写入 `data/itrf_params.json`，本会话未验证具体数值。
4. iOS 出包：必须在 macOS + Xcode 完成（Windows 只能准备工程与预设）——沿用 `DEVELOPMENT_PLAN.md` 风险项声明。
5. GNSS 广播星历算例：无本会话验证向量，用构造自洽（开普勒方程迭代收敛性 + 退化圆轨道解析解对照）。

---

## 1. 总体决策

### 1.1 四层架构（沿用并修订 `DEVELOPMENT_PLAN.md:42-57`）

```
┌────────────────────────────────────────────────────┐
│ UI 层  scenes/  （main 导航壳 + calculators/<域>/ + widgets/）│
│      只画三个字段：结果 / 步骤 / 公式；不做任何算法       │
├────────────────────────────────────────────────────┤
│ 应用服务层 app/  （catalog/history/favorites/settings/      │
│      points/report/batch/storage + 编排跨域调用）           │
├────────────────────────────────────────────────────┤
│ 计算核心层 core/  ← 纯 GDScript，零引擎依赖                  │
│      8 个域模块 + math 叶子库；只允许 Dictionary/Array/      │
│      float/String/Vector 数学类型；禁止 Node/FileAccess      │
├────────────────────────────────────────────────────┤
│ 平台适配层 platform/  （clipboard/file_io/permissions）      │
│      所有引擎 I/O（文件、SQLite 节点、剪贴板、ZIP）在此       │
└────────────────────────────────────────────────────┘
依赖方向单向向下；core 之间禁止互相调用（M1 数学库除外——它是被所有人用的叶子库）。
跨域需求（如 C11 GNSS 网平差需要 BLH→XYZ）一律由 app 编排层先转换再传参，
不引入 core 横向依赖。
```

### 1.2 纯离线与信息安全约束（硬性）

1. **零网络**：全工程禁止 `HTTPRequest`、`JavaScriptBridge`、任何网络类；Web 端已移出范围，`DEVELOPMENT_PLAN.md:124-131` 的 JS 桥接分支整体删除。
2. **输入校验**：core 每个计算入口先做类型/范围/几何可行性校验（如距中央子午线超 3.5° 提示换 6° 带、交会角过小、闭合差为 NaN），失败返回中文可读 `error`，不抛异常不崩进程。
3. **SQL 安全**：所有持久化查询经 godot-sqlite 的参数绑定（`bind_params`），禁止字符串拼接 SQL（Mimosa 安全约束同口径）。
4. **无凭据**：无账号无遥测，无任何密钥字面量。
5. **数据目录隔离**：`_research/`、`_vendor_check/`、`_scripts/` 不进导出包（export_presets.cfg 排除过滤器 `!*_research/*,!*_vendor_check/*,!*_scripts/*`）。

### 1.3 渲染与窗口（移动端兼容性优先的官方建议口径）

现状 `project.godot:14-29`：`features=("4.7","Mobile")`、`stretch/mode="canvas_items"`、`aspect="expand"`、`rendering_method="mobile"`、`rendering_device/driver.windows="d3d12"`。

**M0 集成者修改清单**（共享文件，仅集成期改）：

| 项 | 值 | 理由 |
|---|---|---|
| `renderer/rendering_method` 与 `.mobile` | `gl_compatibility` | 官方对最大设备兼容性的建议；纯 UI 计算器无 Forward+/Mobile 特性收益；iOS 模拟器仅支持 Compatibility（调研结论）；显存占用最低利于低端安卓机 |
| `rendering_device/driver.windows="d3d12"` | 删除 | 该键属 RenderingDevice 后端（Forward+/Mobile），Compatibility 走 OpenGL3 不使用 |
| `application/features` | 编辑器自动改为 `("4.7","GL Compatibility")` | 随渲染方式自动刷新 |
| `display/window/handheld/orientation` | `portrait` | 移动端竖屏（调研口径：移动竖屏官方推荐 canvas_items+expand+portrait） |
| `display/window/size/viewport_width/height` | `720` / `1280` | 单一设计基准；触控目标 48dp≈96px，键盘按钮 `custom_minimum_size≥96×96`、间距≥8px（Material 3 口径换算） |
| `display/window/size/min_window_size`（桌面） | `960×540` | 非游戏应用官方建议：保留最小窗口尺寸 |
| stretch | 保持 `canvas_items` + `expand`（现状已正确，`project.godot:19-20`） | 官方明确 GUI/HUD 推荐口径；`expand` 让 720×1280 基准在桌面横窗自然延展 |
| 无障碍/UI 缩放 | 设置页暴露 `content_scale_factor` 档位（0.8/1.0/1.25/1.5） | 非游戏应用官方建议：暴露 UI 缩放兼作大字模式；字体按 scale 重采样不糊 |
| hiDPI | 保持开启 | 官方默认 |

### 1.4 导航形态（宽屏侧边栏 vs 窄屏底部导航）

官方无内置 Drawer/BottomNavigation（调研结论），用官方原语组合：

- **宽屏（≥900px 有效宽）**：`HBoxContainer{ VBox 侧边栏(fixed custom_minimum_size 240px) + 内容区(size_flags Expand) }`。
- **窄屏（<900px）**：隐藏侧边栏，底部 `TabBar` 做四类导航（首页分类 / 搜索 / 收藏 / 历史），抽屉 = `PanelContainer` + `Tween` 滑入 + 半透明 `ColorRect` 遮罩。
- 断点切换钩 `get_viewport().size_changed` 信号（`themes/responsive.gd` 统一实现）。

---

## 2. 目录结构（修订版）

```
res://
├── project.godot                 # M0 按 §1.3 修改（渲染/窗口/主场景/自定义主题）
├── export_presets.cfg            # 仅三端：Windows Desktop / Android / iOS
├── icon.svg
│
├── core/                         # 纯计算，零引擎依赖（§4 各模块文件明细）
│   ├── math/                     # GK-M1 叶子库
│   ├── ellipsoid/                # GK-M2
│   ├── projection/               # GK-M3
│   ├── transform/                # GK-M4
│   ├── cogo/                     # GK-M5
│   ├── adjustment/               # GK-M6
│   ├── route/                    # GK-M7（路线曲线）
│   ├── earthwork/                # GK-M7（土方）
│   ├── astro/                    # GK-M8（天文时间）
│   └── topics/                   # GK-M8（GNSS/摄影/GIS/地质）
│
├── data/                         # 参数库 JSON（core 不读盘，由 app 装载后传参）
│   ├── ellipsoids.json           # CGCS2000/北京54/西安80/WGS84/GRS80/IAG75/International1924/自定义
│   ├── crs_presets.json          # EPSG 带号/CM 预设表（CGCS2000 4491-4554；北京54 21413-21463+2401-2442；西安80 2327-2390）
│   ├── tolerance.json            # 导线/水准各等级限差（落地时按 GB 50026 等核读填写）
│   ├── formulas.json             # 公式库/百科（出处+适用条件），H 组与报告导出共用
│   ├── remote_indexes.json       # 遥感指数公式表
│   ├── itrf_params.json          # F7 ITRF 转换/速率参数（落地时填）
│   ├── wmm.json                  # F5 WMM 系数（落地时填，SKIP-WMM-DATA）
│   └── geoids/egm2008-5.pgm      # EGM2008 5′ 格网（解包后 18,671,444 B；对应官方 zip 16,773,259 B；本会话已解析验证：Offset=-108.0, Scale=0.003）
│
├── app/                          # 应用服务（集成者所有；施工模块只读）
│   ├── module_index.gd           # 8 个域名常量（M0 预填，此后不改）
│   ├── module_catalog.gd         # 扫描各域 manifest.json → 注册表/搜索/收藏索引
│   ├── settings.gd / history.gd / favorites.gd / points.gd
│   ├── report.gd                 # G3 报告导出（§5 协议渲染 Markdown/文本）
│   ├── batch_convert.gd          # G2 批量转换编排（调 M2/M3/M4）
│   ├── data_service.gd           # JSON/PGM 装载 → 传参进 core（core 不读盘）
│   └── storage/                  # sqlite_store.gd + json_store.gd（同一 DataStore 接口）
│
├── platform/                     # 引擎 I/O 适配（集成者所有）
│   ├── file_io.gd                # 读写/另存/目录；KMZ 用内置 ZIPPacker（本会话验证存在）
│   ├── clipboard.gd              # DisplayServer 剪贴板
│   └── dat_parser.gd             # G1 测量 DAT 自定义分隔格式解析（自写）
│
├── scenes/
│   ├── main.tscn                 # 导航壳（M0 建）
│   ├── widgets/                  # CalculatorBase + NumberField/DMSField/ResultCard/StepList/FormulaCard/LimitsPanel（M0 建，施工者只继承不改）
│   ├── nav/                      # 分类页/搜索页/收藏页/历史页（集成者）
│   └── calculators/
│       ├── ellipsoid/            # ┐
│       ├── projection/           # │ 每域一个目录：manifest.json（自描述条目）
│       ├── transform/            # │ + 各计算器 .tscn/.gd + icon.svg
│       ├── cogo/                 # │ 均为该域施工者自有文件
│       ├── adjustment/           # │
│       ├── route/                # │
│       ├── astro/                # │
│       └── topics/               # ┘
│
├── themes/
│   ├── main.tres                 # 主题 + type variations（Label/Header 等）
│   ├── dark.tres                 # 可整体热切换的第二套主题
│   ├── fonts/                    # NotoSansSC-Regular.otf (8,331,336 B) + Bold (8,543,168 B)
│   └── responsive.gd             # 断点逻辑
│
├── tests/
│   ├── run_tests.gd              # 统一入口（已建成并实测，§7）
│   ├── test_case_base.gd         # 断言基类（已建成并实测，§7）
│   ├── mathk/                    # ┐ 每个施工域一个子目录：
│   ├── ellipsoid/                # │ tests/<域>/test_*.gd
│   ├── projection/               # │ 由该域施工者自有
│   ├── transform/                # │
│   ├── cogo/                     # │
│   ├── adjustment/               # │
│   ├── route/  earthwork/        # │
│   ├── astro/  topics/           # ┘
│   └── _selfcheck/               # 框架自检用例（不进正式计数流程外的规范：常规保留为空或冒烟）
│
├── docs/ARCHITECTURE.md          # 本文档
├── DEVELOPMENT_PLAN.md           # 保留，平台范围/路线图以本文修订为准
├── _research/  _scripts/  _vendor_check/   # 调研资料/脚本/已核验依赖包（不进导出）
└── README.md
```

对 `DEVELOPMENT_PLAN.md:61-102` 的修订点：
- `core/tests/` 上移为工程级 `tests/`（测试与被测域同树、按域分目录，便于并行施工互不踩踏）；
- 删除 Web 专属分支与 `export_presets.cfg` 中 Linux/Web/macOS 预设；
- `core/` 从 12 个大文件拆为 10 个域目录（每域多个小类，单文件职责单一、diff 冲突面小）；
- 新增 `data/geoids/`（EGM2008 格网）、`app/storage/`（SQLite/JSON 双后端）、`app/module_index.gd + module_catalog.gd`（§3 注册机制）。

---

## 3. 模块注册与导航设计（施工期不改共享文件）

### 3.1 原则

1. **模块自描述**：每个施工域在自己目录 `scenes/calculators/<域>/manifest.json` 里声明全部计算器条目；导航/搜索/收藏全部由 manifest 驱动。
2. **共享文件白名单**：施工期施工者**不得**修改：`project.godot`、`export_presets.cfg`、`themes/`、`app/`、`platform/`、`scenes/main.tscn`、`scenes/nav/`、`scenes/widgets/`、`tests/run_tests.gd`、`tests/test_case_base.gd`、任何他人域目录。**只能新增/修改**：自己的 `core/<域>/`、`scenes/calculators/<域>/`、`tests/<域>/`，以及新增 data JSON（不覆盖共享键名）。
3. **集成点一次成型**：`app/module_index.gd` 在 M0 预填全部 8 个域名常量，此后不再改；各域 manifest 缺失或为空时 catalog 静默跳过——渐进集成无需任何共享文件编辑。

### 3.2 manifest.json 契约

```json
{
  "domain": "projection",
  "title": "坐标与投影",
  "icon": "res://scenes/calculators/projection/icon.svg",
  "entries": [
    {
      "id": "a3_gauss_fwd",
      "name": "高斯投影正算",
      "keywords": "高斯 正算 GK CGCS2000 北京54 西安80 3度带 6度带 带号 中央子午线",
      "scene": "res://scenes/calculators/projection/gauss_forward.tscn",
      "formula_ref": "gauss_kruger_fwd",
      "example": { "B_deg": "32.5", "L_deg": "118.25", "datum": "CGCS2000", "band3_zone": "auto" },
      "favorite_default": true
    }
  ]
}
```

- `id`：全局唯一，格式 `<功能编号>_<短名>`（与 §4 功能编号一致，用于历史/收藏/报告命名）。
- `formula_ref`：`data/formulas.json` 中的公式条目键（出处/适用条件由百科页展示）。
- `example`：示例按钮一键填入的输入快照（默认填教材经典算例）。
- `icon`：模块自有 SVG；没有就退化为标题首字方块（catalog 兜底渲染）。

### 3.3 目录与加载

```gdscript
# app/module_index.gd —— M0 预填，此后只读
const DOMAINS := ["ellipsoid", "projection", "transform", "cogo",
                  "adjustment", "route", "astro", "topics"]

# app/module_catalog.gd —— 唯一注册入口
func load_all() -> Array[Dictionary]   # 逐域 load manifest → 拼接 entries → 去重 id 校验（重复则 push_warning 并丢弃后者）
func search(query: String) -> Array[Dictionary]   # name 包含 OR keywords 分词命中
func entry(id: String) -> Dictionary
func by_domain() -> Dictionary          # 导航树数据源
```

- 加载失败/缺场景：跳过并 `push_warning`（不阻断启动）。
- 导航页 = 分类网格（域 → entries）；搜索页覆盖 name+keywords；收藏页读 `favorites` 表按 `id` 关联 entry。
- 计算器场景契约：根节点脚本必须继承 `res://scenes/widgets/calculator_base.gd`（M0 提供），实现 `run() -> Dictionary`（调 core）、`get_inputs()/set_inputs()`（供历史回放/示例填充）；CalculatorBase 内置输入区/结果卡/步骤列表/公式折叠（`FoldableContainer`，4.7 已验证存在）/限差面板/复制导出收藏按钮的骨架与主题绑定。

---

## 4. 8 个并行施工模块与测试向量分配

> 施工排布：**Wave 0** = M0 骨架（集成者）+ GK-M1（其余模块的唯一前置，API 冻结后再开 Wave 1）；**Wave 1** = GK-M2~GK-M8 七个模块完全并行；**Wave 2** = 集成（G 组/H 组/导航接线/三端导出）。
> 向量来源标注：【权威】= 外部权威算例（本会话已复核）；【构造】= 本会话按构造自洽法生成（`_scripts/gen_vectors_b.py`）；【落地补】= 施工时补充；【实测】= 本会话对打包/独立数据的实测值（无外部逐位权威向量时使用）。

### GK-M1 数学内核（Wave 0，其余模块的前置）

| | |
|---|---|
| **功能** | M1-1 `matrix.gd` 矩阵（乘/转置/求逆·部分主元高斯消元/Cholesky/解方程组）；M1-2 `least_squares.gd` 正规方程最小二乘 `N=BᵀPBx̂=BᵀPl`、残差 V、单位权中误差 μ=√(VᵀPV/(n−t))、协方差 Qxx=N⁻¹；M1-3 `statistics.gd` 均值/中位数/方差/标准差/RMS/相对误差/莱依达准则粗差剔除；M1-4 `angles.gd` 度分秒↔十进制度↔弧度↔gon、角度规范化、象限角、方位角推算；M1-5 `units.gd` 长度(m/ft/美制测图英尺)/面积(m²/亩=2000/3m²/公顷/英亩=4046.8564224m²)；M1-6 `errprop.gd` 误差传播定律（线性化偏导）；M1-7 `expression_calc.gd` 内置 `Expression` 类包装（科学表达式计算器 G7 用） |
| **文件** | `core/math/*.gd`（7 个文件）；测试 `tests/mathk/test_matrix.gd`、`test_least_squares.gd`、`test_statistics.gd`、`test_angles.gd`、`test_units.gd` |
| **向量** | 【构造】矩阵解方程：已知 x=(1,2,3) 构造 A(5×3)、b=Ax，Cholesky/消元双路径解回 x（残差<1e-12）；【权威·借用水准网】最小二乘路径与 §GK-M6 水准网向量交叉一致；【构造】统计 [1,2,3,4,5]：均值 3、样本方差 2.5、标准差 1.5811388；【构造】角度 30.5°=30°30′00″=0.532325422 rad=33.913345 gon、方位 315°=北西45°00′；【权威·定义精确】1 英亩=4046.8564224 m²、1 亩=2000/3 m²；面积例 152000 m²=228 亩=15.2 公顷=37.560018 英亩 |
| **要点** | GDScript float 为 64 位双精度；API 在 Wave 0 末冻结，Wave 1 只允许新增方法不改签名；禁用 `%g` 格式（本会话实测不支持）；不定类名冲突：class_name 统一 `GK` 前缀（GKMatrix 等） |

### GK-M2 椭球与大地线（A6/A11/A12/F2）

| | |
|---|---|
| **功能** | M2-1 `ellipsoid.gd` 椭球参数与派生量（a/f/e²/e'²/b、子午线弧长 X(B)、平行圈弧长）；M2-2 `blh_xyz.gd` **A6 BLH↔XYZ**（EPSG 9602 闭式正算 + Bowring ε 闭式反算）；M2-3 `geodesic.gd` **A11 大地线正反解**（Karney 算法，逐行移植底本 geographiclib-js，MIT）；M2-4 `rhumb.gd` **A12 恒向线**（精确 Mercator 参数法：Δψ=ln[tan(π/4+φ₂/2)/tan(π/4+φ₁/2)]）；M2-5 `geoid_egm2008.gd` **F2 高程异常查询**（PGM 5′ 读取 + 双线性/三次插值，头注释 Offset=-108.0 Scale=0.003 已实测） |
| **文件** | `core/ellipsoid/*.gd`；测试 `tests/ellipsoid/test_blh_xyz.gd`、`test_geodesic.gd`、`test_geodesic_sample.gd`、`test_rhumb.gd`、`test_geoid.gd`；数据 `tests/ellipsoid/data/GeodTest_sample.dat`（从 `_research/GeodTest.dat`（86,558,916 B，50 万行）截前 200 行入包，原件不入包） |
| **向量** | 【权威·EPSG GN7-2 §4.1.1】BLH→XYZ：53°48′33.820″N,2°07′46.380″E,h=73 → (3771793.968,140253.342,5124304.349) 逐位一致；反算恢复同点。CGCS2000 天安门 h=43.5 → (−2177748.227,4388723.160,4070142.752)（自编闭式与 pyproj 差<0.1mm）。【权威·GeodTest.dat 本会话复核 0.0mm】行 12346：P1(3.881802°,0°)→P2(54.681996°,10.214488°) azi1=7.571318148° azi2=13.113872140° s12=5707892.5152m；行 168（近对跖）：(71.606214176302°,0°)→(−80.240756381°,170.591260543°) azi1=169.717716111° azi2=19.402427357° s12=19009997.0304m；行 150001（短边 76m）：(19.707097385334°,0°)→(19.707739583°,0.000260256°) azi1=20.996796805° azi2=20.996884567° s12=76.1479m。验收容差：s12 相对 1e-9、方位 1e-8°、抽样 200 行回归。【构造】恒向线北京→上海：d=1074590.1m，az=154.7528°（R1=6371008.7714m）。【实测·双格网互检】EGM2008 高程异常（打包 5′ 格网 data/geoids/egm2008-5.pgm，GeographicLib 口径）：三次插值北京 −9.1030m、上海 +11.8126m、北海 GN7-2 点 +42.6472m；双线性 −9.0996/+11.8116/+42.6510m；独立 2.5′ tif（`_scripts/egm08_25.tif`）双线性参考 −9.1023/+11.8141/+42.6468m，与 5′ 三次互差≤1.5mm 已实测。注：早期分配的「5′ −9.082/+11.835/+42.680」三元组与打包格网任一插值口径互差 1.8~3.3cm、无法复现（疑为其他评估口径如球谐场直接求值），已废弃、勿作为可复现向量引用 |
| **要点** | geodesic 收敛失败（近对跖）返回中文错误并提示改用近似解；PGM 文件读取放 `app/data_service.gd`，core 只解析传入的 PackedByteArray |

### GK-M3 投影与分带（A3/A4/A5/A7/A13/A14/A15 + 分幅）

| | |
|---|---|
| **功能** | M3-1 `gauss_kruger.gd` **A3 高斯正反算**（Krüger 6 阶级数 + μ1 迭代反算，k0/FE/FN 可配，EPSG 9807 同族）；M3-2 `zones.gd` **A4 3°/6°换带**（反算→LL→正算新带）与 **A5 带号/中央子午线查询**（L0=6n−3 / L0=3n；y 前缀带号×10⁶+500km+自然 y）；M3-3 `utm.gd` **A7 UTM**（k0=0.9996，南半球 FN=10,000,000）；M3-4 `ups.gd` UPS（E,N，FE/FN=2,000,000）；M3-5 `mercator.gd` + `lambert.gd` **A14**（Web Mercator 3857 / 兰勃特等角圆锥 1SP/2SP）；M3-6 `mgrs.gd` **A13 MGRS**（100km 方格字母网格 + 精度截断）；M3-7 `kml_export.gd` **A15 KML 生成**（纯字符串 XML；KMZ 打包由 platform 用内置 ZIPPacker 完成）；M3-8 `sheet_gbt13989.gd` **I-地形图分幅编号**（GB/T 13989-2012：1:100万 6°×4° 行 A-V 列 21-72；比例尺代码 B~K；行/列三位序号自西北角起算） |
| **文件** | `core/projection/*.gd`；测试 `tests/projection/test_gauss.gd`、`test_zones.gd`、`test_utm_ups.gd`、`test_mercator_lambert.gd`、`test_mgrs.gd`、`test_kml.gd`、`test_sheet.gd` |
| **向量** | 【权威·EPSG GN7-2 9807 + pyproj 实测】CGCS2000 3°带 CM117°E：(30°,117°)→(x=3320113.3978,y=500000.0000)；(32.5°,118.25°)→(3597986.6234,617474.9201)；天安门→(4419435.7897,447950.5147)。带号前缀 EPSG:4527→y=39617474.9201；6°带 zone20 EPSG:4498→y=20617474.9201。反算：(3597986.6234,617474.9201)→(32.5°,118.25°)。北京54 EPSG:21460 天安门→(4419517.0313,447947.5867)；西安80 EPSG:2384→(4419440.9298,447948.4332)。验收容差：x/y ≤0.5mm（自编级数与 pyproj 差≤0.14mm 已实测）。【权威·DMA TM8358.2 Table 2-11 ID1】UTM zone38 International 椭球 73°N/45°E→E=500000.00,N=8100702.90。【权威·pyproj】UTM 19N (43.642556,−70.252228)→(399002.571,4832935.341)（全精度本会话复核）；UTM 56S 悉尼 (−33.8678,151.2073)→(334181.686,6251056.016)。【权威·pyproj EPSG:5041/5042】UPS 北 (85°,30°)→(2277728.6957,1518959.7883)；UPS 南 (−85°,30°)→(2277728.6957,2481040.2117)。【权威·mgrs 1.7.0（GeographicLib C 移植）】天安门→`50SMK4796917671`；北海点→`31UDV4268262666`（该点落在 1mm 方格舍入临界，输入须按 DMS 组装、勿用十进制截断字面量，详见 tests/projection/test_mgrs.gd 注）；`18SUJ2285070542`→(39.4662462°,−77.0592989°)。【权威·pyproj】Web Mercator 天安门→(12956617.544,4852513.528)；Lambert-93 巴黎 (2.35°,48.85°)→(652301.565,6861302.726)。【权威·GB/T 13989-2012】天安门 (39°54′27.1″N,116°23′28.6″E)：1:5万 `J50E001010`、1:10万 `J50D001005`、1:1万 `J50G003039`、1:50万 `J50B001001`、1:25万 `J50C001002`。【构造】KML 结构测试（Placemark/坐标串 `lon,lat,0` 格式与转义） |
| **要点** | 换带限界校验（距中央子午线>3.5° 提示改 6° 带）；crs_presets.json 的 EPSG 带号表直接采用调研 `cnDatumParams` 实测清单（CGCS2000 4491-4554 等） |

### GK-M4 坐标转换与高程拟合（A8/A9/A10/F7）

| | |
|---|---|
| **功能** | M4-1 `bursa.gd` **A9 七参数布尔莎**（Position Vector 1033 / Coordinate Frame 1032 双约定互为反号）+ 三参数；M4-2 `four_param.gd` **A8 平面四参数求参**（dx,dy,m,α 四元线性方程组 LS）与正反算；M4-3 `height_fit.gd` **A10 高程拟合**（平面 3 参/曲面 6 参/带状分段，经 M1 least_squares）；M4-4 `itrf.gd` **F7 ITRF 历元传播/14 参数**（半 Helmt：平移/旋转/尺度及其年速率） |
| **文件** | `core/transform/*.gd`；测试 `tests/transform/test_bursa.gd`、`test_four_param.gd`、`test_height_fit.gd`、`test_itrf.gd` |
| **向量** | 【权威·EPSG GN7-2 §4.2.3 WGS72→WGS84 官方算例】PV 约定：t=(0,0,+4.5m), rZ=+0.554″, dS=+0.219ppm，入 (3657660.66,255768.55,5201382.11) → 出 (3657660.78,255778.43,5201387.75)；CF 约定 rZ=−0.554″ 输出完全相同（本会话自编复现至 0.01m）。【构造·自洽】四参数恢复：公共点 (1000,1000),(3000,2000)，真值 dx=1000,dy=2000,m=1.0002,α=2° → 解出 (1000.0000,2000.0000,1.000200,2.000000°)；检核点 (2000,4000) 残差 0.000000。A10 构造：已知平面拟合系数生成格网点→加入已知噪声→恢复系数与残差。【落地补】F7：ITRF 官方参数表入 data/itrf_params.json 后，用"无速率参数时退化为普通七参数"做自洽检验 |
| **要点** | 双约定必须同测（反号互检）；求参时给出公共点残差表与粗差提示（残差>3σ） |

### GK-M5 坐标几何与交会（A1/A2/B1-B9）

| | |
|---|---|
| **功能** | M5-1 `cogo.gd` **A1 坐标正算**（极坐标法）/**A2 坐标反算** + 三维正反算（斜距/竖直角/仪器高/棱镜高）；M5-2 `intersections.gd` **B1 前方/侧方/后方交会**（后方含危险圆检测）与 **B2 方位-方位/方位-距离/距离-距离交会**（双解判别）；M5-3 `angle_tools.gd` **B5 角度格式/象限角换算**（调 M1 angles）；M5-4 `area_tools.gd` **B6 多边形面积**（鞋带公式）与亩/公顷/英亩换算；M5-5 `affine_tools.gd` **B7 点位平移/旋转/缩放**（枢轴，方位系顺时针正角约定）；M5-6 `line_tools.gd` **B8 点在线上/桩号偏距/垂足/点到线距**；M5-7 `circle_tools.gd` **B9 三点定圆** + 圆弧要素反算 |
| **文件** | `core/cogo/*.gd`；测试 `tests/cogo/test_cogo.gd`、`test_intersections.gd`、`test_area_tools.gd`、`test_affine.gd`、`test_line_tools.gd`、`test_circle_tools.gd` |
| **向量** | 全部【构造·本会话已自洽检核】A1/A2：(1000,1000),az=45°,d=500→(1353.553390593,1353.553390593)，反算回收 d=500.000000/az=45.000000。B1 方位交会：A(1000,1000) az1=30°，B(2000,1200) az2=309.3986°→P=(1400.0000,1692.8203)。B2 距离交会：A(1000,1000) dA=700、B(1800,1050) dB=600→双解 P₊(1512.6058,523.3079)/P₋(1449.2619,1536.8088)，检核 dA=700.0000/dB=600.0000。B9 三点定圆：(100,100),(500,150),(300,400)→圆心(292.0455,188.6364),R=211.5133（三半径一致）。B6 面积：四边形 (100,100),(500,120),(520,480),(120,500)→152000.0000 m²=228 亩=15.2 公顷=37.560018 英亩。B8：起点(1000,1000) az30° 线长 2000，点(2150,1950)→桩号 1397.7241、偏距 +520.9292（右正）。B7：枢轴(100,100) 旋转 30° 缩放 2，点(300,150)→(496.4102,−13.3975)（距离比 2.000000、方位偏移 30.0000°）。B5：30.5°=30°30′00″。声明：B 组无外部权威向量，验收=构造自洽+与 M3/M4 交叉（如交会点经反算回收、四参数恢复点回代） |
| **要点** | 距离交会必须给出双解与"指定侧"参数；后方交会危险圆（四点共圆邻域）返回中文警告；交会角<15° 提示精度弱 |

### GK-M6 控制测量与平差（C1-C12）

| | |
|---|---|
| **功能** | M6-1 `traverse.gd` **C1 支导线**、**C2 闭合导线平差**、**C3 附合导线平差**（角度闭合差反号均分→推方位→坐标增量按边长比例反号分配·Bowditch）、**C4 无定向导线**；M6-2 `network.gd` **C5 导线网/测边网/边角网严密平差**（间接平差，误差方程+法方程+精度评定）；M6-3 `leveling.gd` **C6 单一水准路线闭合差与高差改正**、**C7 水准网平差**（间接/条件双实现互检）、三角高程；M6-4 `tolerance.gd` **C8 限差检核与超限中文提示**（data/tolerance.json 驱动）；M6-5 `accuracy.gd` **C9 点位中误差/误差椭圆**（Qxx→φE/A²/B²）；M6-6 `reliability.gd` **C10 粗差探测与可靠性**（数据探测法学生化残差、多余观测分量）；M6-7 `gnss_net.gd` **C11 GNSS 向量网平差**（三维基线向量间接平差，输入由 app 先经 M2 转 XYZ）；M6-8 `variance_est.gd` **C12 方差分量估计（Helmert 法）与秩亏自由网平差**（最小范数解） |
| **文件** | `core/adjustment/*.gd`；测试 `tests/adjustment/test_traverse.gd`、`test_network.gd`、`test_leveling.gd`、`test_tolerance.gd`、`test_accuracy.gd`、`test_reliability.gd`、`test_gnss_net.gd`、`test_variance_est.gd` |
| **向量** | 【权威·教材公式，本会话 numpy 双法互检】C7 水准网：HA=100.000；h1=12.513(3.0km,A→P1)、h2=20.947(4.0km,A→P2)、h3=8.402(2.0km,P1→P2)，P=diag(1/3,1/4,1/2)→HP1=112.5237,HP2=120.9328；V=(+0.0107,−0.0142,+0.0071)m；μ=±10.7mm；条件法闭合差 w=−0.032m 与间接法结果逐位一致。【权威·教材规则，本会话复核】C3 附合导线：A(5000,5000)、α起=95.5°、β1=178.250556°(真+2″)、β2=236.249583°(真−1.5″)、边 950.004/1100.003/200.002、α终=150°→fβ=+0.50″、fx=+0.0074、fy=−0.0116、ΣD=2250.009、相对闭合 1/163506、平差后 P1=(5945.627,4908.951)、P2=(7043.271,4837.004)。【构造·判据明确】C5/C9/C10/C11/C12：在上述水准网/导线加装冗余观测推导 Qxx 与误差椭圆（判据：残差加权和=0、椭圆半轴非负、μ 收敛）；GNSS 网用已知基线+微噪声构造并恢复已知坐标差。【落地补】C8 限差表按规范核读后填 JSON，先以"用户自输限差"模式可用 |
| **要点** | 全部依赖 M1；近似平差 vs 严密平差在结果页标注区别（精度诚实原则）；超限提示必须含"限差值/实际值/依据等级"三要素 |

### GK-M7 路线、曲线与土方（B3/B4/D1-D7/E1-E6）

| | |
|---|---|
| **功能** | M7-1 `curve_elements.gd` **B3 圆曲线要素**（T/L/E/q/β0/m/p/主点里程）；M7-2 `spiral.gd` **B4 缓和曲线坐标**（回旋线级数 x0/y0 + 任意弧长坐标）；M7-3 `alignment_jd.gd` **D1 交点法中线正反算**；M7-4 `alignment_el.gd` **D2 线元法**（直线/完整缓和/圆曲线元拼接）；M7-5 `vertical_curve.gd` **D3 竖曲线高程**（对称抛物线 y=y_BVC+g1x+(g2−g1)x²/2L）；M7-6 `stakeout.gd` **D4 中边桩坐标与极坐标放样数据**；M7-7 `segment_link.gd` **D5 超高/加宽/断链**（断链里程双向换算）；M7-8 `interchange.gd` **D6 匝道复杂线型**（C型/S型/卵型/回头曲线=线元序列组合）；M7-9 `roadbed.gd` **D7 路基开挖口/坡脚放样**（横断面模板+坡率）；M7-10 `grid_volume.gd` **E1 方格网法土方**；M7-11 `section_volume.gd` **E2 断面法**；M7-12 `dtm_volume.gd` **E3 DTM 法**（TIN 三棱柱累加）；M7-13 `dist_slope.gd` **E4 平距/空间距离/坡度**；M7-14 `plumb.gd` **E5 垂直度**；M7-15 `profile.gd` **E6 纵断面内插/横断面数据** |
| **文件** | `core/route/*.gd`（M7-1~M7-9）、`core/earthwork/*.gd`（M7-10~M7-15）；测试 `tests/route/`、`tests/earthwork/` |
| **向量** | 【权威·教材通用公式，本会话两公式路径复算一致】B3/B4 曲线要素三组：(R=500,l0=60,α=30°)→β0=3.4377468°,m=29.9964,p=0.3000,T=164.0514,L=321.7994,E=17.9486,q=6.3034,x0=59.9784,y0=1.1997；(R=1000,l0=100,α=45°)→β0=2.8647890°,m=49.9958,p=0.4166,T=464.3820,L=885.3982,E=82.8432,q=43.3658,x0=99.9750,y0=1.6664；(R=600,l0=120,α=25°30′)→β0=5.7295780°,m=59.9800,p=0.9996,T=195.9723,L=387.0354,E=16.1935,q=4.9093,x0=119.8800,y0=3.9971。【构造·本会话】D3 竖曲线：g1=+3%、g2=−2%、L=400、PVI(1000,100)→BVC(800,94.000)、EVC 高程 96.000、中点 97.5000、E=−2.500、桩 900 高程 96.3750。【构造·本会话】E1：20×20 方格四角 (1.0,2.0,1.5,0.5)→V=500.0 m³。【构造·本会话】E4：Δh=30、平距 500→空间 500.8992、坡度 6.00%。【构造·判据明确】D1/D2/D4/D5/D6/D7/E2/E3/E5/E6：线元法用回旋线积分双路径互检（完整公式链 vs Fresnel 数值积分）；断链构造已知断链值往返换算闭合；DTM 用已知三棱柱精确体积；坡脚用解析断面（已知边坡线与地面线交点） |
| **要点** | 本模块体量最大；route/earthwork 两目录可由两人合署（文件互不重叠）；线元法是 D 组地基，先做并冻结 |

### GK-M8 天文时间与专题计算（F1/F3/F4/F5/F6 + I-GNSS/摄影/GIS/地质）

| | |
|---|---|
| **功能** | M8-1 `solar.gd` **F3 太阳方位角/高度角**（NOAA 算法移植，真北定向）；M8-2 `sun_events.gd` **F4 日出日落/时角/赤纬**（ha0=arccos[cos90.833°/(cosφcosδ)−tanφtanδ]，含折光 0.833° 综合）；M8-3 `magdecl.gd` **F5 磁偏角 WMM**（球谐系数模型，data/wmm.json，落地补）；M8-4 `time_sys.gd` **F6 时间系统**（UTC↔GPS 时（含周/周内秒/闰秒说明）↔儒略日↔年积日）；M8-5 `curvature_refraction.gd` **F1 地球曲率与大气折光**（c1·D²/R，c1=1−k，k≈0.13/0.14 可配）；M8-6 `gnss.gd` I-GNSS（广播星历开普勒方程→卫星 ECEF、时间、DOP）；M8-7 `photogrammetry.gd` I-摄影测量（共线方程、单像空间后方交会迭代 LS、前方交会、航高/GSD/重叠度、遥感指数 NDVI/EVI/SAVI/NDWI/MNDWI/NDBI/NBR/BAI/VARI/NDSI + 自定义表达式经 M1 expression）；M8-8 `gis_measure.gd` I-GIS（Haversine/缓冲区经纬范围估算/IDW 插值/球面面积）；M8-9 `geology.gd` I-地质矿山（产状换算/真视厚度/钻孔测斜三维/线储量估算） |
| **文件** | `core/astro/*.gd`（M8-1~M8-5）、`core/topics/*.gd`（M8-6~M8-9）；测试 `tests/astro/`、`tests/topics/` |
| **向量** | 【权威·NOAA 算法，本会话 pvlib 互差≤0.007°】F3 三例：(2024-03-20 12:00Z, 40.0°,−105.25°)→az=78.719°、zen=102.900°、δ=+0.14703°、EoT=−7.291min；(2024-06-21 06:00Z, 39.9075°,116.3913°)→az=240.788°、zen=27.358°、δ=+23.43811°、EoT=−1.871min；(2024-01-01 03:00Z, −33.8678°,151.2073°)→az=304.675°、zen=17.307°、δ=−23.04888°、EoT=−3.152min。【构造·本会话】F4 北京 2024-06-21：ha0=112.5345°、日出 UTC 20.7695h（前一日，即北京 04:46）、日落 UTC 11.7741h、昼长 15.0046h（判据：日出时刻太阳高度≈−0.833°）。【权威·常数】F6：JD(2000-01-01 12:00UT)=2451545.0；GPS 周起点 1980-01-06 00:00 UTC；2024-06-21 年积日 173。【构造·本会话】I-GIS：Haversine 北京→上海 1074470.9m（R1=6371008.7714m）。【构造·本会话】I-地质：走向 045°/倾角 30°→倾向 135°；剖面宽 100m ⊥ 走向→真厚度 50.0m。【构造·本会话】I-摄影：天顶像 f=100,H=100、物点 (±20,±15,0)→像点 (±20,∓15)、比例尺 1:100（构造成像自洽）。【构造·本会话】I-GNSS DOP：4 星对称单位视线 (±0.5,±0.3,0.8124)→PDOP=2.0388。【落地补】F5 WMM 系数与抽样比对（NOAA 计算器）；GNSS 星历算例（实测 RINEX 广播星历一条） |
| **要点** | 太阳算法源码已留档 `_scripts/azel.html`、`_scripts/solcalc.js`；NOAA 算法适用 1901-2099（电子表格版口径），页脚标注；遥感指数表达式引擎直接复用 M1-7 |

### 集成阶段（Wave 2，非并行施工模块——G 组 / H 组 / 导航接线 / 导出）

- **G1** CSV/DAT/TXT 批量点导入导出：`FileAccess.get_csv_line()`（内置）+ `platform/dat_parser.gd`（测量 DAT 自定义分隔自写）；导出同构。
- **G2** 批量坐标转换编排 `app/batch_convert.gd`：链式调 M3（投影）→M2（BLH/XYZ）→M4（参数转换），进度反馈与逐行错误报告。
- **G3** 报告导出：按 §5 协议渲染（`app/report.gd`），存 `user://reports/`，桌面端可另存。
- **G4** 点库：SQLite `points` 表 + CSV 导入导出 + 地图选取（M3 反算显示 LL）。
- **G5** 全局单位制：settings 驱动，`M1-5 units.gd` 供格式化。
- **G6** 历史/收藏：SQLite 表，历史条目存输入/结果 JSON 快照，支持"改参数重算"。
- **G7** 统计与误差传播计算器：M1-3/M1-6 + 专用计算器场景。
- **G8** DXF 展点图/网图导出：自写 ASCII DXF R12（POINT/LINE/TEXT/CIRCLE/POLYLINE），公开格式无依赖。
- **H** 公式库/百科页（`data/formulas.json` + 每模块 manifest `formula_ref`）；导线网略图/控制网图/曲线示意图用 `_draw()` 自绘（core 输出几何点列，UI 层画）。
- **导出验收**：Windows（x86_64，签名可选跳过）、Android（JDK17+SDK 35 组件清单按调研结论，AAB 走 Gradle 模板）、iOS（预设+工程准备；出包必须 Mac+Xcode）。

---

## 5. 解题步骤与报告导出的统一协议（core 输出契约）

每个 core 计算入口统一签名（沿用 `DEVELOPMENT_PLAN.md:108-118`，字段扩展为四元 steps）：

```gdscript
static func forward(p: Dictionary) -> Dictionary
# 返回：
{
  "ok": true,
  "value": { "x_m": 3597986.6234, "y_m": 617474.9201, "zone": 33 },   # 键名带单位后缀：_m/_km/_deg/_dms/_m2/_s/_mm
  "steps": [                                    # 教学特色：公式→代入→结果 三段式
    { "title": "1. 计算子午线弧长",
      "formula": "X = a·[m0·B − m2·sin2B + m4·sin4B − m6·sin6B]",
      "substitution": "X = 6378137×(0.9983…×0.567232 rad − 0.0025…×sin(1.134) + …)",
      "result": "3596879.2086 m" },
    { "title": "2. 计算纵坐标", "formula": "x = X + N/2·sinB·cosB·l² + …",
      "substitution": "…", "result": "3597986.6234 m" }
  ],
  "formula": "高斯-克吕格正算（EPSG 9807 / Krüger 6 阶，k0=1，FE=500km）",
  "error": ""                                   # ok=false 时必有中文可读原因
}
```

**规则：**

1. `ok=false` 时：`value` 为空字典，`error` 必填中文（如"坐标闭合差超限：1/2000 > 限差 1/10000（三级导线）"）；`steps` 可保留已算出的合法步骤；禁止把 GDScript 报错/堆栈文本放进 `error`。
2. `steps` 元素恰为 `{title, formula, substitution, result}` 四字段（String，允许空串）；UI 逐条渲染为四行卡片，空字段跳过渲染。
3. `value` 键名必须带单位后缀，UI 不再猜测单位；限差检核结果作为额外键（如 `f_beta_s`、`rel_closure`、`limit_s`、`ok_limit: false`）与 `steps` 同步输出。
4. 精度诚实：近似平差/严密平差、NOAA 太阳位置适用年份、EGM2008 插值误差量级，写入 `formula` 尾注或步骤 title，不隐瞒。
5. **G3 报告导出**（`app/report.gd`）：Markdown = `# <计算器名>` + 时间戳/版本 → 输入回显表 → 使用公式 → 步骤四列表格（title/formula/substitution/result）→ 结果表 → 限差检核（通过/超限+依据）→ 尾注"教学演示用途，不替代生产级平差/工程软件"。纯文本版同构去表格线。文件名 `<entry_id>_<yyyyMMdd_HHmmss>.md`。该协议使"每一步可追溯"（`DEVELOPMENT_PLAN.md:31`）在全部 69 项编号功能（A15+B9+C12+D7+E6+F7+G8+I5）的计算器上零成本落地。

---

## 6. 选用组件与集成方式

| 组件 | 决策 | 许可证（核对方式） | 集成方式 |
|---|---|---|---|
| **godot-sqlite v4.9**（2shady4u） | **采用**——历史/收藏/设置/点库持久化；本会话 `gh release download` addons.zip（72,102,324 B）并 `unzip -l` 核验 **Windows x86_64 DLL + Android arm64/x86_64 .so + iOS 设备与模拟器 xcframework 全部存在**，三端开箱即用 | MIT（调研实测 LICENSE.md 原文） | M0 拷 `addons/` 入工程；编辑器插件启用属共享文件改动由集成者完成；业务只经 `app/storage/sqlite_store.gd`（参数绑定），不直接触碰节点 |
| **JSON 存储（降级后端）** | **保留**——同一 `DataStore` 接口的第二实现；若某端 GDExtension 加载失败（如 iOS 沙盒异常）或将来放弃 SQLite，切换 `json_store.gd`（user://store/*.json），业务代码零改动 | 无依赖 | `app/storage/` 接口约定：`load_table/save_table/query` |
| **Noto Sans SC** | **采用**——随包自带（Android 厂商字体回退不可控，调研结论）。本会话经 `gh release download Sans2.004` 取得 `18_NotoSansSC.zip`（50,077,940 B，7 字重 + LICENSE），Regular 8,331,336 B / Bold 8,543,168 B；许可 **SIL OFL 1.1** 原文经 `gh api .../contents/Sans/LICENSE` 核验（可分发可商用可嵌入导出包） | OFL 1.1（in-repo LICENSE 原文） | M0：两枚 OTF 拷入 `themes/fonts/`，`main.tres` 设 Default Font（Bold 用 FontVariation 设字重或第二字体槽）；gui/theme/custom_font 兜底 |
| **geographiclib-js**（MIT） | 参考自写——A11 大地线算法移植底本；移植代码带来源注释（文件头注明 fork 自 GitHub geographiclib/geographiclib-js，MIT） | MIT | `core/ellipsoid/geodesic.gd` |
| **chrisveness/geodesy**（MIT） | 参考自写——UTM/BLH↔XYZ/Vincenty 阅读参考，不拷码 | MIT | 无直接依赖 |
| **PROJ / pyproj** | 参考校核——投影公式与 EPSG 参数权威对照（本会话 3.8.0 全部向量复核用它）；不引入运行时 | MIT 风格 | 仅 `_scripts/` 校验脚本使用 |
| **mgrs 1.7.0（PyPI，GeographicLib C 移植）** | 参考校核——A13 验收基准（本会话已装并用它生成向量） | MIT | 仅 `_scripts/` 校验使用 |
| **timothyqiu/godot-csv-data-importer** | **不采用**——它是编辑器期 CSV→Resource 导入插件；本项目静态数据是 JSON，运行时导入用内置 `FileAccess.get_csv_line()` 即可 | MIT | — |
| **godot-stat-math** | **不采用**——autoload 形态注册需改 project.godot（共享文件）且面向游戏非测量级；所需十几个统计函数由 M1-3 自写+自测 | Unlicense | — |
| **gdUnit4** | **不采用**——§7 的自研 runner 已满足统一入口/退出码/容差断言并实测；省一个编辑器插件与共享工程配置改动 | MIT | — |
| **geodot-plugin（GPL-3.0）** | **一票否决排除**——传染性许可证不得再分发（调研结论同口径） | GPL-3.0 | — |
| **GodotBigNumberClass / SmoothScroll / MrEliptik UI 集** | 不引入（无超大数需求；ScrollContainer 够用；UI 以官方 Theme+Container 自绘为准，MrEliptik 仅作样式参考） | — | — |

内置引擎能力（本会话 ClassDB 验证存在）：`ZIPPacker`（KMZ 打包）、`ZIPReader`、`FoldableContainer`（公式折叠面板）、`Expression`（科学计算器）、`FileAccess.get_csv_line()`、`DirAccess`（测试收集）。

**依赖体积预算**：Noto SC Regular+Bold ≈16.9MB + EGM2008 5′ PGM ≈18.7MB + SQLite 三平台二进制（Windows DLL 3.4MB / Android .so 2.2MB×2 / iOS 设备切片 2.1MB）≈ 基础包可控制在 55MB 量级（iOS 仅链接对应切片）。

---

## 7. 测试方案（已建成并 headless 实测）

### 7.1 统一入口（本会话已实现 + 两种退出码实测通过）

`tests/run_tests.gd`（extends SceneTree）：
1. 递归收集 `res://tests/**/test_*.gd`（点开头目录跳过，`run_tests.gd`/`test_case_base.gd` 自身排除）；
2. 逐脚本实例化，按声明顺序执行全部 `test_` 开头方法；
3. 软断言失败累计 `failures`；脚本加载/实例化失败计 `script_errors`；
4. 逐用例打印 `[PASS]/[FAIL]` + 中文失败明细，末尾 `passed/failed/script_errors` 汇总；
5. `quit(1 if (failed>0 or script_errors>0) else 0)`。

实测命令与本会话结果（Steam 二进制）：

```bash
"c:/atian/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
  --headless --path . --script res://tests/run_tests.gd
# 全过：stdout "总计: passed=2 failed=0 script_errors=0 / 退出码: 0"，进程 EXIT=0
# 注入 tests/_selfcheck/test_temp_fail.gd（故意断言失败）：
#   "[FAIL] … :: test_intentional_fail / - 故意失败以验证退出码 实际=1.001000000000 期望=1.000000000000 容差=0.000001"
#   进程 EXIT=1（经 `> log 2>&1; echo $?` 无管道掩码验证；验证后已删除该临时文件）
```

CI/本地约定：**退出码非 0 即失败**。管道取码用 `${PIPESTATUS[0]}`（本会话实证：管道后 `$?` 会取到 tail 的 0）。

### 7.2 断言基类（本会话已实现并实测）

`tests/test_case_base.gd`（extends RefCounted），测试脚本 `extends "res://tests/test_case_base.gd"`：
- `assert_almost_eq(actual, expected, tol=1e-6, msg)` —— **浮点容差断言**，显式拒绝 NaN/INF（is_finite 前置）；
- `assert_vector_almost_eq`（Vector2/Vector3/Array 逐分量）、`assert_eq/assert_ne/assert_true/assert_false/assert_between/assert_int_eq`；
- 软失败：单条断言不中断方法，消息累计；不用 push_error（避免污染退出码判断）；
- 本会话实测教训已固化进代码注释：GDScript `"%g"` 不被 format 支持（返回原串+variant 错误，改用 `%.12f`+`str()`）；三元运算符与 `%` 混用有优先级陷阱（断言消息一律显式 if/else）。

### 7.3 向量回归策略

1. **权威向量硬编码进测试**：§4 各模块向量表即测试值（本会话全部经 Python 复核，来源标注【权威】/【构造】）。
2. **GeodTest.dat 抽样回归**：M2 维护 `tests/ellipsoid/data/GeodTest_sample.dat`（前 200 行），大地线实现每次全量回归（容差 s12 相对 1e-9）。
3. **双法互检**：水准网间接/条件双实现、高斯级数 vs 反算回代、曲线要素两条公式路径——一致性本身就是测试。
4. **交叉校验留痕**：`_scripts/verify_vectors.py`（pyproj/geographiclib/numpy）与 `_scripts/gen_vectors_b.py` 保留为向量再生成与复核工具（Python 侧，不进导出包）。
5. **UI 不在单测范围**：headless 只测 core；UI 验收走三端手工清单（每端关键计算器 + 历史/导出，`DEVELOPMENT_PLAN.md:317` 原则保留、范围改为三端）。

### 7.4 施工域测试纪律

- 每域测试文件只放 `tests/<域>/`，互相不可见；runner 自动收集，新文件零注册。
- 施工者本地命令同 §7.1；合并前跑全量（失败>0 拒绝合入）。
- 【落地补】类向量（WMM/限差/ITRF/星历）测试先以 `SKIP-WMM-DATA` 等占位标记存在，数据到位后转正式断言——不静默跳过不存在的验收。

---

## 8. 三端导出要点（修订自 `DEVELOPMENT_PLAN.md` §8，裁至三端）

| 端 | 要点（沿用调研结论，来源 docs.godotengine.org 各导出页） |
|---|---|
| Windows | 模板安装（ICU Data 建议勾选）；x86_64；图标由项目 icon 转 ICO；纯离线分发签名可跳过；命令行 `--export-release "Windows Desktop" xxx.exe` |
| Android | OpenJDK 17 + SDK（platform-tools≥35.0.0、build-tools 35.0.1、platforms;android-35、cmdline-tools latest、cmake;3.10.2.4988404、ndk;28.1.13356709）；一键部署调试；发布 keystore `keytool -v -genkey -validity 10000`（密码字母数字、必须备份）；AAB 走 Gradle 模板；自适应图标前景/背景 ≥432×432、关键内容居中 264px 安全区圆 |
| iOS | **必须 macOS+Xcode**（官方原文）；Windows 侧完成：iOS 预设、App Store Team ID（10 位）与 Bundle Identifier（反 DNS）填写、导出 .xcodeproj；签名/真机/上架走 Xcode 常规流程；iOS 模拟器仅支持 Compatibility 渲染器（已按 §1.3 选型对齐） |

`export_presets.cfg` 由 M0 写入三端预设；`_research/_scripts/_vendor_check/docs` 目录进排除过滤器。

---

## 9. 施工纪律与风险

1. **共享文件变更仅走集成者**：唯一例外是 `data/` 新增 JSON（命名空间不冲突即可）；发现共享文件不足时提需求给集成者，不自行改。
2. **API 冻结**：GK-M1 的公开静态方法签名在 Wave 0 末冻结；后续只增不改（向后兼容）。
3. **core 禁止引擎 API**：评审重点检查 `extends RefCounted`、无 `Node`/`FileAccess`/`DirAccess` 引用。
4. **精度与误用风险**（`DEVELOPMENT_PLAN.md:344-345` 保留）：限差表未核读前 UI 显式标注"限差由用户输入"；近似/严密平差区分标注；NOAA 太阳算法标注适用年限。
5. **体量风险**：M7 最大，建议 Wave 1 内最先启动并冻结线元法；必要时集成者允许其拆分为两个施工账号（route/earthwork 两目录文件互不重叠，测试向量表已按此分配）。

---

*本文档由总架构师会话产出。所有"已实测"结论对应的命令与输出见 §0；未验证事项逐条声明于 §0"落地时需补"，不虚构验收结果。*
