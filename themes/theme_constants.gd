# themes/theme_constants.gd —— 布局常量的运行时唯一出处（与 build_theme.gd 生成口径一致）
#
# 为什么存在：build_theme.gd 是一次性 SceneTree 工具脚本（extends SceneTree，无 class_name，
# 不能被 preload），运行时代码无法直接引用它的常量。此处手工同步同一组值；
# build_theme.gd 顶部注释与其自校验共同保证两处不漂移。
# 全应用引用这些常量代替散落的字面量 96/16/48/22（施工包 P7 收敛项）。
class_name GKThemeConstants
extends RefCounted

## 触控目标最小高度（设计 px）：按钮/输入行/底部导航条目统一 96。
const TOUCH_TARGET := 96
## 指针设备（宽屏键鼠）触控目标高度（设计 px）：输入行/按钮收窄，仍满足
## WCAG 2.5.8 AA（24px）下限，为宽屏省出纵向空间。
const TOUCH_TARGET_POINTER := 56
## 相邻触控控件最小间距（设计 px）：按钮行、TabBar 条目间 ≥16。
const MIN_TOUCH_SPACING := 16
## 宽屏侧边栏标准宽（设计 px）：Logo + 标题 + 五类导航按钮（原 260 收窄）。
const SIDEBAR_WIDTH := 216
## 宽屏侧边栏折叠态宽（设计 px）：只留 Logo + 五类导航图标按钮。
const SIDEBAR_WIDTH_COLLAPSED := 72
## list-detail 左列表折叠态宽（设计 px）：只留展开按钮的细列。
const LIST_PANEL_WIDTH_COLLAPSED := 56
## 抽屉宽（设计 px）：窄屏导航抽屉滑入宽度。
const DRAWER_WIDTH := 320
## 结果卡主值字号（设计 px，type variation "ResultValue"）。
const FONT_RESULT := 48
## 次级说明字号（设计 px，type variation "Caption"）。
const FONT_CAPTION := 22
