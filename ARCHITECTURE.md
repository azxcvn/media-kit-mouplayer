# 小牛Player（moumou）项目架构指南

> 本文件是项目的**唯一架构契约**。任何 AI / 开发者在本仓库添加新功能前，必须先读完本文件。
> 遵循本文件的约定，项目可以健康扩展到 PiliPlus / mpvRx 同量级规模；违反约定堆代码，项目会退化为屎山。
> **完成重大功能新增 / 优化或 Bug 修复后，必须同步更新本文档（至少 §2 目录结构），禁止文档与代码脱节。**

---

## 1. 项目简介

Flutter 本地视频播放器（Android），核心能力：
- 扫描本地视频（MediaStore + 「允许管理所有文件」权限）
- **列表模式**：含直接视频的文件夹 → 文件夹详情页（纯视频列表）
- **树状模式**：逐级目录导航（mpvRx 风格），一级界面显示独立文件夹卡片，点入下钻，带面包屑
- 两种模式共用同一套卡片组件（视觉一致）
- 播放器：media_kit，横屏沉浸式全屏，播放进度持久化
- 超分辨率：Anime4K v4 着色器链（7 档模式：关闭 + A/B/C/A+/B+/C+，× 质量档 流畅/均衡/高清），底栏固定入口
- 外观设置：23 种主题色 + 21 种调色板风格（flex_seed_scheme）

技术栈：Flutter 3.44+ / Dart 3.12+，依赖见 `pubspec.yaml`。

---

## 2. 目录结构（lib/）

```
lib/
├── main.dart                  # 入口：主题装配 + AppFrame + 路由观察者
├── models/                    # 纯数据模型（无逻辑、无依赖）
│   ├── tree_node.dart         #   目录树节点（folder/video）
│   ├── video_file.dart        #   视频文件信息
│   ├── player_action.dart     #   播放器按钮动作（含占位入口）/ 双击手势模式枚举（倍速不在顶栏动作之列）
│   └── super_resolution_mode.dart  # 超分模型：模式枚举（关闭+A/B/C/A+/B+/C+）+ 质量枚举（流畅/均衡/高清）+ buildAnime4KChain 纯函数
├── services/                  # 业务逻辑 / 数据层（无 UI）
│   ├── view_settings.dart     #   排序/字段/视图模式设置（ChangeNotifier + 持久化）
│   ├── video_scanner.dart     #   扫描 + 建树 + 建文件夹列表
│   ├── video_info_service.dart#   缩略图生成（跨进程，磁盘缓存）
│   ├── playback_progress_service.dart  # 播放进度（ChangeNotifier + 持久化）
│   ├── player_controls_settings.dart   # 播放器控制设置（右上角槽位/手势/时长/倍速预设/按钮背景/进度条样式/长按倍速/音量亮度灵敏度/保存音量到系统/双指缩放/进度条缩略图开关，单例 + 持久化）
│   ├── device_services.dart   #   设备能力：系统音量 / 窗口亮度 / 任意时刻抓帧（video_thumbnail_plus 包优先 + MethodChannel 兜底 + 磁盘缓存 + 最近帧内存查询，原生见 MainActivity.kt）
│   ├── thumbnail_preload_service.dart # 缩略图预生成：进入播放后按自适应间隔从当前位置向外预热整段缩略图（页面局部实例，切集/退出 cancel）
│   ├── cache_manager_service.dart # 缓存管理：各类别缓存大小查询 / 逐类清除 / 一键清除（原生 getCacheSizes/clearCache/clearAllCaches）
│   ├── super_resolution_service.dart   # 超分：模式+质量持久化、着色器 assets→目录拷贝、mpv glsl-shaders 应用与生效查询
│   └── ...                    #   ⚠️ 不要在这里加全局 ValueNotifier hack（见 §4.1）
├── widgets/                   # 可复用 UI 组件（跨页面）
│   ├── app_frame.dart         #   ★ 全局框架：安全区 + 播放页全屏检测
│   ├── app_dialog.dart        #   showAppDialog（统一弹窗动画）
│   ├── player_panel.dart      #   ★ 右侧滑入面板壳 + showPlayerPanel 公用入口（倍速/超分/更多/编辑控制栏共用）
│   ├── player_option_chip.dart#   面板选项胶囊（倍速预设/超分模式共用，保证视觉一致）
│   ├── options_sheet.dart     #   showSortOptionsSheet（统一排序弹窗）
│   ├── folder_card.dart       #   文件夹卡片（列表/树状共用）
│   ├── video_card.dart        #   视频卡片（列表/树状/详情共用）
│   ├── settings_ui.dart       #   设置页公共组件（分组/卡片/设置项/Kazumi 滑杆主题）
│   ├── capsule_nav_bar.dart   #   悬浮胶囊导航
│   ├── main_scaffold.dart     #   主壳（PageView + 悬浮胶囊）
│   └── marquee_text.dart      #   无缝循环跑马灯
├── pages/                     # 页面（每页一个目录）
│   ├── home/
│   │   ├── home_page.dart     #   首页（权限门禁 + 视图分发）
│   │   ├── views/             #   首页专属视图组件
│   │   │   ├── folder_list_view.dart  # 列表视图
│   │   │   └── tree_list_view.dart    # 树状一级视图
│   │   ├── folder_detail_page.dart    # 列表模式详情页（纯视频）
│   │   └── tree_folder_page.dart      # 树状目录页（混合内容 + 面包屑）
│   ├── player/
│   │   ├── player_page.dart   #   播放页（横屏沉浸式；控制层 Kazumi 风格滑入动画；锁定后左右解锁按钮；截图；全套手势）
│   │   └── views/             #   播放页专属控制组件
│   │       ├── player_top_bar.dart        # 顶栏：返回 + 标题 + 5 槽位（空槽隐藏）+ 固定「更多」（图标背景可开关）
│   │       ├── player_center_cluster.dart # 中央簇：快退/播放暂停/快进（双三角图标）
│   │       ├── player_bottom_bar.dart     # 底栏：下一集 + 时间 + 固定「倍速」（图标）+「超分辨率」
│   │       ├── player_seek_bar.dart       # 全宽进度条（默认细线，跟随主题色）
│   │       ├── player_right_actions.dart  # 右侧竖排：截图 + 锁定（固定灰黑圆角背景，不受按钮背景设置控制）
│   │       ├── player_fit_panel.dart      # 画面比例面板（PiliPlus 同款选项：拉伸/自动/裁剪/等宽/等高/原始/限制/4:3/16:9）
│   │       ├── player_speed_panel.dart    # 倍速面板内容（预设置顶/精确调速/临时应用开关）
│   │       ├── player_super_resolution_panel.dart  # 超分面板内容（模式三行胶囊 + 超分质量一行胶囊 + 记忆开关）
│   │       ├── player_play_pause_button.dart  # 播放/暂停图标形变动画（PiliPlus AnimatedIcon 风格）
│   │       ├── player_gesture_layer.dart      # ★ 手势层：单击/双击/长按+左右滑动调速/单指滑动（音量·亮度·进度）/双指缩放平移（裸识别器方案，见 §4.8）
│   │       ├── player_gesture_indicator.dart  # 音量/亮度手势指示器（左侧区域，kazumi 风格垂直胶囊 + 图标 Crossfade + 缓动填充）
│   │       ├── player_speed_indicator.dart    # 长按倍速指示器（顶部：速度胶囊 + 首次提示 + 动态倍速条，倍速条 3 秒自动隐藏）
│   │       ├── player_swipe_seek_overlay.dart # 水平滑动 seek 预览浮层（目标时间 + 偏移量）
│   │       └── player_thumbnail_preview.dart  # 进度条拖动缩略图预览气泡（本地视频任意时刻抓帧，16:9 + 时间胶囊）
│   └── settings/
│       ├── settings_page.dart #   设置主页（分组结构，可扩展；「其他」组 → 关于）
│       ├── appearance_page.dart      # 外观设置子页
│       ├── player_settings_page.dart # 播放器设置子页（手势/时长原地编辑/进度线/倍速记忆/按钮背景/长按倍速/灵敏度/保存音量/双指缩放/进度条缩略图；超分在播放界面调）
│       ├── about_page.dart           # 关于页（应用信息 + 「工具」组，工具后续扩展）
│       └── cache_management_page.dart# 缓存管理页（各类缓存大小/逐类清除/一键清除二次确认/刷新）
├── theme/                     # 主题
│   ├── app_theme.dart         #   ThemeData 生成（light/dark/amoled）
│   └── theme_controller.dart  #   主题控制（模式/色/风格 + 旧数据迁移）
└── utils/                     # 纯工具函数
    ├── app_dialog.dart        #   （见 widgets/app_dialog.dart 说明）
    ├── formatters.dart        #   文件大小/日期/时长/倍速格式化
    ├── natural_compare.dart   #   自然序（数字感知）比较：名称排序用
    └── player_gestures.dart   #   双击手势判定 + 滑动手势数学（seek 灵敏度/音量·亮度增量/动态倍速档位，纯函数，可单测）
```

---

## 3. 分层职责（依赖方向：只允许上层依赖下层，禁止反向）

```
pages（页面）      → 组装 widgets / 调用 services
widgets（组件）    → 只依赖 models / services / theme / utils（不依赖 pages）
services（服务）   → 只依赖 models / utils（不依赖 UI）
models（模型）     → 无依赖（纯数据）
```

**规则**：
- `widgets/` 里的公共组件**禁止 import `pages/`**（否则页面组件耦合）
- 页面专属的小组件放 `pages/<页面>/` 下（如 `views/`），不要塞进 `widgets/`
- 单文件超过 ~400 行必须拆分（参考首页拆分出的 `views/`）

---

## 4. 关键架构决策（新增代码前必读）

### 4.1 状态管理

- **约定**：`ChangeNotifier` + `ListenableBuilder`（或 `Listenable.merge`），需要持久化的用 `shared_preferences`
- 现有控制器：`ViewSettings`（排序/字段/视图模式）、`ThemeController`（外观）、`PlaybackProgressService`（单例，进度）、`SuperResolutionService`（单例，超分模式+质量+记忆开关）；控制按钮背景（底栏倍速图标/顶栏控制图标，默认关闭）、倍速记忆（默认关闭）、画面比例（默认自动）、**长按倍速（倍率 1–6 步进 0.1/指示器开关/首次提示标记）、音量亮度手势灵敏度（默认 1.0）、保存音量到系统（默认开启）、双指缩小视频（默认开启）、进度条缩略图（默认开启）** 属 `PlayerControlsSettings`
- 播放页音量/亮度属于**页面局部状态**（进入时从系统同步，退出时按设置写回/恢复，见 §4.8），禁止做成全局服务
- 超分记忆语义（`SuperResolutionService`，默认关闭）：无论开关状态都记录「最近一次设置的 模式/质量」；开启记忆后 `load()`/`enterPlayer()` 自动恢复该组合应用到所有视频；**未开启记忆时 `enterPlayer()`（播放页 initState）把本次会话重置为关闭/均衡**——退出播放或重启后都回到默认关闭（参考 mpv-android-anime4k）
- **禁止**：新增全局 `ValueNotifier` hack / 全局可变单例来跨页面通信
  - 反例教训：曾经的 `fullscreen_state.dart` 全局 `playerActive`，靠页面手动置位影响全局布局，引发连锁补丁 → 已重构为 `AppFrameObserver`（§4.3）
- 跨页面状态先想清楚归属：全局设置 → services 里的 ChangeNotifier；页面局部 → 页面 State；路由相关 → 路由机制

### 4.2 安全区（三大金刚键 / 挖孔）—— 全局已处理，页面零负担

`lib/widgets/app_frame.dart` 的 `AppFrame` 包裹整个 Navigator（挂在 `main.dart` 的 `MaterialApp.builder`）：

- **普通页面**：底部自动避让系统导航键（`bottom: true`），背景 = 主题色
- **播放页**：自动全屏（`bottom: false`），背景 = 黑色
- `left/right` **恒为 false**：横屏时挖孔在物理左/右侧，若消费会导致整个界面被挖孔挤到一侧（历史白条 bug 的根因，勿改）

**新增页面的约定**：
- 普通列表页：`Scaffold(appBar: ..., body: ListView(...))`，**什么都不用做**
- 底部有悬浮胶囊的主 tab 页：列表底部留 `88` padding（如首页/设置页）

### 4.3 播放页全屏检测 —— 路由驱动，禁止手动标志

`AppFrameObserver`（`app_frame.dart`，全局单例，挂在 `MaterialApp.navigatorObservers`）自动监听栈顶路由：

- **push 播放页时必须在 `MaterialPageRoute` 上带** `settings: const RouteSettings(name: playerRouteName)`（`playerRouteName` 常量在 `app_frame.dart`）
- 播放页内部**不要**手动设置任何全局状态
- 现有三处 push 已遵循（home_page / folder_detail_page / tree_folder_page 的 `_openVideo`/`_openPlayer`）

### 4.4 播放页全屏（系统栏）

`player_page.dart` 的 `_enterFullscreen()`：`immersiveSticky` + 透明系统栏（`_exitPlayer` / `dispose` 恢复竖屏 + edgeToEdge）。退出统一走 `PopScope` 拦截 + `_exitPlayer()`（保存进度 → 恢复竖屏 → pop），系统返回键与返回按钮行为一致。

### 4.5 弹窗 / 面板

- **所有弹窗统一用** `showAppDialog`（`lib/utils/app_dialog.dart`，缩放 + 淡入动画），**不要**直接 `showDialog`
- **播放器内右侧滑入面板统一用** `showPlayerPanel`（`lib/widgets/player_panel.dart`，滑入 + 淡入 + 面板内页面栈）。倍速 / 超分 / 画面比例 / 更多 / 编辑控制栏共用；面板内二级页面用 `PlayerPanelNavigator.of(context).push(...)` 就地切换，禁止叠加第二个面板。**新增类似右侧面板需求时直接复用，勿另写一套**。注意：`of` 必须用面板树内的 context（内容里先包一层 `Builder` 再取），不能用页面 State 的 context
- **播放界面二级界面硬性约定**：播放器内凡需弹出二级界面（倍速、超分、画面比例、字幕/音轨等后续功能）的，**一律使用 `showPlayerPanel` 右侧滑入外壳**（同款外壳必须保证）；面板内容可选用 `PlayerOptionChip` 胶囊选择（视功能而定），也可用列表等其他形式，但**不得另写一套弹窗/面板外壳**
- **排序/字段弹窗统一用** `showSortOptionsSheet(context, viewSettings, hasFolders:, hasVideos:, showViewMode:)`（`lib/widgets/options_sheet.dart`）
  - `hasFolders` / `hasVideos` 按页面内容动态传（纯文件夹页、纯视频页、混合页自动区分区块）
  - `showViewMode` 仅首页传 true
- 弹窗类命名为 `_XxxSheet`，放页面文件内或公共 `widgets/`（跨页共用时）

### 4.6 卡片复用（树状/列表视觉一致的根基）

- 文件夹 → `FolderCard`（`widgets/folder_card.dart`），参数：`node / fields / onTap`
- 视频 → `VideoCard`（`widgets/video_card.dart`），参数：`video / fields / onTap`
- **任何新视图/新页面显示文件夹或视频时，必须复用这两个卡片**，禁止另写一套样式
- 字段由 `ViewSettings.fields`（FolderField）和 `viewSettings.videoFields`（VideoField）驱动

### 4.7 主题

- 主题色/风格都在 `theme_controller.dart`（`presetColors` 23 色、`variantLabels` 21 风格）
- 新增主题色：往 `presetColors` 加 `(color: ..., label: 'XXX色')`（3 字命名，色相排列）
- 调色板风格来自 flex_seed_scheme 的 `FlexSchemeVariant`（21 种已全量），**勿**改枚举顺序（持久化 index）
- `app_theme.dart` 统一 `appBarTheme`（`scrolledUnderElevation: 0` + 固定背景色，防止 AppBar 滚动变色）

### 4.8 播放页手势（新增功能前必读）

播放页手势统一由 `PlayerGestureLayer`（`pages/player/views/`）承载，**不要**在播放页再叠加
`GestureDetector` 手势（多识别器竞技场竞争会导致方向判定漂移，历史教训）。方案对齐
PiliPlus：裸 `RawGestureDetector` + 自定义识别器组 + `Listener` 兜底。

| 手势 | 行为 | 说明 |
|---|---|---|
| 单击 | 显隐控制层（锁定态切换解锁按钮） | Tap + DoubleTap 并存，单击有 ~300ms 双击判定延迟（与旧实现一致） |
| 双击 | 按 `doubleTapMode`：暂停 / 左退右进 / 混合 | 同旧逻辑 |
| 长按（500ms） | 临时倍速（设置值 1–6x），指示器常驻 | 长按期间 `Listener` 裸指针事件驱动左右滑动调速 |
| 长按 + 左右滑动 | 动态调速 1.5–4x（间隔 0.5，离散），出现倍速条 | 倍速条在指示器下方，停在某档 3 秒自动隐藏；首次完成该操作后提示不再出现（`speedHintShown` 持久化） |
| 单指垂直滑动 | 左半屏亮度、右半屏音量 | 顶部/底部 8% 死区（避系统手势）；音量 0–100、亮度 0–1，带浮点累加器；**方向确认延迟 80ms**（给第二根手指加入时间，防捏合误触滑动） |
| 单指水平滑动 | 实时 seek（满屏 = 90 秒，40ms 节流），居中浮层显示目标时间 | 右侧 8% 死区（避系统返回手势）；若滑动中途加入第二指，先撤销 seek（`onSwipeCancel`）再进缩放 |
| 双指 | 缩放（0.75–2x，设置可禁缩小）+ 平移 | 以双指焦点为锚缩放 + 焦点位移平移；缩放后「还原画面」胶囊出现在播放/暂停按钮下方 |

音量/亮度与系统交互约定（原生在 `MainActivity.kt`，走 `DeviceServices`）：
- 进入播放：读系统音量作为播放音量起点（如 20%）；亮度读系统值并**应用到窗口**
  （kt/mpvEx 做法：屏幕显示与指示器一致，播放期间亮度不随自动亮度漂移），**不改系统设置**；
- 播放中：音量只调 mpv 音量（`player.setVolume` 0–100），亮度只调窗口亮度（`WindowManager` 属性，无需权限）；
- 退出播放：**亮度恢复 -1（交还系统控制 = 进入前状态）**；音量按设置「保存音量到系统」（默认开）→ 写回系统，关闭 → 恢复进入前系统音量。`dispose` 兜底恢复，防异常路径泄漏；
- 音量指示器在**屏幕左侧**、亮度指示器在**屏幕右侧**（对称）；kazumi 风格进出场
  （从屏幕边缘滑入滑出 + 淡入淡出 + 轻微缩放），2 秒无操作自动隐藏。

---

## 5. 新增功能指南（按功能类型）

### 5.1 新增一个页面

1. 建目录 `lib/pages/<name>/`，页面文件 `xxx_page.dart`（StatefulWidget）
2. 页面用 `Scaffold` + `AppBar`，body 用 `ListView`（安全区自动处理，不用管）
3. 需要排序弹窗 → `showSortOptionsSheet`；需要弹窗 → `showAppDialog`
4. 跳转：`Navigator.push(MaterialPageRoute(builder: ...))`
   - 如果是播放页：加 `settings: const RouteSettings(name: playerRouteName)`
   - 播放页可传 `playlist:`（当前可见的排序视频列表），用于「下一集」；不传则按钮置灰
5. 页面专属小组件放 `lib/pages/<name>/views/`，跨页复用的放 `lib/widgets/`
6. 底部有悬浮胶囊（主 tab 页）：ListView 底部 padding `88`

### 5.2 新增数据/业务服务

1. 放 `lib/services/<name>.dart`
2. 需要 UI 响应：`class XxxService extends ChangeNotifier`，页面用 `ListenableBuilder(listenable: Listenable.merge([...]))`
3. 需要持久化：`shared_preferences`，load 在启动时调用（参考 `main.dart` 的 initState）
4. 纯工具函数：放 `lib/utils/`（无状态、无 Flutter 依赖更佳）

### 5.3 新增设置项

1. 设置主页 `settings_page.dart` 已有分组结构：`SettingsGroupTitle(title: '分组名')` + `SettingsCard(child: SettingsTile(...))`
2. 新分组直接追加；新设置子页参考 `appearance_page.dart`（`AppBar` + 分组列表）
3. 设置项 UI 组件复用 `lib/widgets/settings_ui.dart`（`SettingsGroupTitle / SettingsCard / SettingsTile / SettingsRadioTile`）

### 5.4 新增模型字段

- 改 `lib/models/` 下对应模型（纯数据），注意 `TreeNode` 是不可变类，重建时传完整参数

### 5.5 新增测试（必须有）

每个新逻辑都要配测试（见 §6），文件放 `test/`，命名 `<被测文件>_test.dart`。

### 5.6 文档维护（必须）

完成**重大功能新增 / 优化或 Bug 修复**后，必须在本文件（ARCHITECTURE.md）同步以下内容，再算收工：

1. **§2 目录结构**：新增/删除/移动的文件、目录必须反映到树形图（含一行注释说明职责）；
2. **受影响章节**：改到状态管理 → §4.1；新增弹窗 → §4.5；改播放页 → §5.1 / §4.3/4.4；新增设置 → §5.3；新增测试 → §6；
3. **§7 已知注意事项**：新踩的坑（环境 / 框架 / 设备）要补进表格，防止他人重蹈覆辙。

> 判断标准：改完代码后，**文档中任何与代码不一致的路径、文件名、组件名都算违约**。小改动（如改文案、调样式）不强制，但涉及结构 / 接口 / 行为变化必须更新。

---

## 6. 测试约定

- 框架：`flutter_test`；权限 mock 用 `permission_handler_platform_interface` 的 `PermissionHandlerPlatform.instance` 替换（参考 `test/home_page_permission_test.dart`）
- 现有测试（`flutter test` 全绿）：
  - `test/widget_test.dart` — 胶囊导航渲染（**注意**：胶囊设计上所有标签都显示，勿改成 findsNothing）
  - `test/view_settings_test.dart` — sortTree / sortFolders / sortVideos 排序逻辑（含名称自然序：2 < 12 < 112）
  - `test/natural_compare_test.dart` — 自然序比较纯函数（数字段/字母段/前缀）
  - `test/super_resolution_mode_test.dart` — 超分模型（7 模式 + 质量枚举 + buildAnime4KChain 链构建纯函数 + 着色器文件完整性）
  - `test/super_resolution_service_test.dart` — 超分服务状态/持久化（模式、质量、记忆开关的开启/关闭/load 恢复）
  - `test/app_frame_test.dart` — AppFrame 安全区行为 + 播放页路由检测（**安全区/播放页回归测试，改 AppFrame 必须跑**）
  - `test/home_page_permission_test.dart` — 权限流程（未授权 → 授予权限 → 授权扫描）
  - `test/player_controls_settings_test.dart` — 播放器控制设置（槽位增删/排序/上限/时长档位/倍速预设/按钮背景/进度条样式/旧数据迁移；倍速不在顶栏动作之列）
  - `test/player_gestures_test.dart` — 双击手势三模式判定（含边界）+ 滑动手势数学（seek 灵敏度/音量·亮度增量/动态倍速档位与索引/最近档位）
  - `test/player_panel_test.dart` — 右侧面板打开/面板内导航不崩溃（**改 PlayerPanel 必须跑**）
  - `test/player_speed_panel_test.dart` — 倍速面板（「我的预设」✕ 删除 / 「添加到预设」随滑杆联动）
  - `test/player_controls_settings_test.dart` — 播放器控制设置（槽位/时长/倍速预设/按钮背景/进度条样式/长按倍速/灵敏度/保存音量到系统/指示器开关/首次提示/双指缩放/旧数据迁移）
  - `test/thumbnail_cache_test.dart` — 缩略图预生成间隔（intervalFor）+ 设备帧缓存查询（peekFrame/peekNearestFrame）+ 预生成服务状态流转
- 改以下代码必须跑对应测试：`AppFrame`、`ViewSettings` 排序、权限流程、`CapsuleNavBar`

---

## 7. 已知注意事项（踩过的坑）

| 坑 | 说明 | 防护 |
|---|---|---|
| 挖孔屏横屏白条 | 全局 SafeArea 消费 left/right inset → 界面被挖孔挤到一侧 + 露浅色背景 | AppFrame `left/right` 恒 false + 播放页豁免 bottom（§4.2） |
| AppBar 滚动变色 | M3 默认 scrolledUnderElevation 变背景色 | `app_theme.dart` 统一 `scrolledUnderElevation: 0` + 固定 backgroundColor |
| 三大金刚键遮挡 | 页面内容被系统导航键盖住 | AppFrame 全局 bottom 安全区（§4.2） |
| 系统栏区域黑色/白色 | SafeArea padding 区域在 Navigator 外露窗口背景 | AppFrame 用 ColoredBox 铺主题色/黑色 |
| 播放页退出横屏闪烁 | 系统返回键直接 pop，未先恢复竖屏 | PopScope 统一走 `_exitPlayer`（§4.4） |
| 弹窗三份重复 | 排序弹窗曾复制 3 份 | 统一 `showSortOptionsSheet`（§4.5） |
| 全局状态 hack | 全局 ValueNotifier 跨页面通信引发连锁补丁 | 禁止，用 ChangeNotifier / 路由机制（§4.1/4.3） |
| 面板红底黄字崩溃 | 右侧面板用普通 Container 包裹，内容里的 ListTile/SwitchListTile/TextField 找不到 Material 祖先 → "No Material widget found" | PlayerPanel 外壳必须用 `Material`（含圆角/裁剪），勿换回 Container（§4.5） |
| 编辑控制栏点击无反应 | 面板内容里调 `PlayerPanelNavigator.of(context)` 时用了 State 外层 context（不在 _PanelNavigatorScope 下）→ 断言 scope == null | 面板内容必须用 `Builder` 取面板树内的 context 再调用 `of`（§4.5） |
| Flutter 工具链"卡死" | DSH 沙箱拦截 flutter/dart 启动分析器、测试等子进程（`CreateFile failed 5` 拒绝访问），表现为进程冻结、长时间无输出 | 运行 `flutter analyze` / `flutter test` 需以 **danger-full-access** 权限执行；升级后 2-3 秒出结果。**勿用 `flutter --version` 探路**（同样会被卡住）；先用 `dart analyze` 也无效（同样被拒），直接以完整权限跑 `flutter analyze` |
| mpv 着色器要绝对路径 | libmpv 的 `glsl-shaders` 不接受 assets 虚拟路径，必须给文件系统绝对路径 | `SuperResolutionService` 启动后把 `assets/shaders/*.glsl` 拷贝到应用支持目录（`anime_shaders/`），拼接绝对路径（Windows 用 `;`、其余平台用 `:`）再下发（§5.2） |
| 切集/重开媒体着色器失效 | mpv 打开新文件时 `glsl-shaders` 链需重新确认，否则回到默认渲染 | `player_page` 在 `open()` 后与「下一集」后都调用 `SuperResolutionService.apply(player)` |
| 超分模式切换后 UI 不刷新 | 面板是独立弹窗路由，播放页 setState 不会重建面板（同倍速历史 bug） | 超分面板通过 `ValueNotifier<SuperResolutionMode>` 实时刷新（`player_page` 的 `_superResolutionNotifier`） |
| 超分"看不出效果" | 着色器只对「视频分辨率 < 屏幕分辨率」的场景有可见提升；1080p 视频在 1080p 屏上几乎无放大空间；且 Anime4K 面向动漫 | 用 720p 以下动漫测试；激进档位选 A+/B+/C+ 双段链 + 设置内「高清」质量 |
| debug 版动画掉帧 | Flutter debug 构建为 JIT + 断言，控制层滑入动画（尤其启用超分、GPU 负载高时）易掉帧；release AOT 无此问题 | 用 `flutter build apk --release` 验证动画；非功能缺陷（参考 KT 开发经验：debug 掉帧、release 正常） |
| 截图保存 | mpv `screenshot` 需渲染器就绪；保存到系统相册依赖平台插件 | 用 media_kit `Player.screenshot(format: 'image/png')` + `saver_gallery` 保存；失败时 Toast 提示 |
| 右侧截图/锁定按钮背景 | 固定灰黑圆角背景，**不受**「按钮背景」设置控制（该设置只作用于顶栏/底栏图标） | 样式写死在 `player_right_actions.dart`，勿套用 `showButtonBackground` |
| 锁定交互 | 锁定后控制层隐藏，**左右两侧滑入解锁按钮**；单击屏幕呼出/隐藏（动画）；点击解锁按钮解锁 | 解锁按钮显隐由 `_unlockController`（player_page）驱动，勿改回中央提示 |
| 画面比例 | 用 media_kit Video 的 `fit` + `aspectRatio`（Flutter 渲染层），无需 mpv 属性；4:3/16:9 固定比例时 boxFit 取 contain | `PlayerVideoFit`（models/player_action.dart）持久化于 `PlayerControlsSettings`，顶栏「比例」槽位弹出面板 |
| 窗口亮度泄漏到列表页 | 窗口亮度是 Activity 级属性，播放页不恢复的话，退出后列表页会保持播放时亮度 | `_exitPlayer` + `dispose` 双重恢复（`DeviceServices.setWindowBrightness(null)` → 原生 -1 交还系统控制），原生侧 < 0 表示恢复系统默认（§4.8） |
| 播放页手势方向漂移 | 用 GestureDetector 叠加 onVerticalDrag/onHorizontalDrag/onScale，识别器竞技场竞争导致方向判定漂移 | 统一用 `PlayerGestureLayer` 裸识别器方案：单指方向滑动全部走 ScaleGestureRecognizer 分类，长按走 LongPress + Listener 裸指针（§4.8） |
| 全面屏系统手势误触 | 屏幕边缘滑动会触发系统下拉/返回手势 | 手势层设死区：垂直手势排除顶部/底部 8%，水平手势排除右侧 8%（参考 kt 项目）。注意死区只拦截对应方向：底部死区里左右滑动仍生效，属预期 |
| 双指捏合误触发左右滑动 | 第二根手指落下前的短暂单指位移会被立即分类成方向滑动 → 缩放时偶尔触发 seek | 手势层方向确认延迟 80ms + 双指标记；滑动中途加入第二指先回调 `onSwipeCancel` 撤销 seek（§4.8） |
| 滑杆没有刻度点 | Flutter 在刻度过密时（间距 < 3×刻度宽）整条跳过刻度绘制；长按倍速 50 档必然过密 | `DenseSliderTickMarkShape`（settings_ui.dart）：对外声明极小宽度通过密度检查，实际仍画小圆点 |
| 自动亮度下读不到实时亮度 | `Settings.System.SCREEN_BRIGHTNESS` 在自动亮度模式下是固定基值（常 ~50%），`Display.getBrightness()` 等实时接口不存在/需系统权限 | 进入播放把读到的系统值应用到窗口（kt/mpvEx 做法，显示与指示器一致），退出恢复 -1；手动亮度模式下精确跟踪 |
| MediaMetadataRetriever 取帧 | `getFrameAtTime` 在 API 29+ 标记废弃（仍可用）；**OPTION_CLOSEST_SYNC 在非关键帧位置经常返回 null 甚至抛异常**（若与 CLOSEST 共用一个 try/catch，SYNC 抛异常会跳过 CLOSEST）；OPTION_CLOSEST 精确解码最可靠但偏慢；另注意旧版 video_thumbnail 0.5.6 的 build.gradle 引用已移除的 jcenter()，Gradle 9 下配置即失败 | 抓帧**原生通道为主**（磁盘缓存命中零解码 → `MediaMetadataRetriever` SYNC 快 → CLOSEST 稳，各自独立 try/catch → 成功后落盘），video_thumbnail_plus 包为兜底（只走 SYNC，带 4 秒超时防挂死，成功也经 `putVideoFrame` 落盘）；`ThumbnailPreloadService` 全片预热 + 拖动时最近帧秒显（`peekFrame/peekNearestFrame`）；磁盘空/损坏文件自动删除重解（防桶永久转圈） |
| MethodChannel 参数类型 | **Dart 的小整数（32 位内）经 StandardMessageCodec 编码后，Android 端是 `Integer` 而非 `Long`**；用 `call.argument<Long>` 会抛 `ClassCastException: Integer cannot be cast to Long`，通道静默失败（表现为功能"永远不生效"且无崩溃）——本次缩略图原生路径失效 + 磁盘 0B 的历史根因 | **取整型参数一律用 `call.argument<Number>("x")?.toLong()/toInt()`**，不要用 `argument<Long>`（本文件 `getVideoFrameAt` / `putVideoFrame` 的 timeMs 已按此修复） |
| FrameGrabber（MediaCodec 硬解）已接入后回退 | 曾用 MediaCodec（`getOutputImage` 无 surface 模式 + 软件 YUV→RGB）替换 MediaMetadataRetriever 抓帧，实测**反而更慢/效果更差**：每次新建 codec + configure，部分解码器不支持无 surface 输出导致全部落入回退，叠加额外开销；图像质量/旋转也可能有偏差 | 原生抓帧保持 `MediaMetadataRetriever.getFrameAtTime(OPTION_CLOSEST)` + 磁盘缓存；`FrameGrabber.kt` 已删除，勿再引入（真机验证为准） |
| 缩略图缓存自动清理 | 缓存无上限会持续增长（每视频 ~2.5-4MB） | 原生 `maybeAutoCleanCache`：每写入 30 帧检查总量，**>200MB 时按文件修改时间从旧到新删到 50MB**；手动清理走设置 → 关于 → 工具 → 缓存管理（`CacheManagerService`），支持逐类清除与一键清除（二次确认） |
| 缓存文件分类 | `cacheDir/thumbs/` 混放列表封面与进度条缩略图 | 按文件名下划线分段区分：≥3 段（`hash_mod_bucket_width.jpg`）为进度条缩略图，否则为列表封面；`clearCache/clearAllCaches` 按此分类删除（未来弹幕/字幕类别预留 `other`） |
| 缩略图预览只对本地文件 | PiliPlus 的进度条缩略图走 B 站服务端 videoshot 接口（仅网络视频）；本地视频无现成算法 | 本项目用 MediaMetadataRetriever 任意时刻抓帧实现（MainActivity `getVideoFrameAt`），进度条拖动时按秒分桶请求 |

---

## 8. 参考项目

- `参考项目/mpvRx-master/` — 树状模式（逐级导航 + 面包屑）的设计来源
- `参考项目/PiliPlus-main/` — 设置体系、配色规模、弹窗交互参考
- `参考项目/对话.txt` / `修复.txt` — 历史修复记录（勿删，排查回归时查阅）
