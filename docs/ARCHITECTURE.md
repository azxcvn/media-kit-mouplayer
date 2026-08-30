# 小牛Player（Flutter版小喵）项目架构指南

> 本文件是项目的**唯一架构契约**。任何 AI / 开发者在本仓库添加新功能前，必须先读完本文件。
> 遵循本文件的约定，项目可以健康扩展到 PiliPlus / mpvRx 同量级规模；违反约定堆代码，项目会退化为屎山。
> **完成重大功能新增 / 优化或 Bug 修复后，必须同步更新本文档（至少 §2 目录结构），禁止文档与代码脱节。**
> **本文档不设「参考项目」一节**：外部参考项目（mpvRx/PiliPlus/Kazumi/小喵 等）不随仓库分发（已 gitignore），
> 参考来源只在正文行内注明（如「对齐 mpvRx」）；禁止在文末新增独立的「参考项目」清单。

---

## 1. 项目简介

Flutter 本地视频播放器（Android），核心能力：
- 扫描本地视频（MediaStore + 「允许管理所有文件」权限）
- **列表模式**：含直接视频的文件夹 → 文件夹详情页（纯视频列表）
- **树状模式**：逐级目录导航（mpvRx 风格），一级界面显示独立文件夹卡片，点入下钻，带面包屑
- 两种模式共用同一套卡片组件（视觉一致）
- 播放器：media_kit，横屏沉浸式全屏，播放进度持久化；**听视频**（共享 Player 只播音频，
  封面模糊背景 + 1:1 圆角封面 + 胶囊式底部倍速/列表面板 + 定时关闭 + 后台播放（前台服务保活）+ 时间刻随机播放）
- **字幕**（阶段1 第 3 点）：内嵌轨道 + 外挂字幕导入（Android≤11 系统选择器 / >11 自建选择器带排序与文件夹记忆）
  + 同名字幕自动加载（同目录按视频名前缀匹配，简体系统优先 sc、繁体优先 tc）；
  单选模型，延迟/样式/杂项/字体四类设置，样式支持预设 + RGBA 滑杆调色与 ASS 强制覆盖开关，内嵌样式字幕默认尊重自带样式；
  自定义字体走 libass 原生渲染 + 运行时选择字体目录批量导入（§4.10）
- **音频**：内嵌音轨切换 + 外部音轨导入/移除（外部音轨临时，退出播放后不保留）；
  音频声道（自动/安全自动/单声道/立体声/反向立体声）+ 音频处理（音量标准化/动态范围压缩），
  对齐 mpvRx 的 `audio-channels` 与 `af` 滤镜链；声道/处理为会话级状态（每次进播放器重置）
- **音频均衡器**：5 频段（60/230/910/3.6k/14k Hz，±15dB，1dB 步进）+ 低音增强（0-100）
  + 虚拟环绕（0-100），内置 6 个影视向预设（平直/对白增强/电影/低音震撼/高音清晰/柔和夜间，
  关键频段 ±6~8dB）；入口在播放器「更多 → 音频均衡器」（可加至顶栏槽位）；对齐小喵 player
  的 mpv `af` 命名滤镜（`@eq`/`@bass`/`@virt` lavfi 链）；设置全局持久化（`EqualizerSettings`，
  区别于声道/处理的会话级）
- **进度条缩略图**：自建 libmpv 内核（含 `mk_thumbnail_*` 快速抓帧接口）+ FFmpeg/MediaCodec
  硬解独立解码实例（~85ms/帧），拖动实时预览、松手精确落帧、空闲预取邻近帧（§4.9）
- 超分辨率：Anime4K v4 着色器链（7 档模式：关闭 + A/B/C/A+/B+/C+，× 质量档 流畅/均衡/高清），底栏固定入口
- 片头片尾自动跳过：全局开关，按秒跳过片头 / 按剩余时间跳过片尾，播放中「设为当前时间」，一键重置
- **弹幕（阶段1）**：canvas_danmaku 渲染 + 本地弹幕加载（同名 9 种命名规则自动加载
  + 「更多→弹幕→本地弹幕」文件选择器手动导入，选择器规则对齐字幕）+ 弹幕二级界面
  （本地/网络/自动匹配/设置四入口）+ 播放界面开关/设置按钮（横屏左下角时间右侧 /
  竖屏右下角进度条上方）（§4.11）
- **弹幕设置（阶段2）**：弹幕样式（字号/字重/速度/描边/不透明度无极滑杆 + 随机渐变色
  忽略文件颜色）+ 弹幕配置（显示区域/行高/顶·底·滚动三类显隐/海量弹幕/弹幕去重）
  + 弹幕偏移（时间轴偏移 -180~+180 秒，正 = 延后、负 = 提前，对齐 Kazumi）；
  设置全量持久化（`DanmakuSettings`），三入口（横屏底栏设置按钮/竖屏进度条上方设置
  按钮/更多→弹幕→弹幕设置）进入同一面板（§4.11）
- **网络弹幕 / 自动匹配（阶段3）**：接入弹弹Play 开放弹幕网络（签名验证模式）——
  网络弹幕三级界面搜索（搜索历史胶囊 + 一键清除 + 上限淘汰最旧）、自动匹配
  （文件前 16MB MD5 匹配）、切集自动匹配（缓存番剧集列表按集数自动加载）、
  弹幕服务器管理（默认弹弹Play 不可删 + 自建服务器增删启停，搜索合并展示）；
  密钥存 gitignored 私有文件（§4.11）
- 外观设置：23 种主题色 + 21 种调色板风格（flex_seed_scheme）

技术栈：Flutter 3.44+ / Dart 3.12+，依赖见 `pubspec.yaml`。

---

## 2. 目录结构（lib/）

> 文档约定（工作.md 第 1 点）：**每个 dart 文件必须带 `#` 一行简短描述**，
> 只说明「这个文件负责什么」，不展开实现细节；新增文件必须同步更新本树。

```
lib/
├── main.dart                  # 入口：主题装配 + AppFrame + 路由观察者 + 崩溃日志钩子
├── models/                    # 纯数据模型（无逻辑、无依赖）
│   ├── tree_node.dart         # 目录树节点（folder/video）
│   ├── video_file.dart        # 视频文件信息
│   ├── player_action.dart     # 播放器按钮动作 / 双击手势模式 / 视频方向模式
│   ├── player_loop.dart       # 循环播放模式枚举（off/列表循环/单集循环）
│   ├── playlist_sort.dart     # 播放列表排序 + 目录过滤纯函数
│   ├── chapter_info.dart      # 章节模型（ChapterInfo/SkipSegment/跳过类型枚举）
│   ├── audio_track.dart       # 音轨模型 + 声道枚举（auto/auto-safe/mono/stereo/反向立体声）+ 格式过滤/af 滤镜链纯函数
│   ├── subtitle_track.dart    # 字幕轨道模型 + 展示名/格式过滤/对齐/颜色/RGBA 转换/字体过滤纯函数
│   ├── super_resolution_mode.dart  # 超分模式/质量枚举 + 着色器链构建纯函数
│   ├── equalizer_preset.dart  # 音频均衡器预设模型（14 预设 + 频段标签 + 反查/相等纯函数）
│   ├── danmaku_entry.dart     # 弹幕条目纯数据模型（时间/模式/颜色/文本，可跨 isolate 发送）
│   ├── danmaku_server.dart    # 弹幕服务器配置模型（默认弹弹Play + 自建服务器，toJson/fromJson）
│   ├── dandan_models.dart     # 弹弹Play API 数据模型（番剧/集/评论/匹配候选，fromJson 容错）
│   └── danmaku_auto_match_cache.dart # 弹幕自动匹配缓存模型（番剧 + 集列表，供切集自动匹配）
├── services/                  # 业务逻辑 / 数据层（无 UI）
│   ├── view_settings.dart     # 排序/字段/视图模式设置（ChangeNotifier + 持久化）
│   ├── video_scanner.dart     # 扫描 + 建树 + 建文件夹列表
│   ├── video_info_service.dart# 列表封面缩略图（磁盘缓存）+ 基本元数据 + 完整媒体信息
│   ├── playback_progress_service.dart  # 播放进度（ChangeNotifier + 持久化 + 串行写盘）
│   ├── player_controls_settings.dart   # 播放器控制设置（槽位/手势/倍速/比例/长按/方向/顶部信息等）
│   ├── device_services.dart   # 设备能力：音量/亮度/画中画/电量/网络类型/后台服务启停/字幕·字体文件与目录操作（MethodChannel）+ 任意时刻抓帧（FFmpeg 引擎 + 秒桶内存 LRU）
│   ├── fast_thumbnails.dart   # FFmpeg 快速缩略图引擎（FFI 直连自建 libmpv.so 的 mk_thumbnail_*，单飞+顶旧调度）
│   ├── crash_log_service.dart # 崩溃日志：列表/读取/删除/清空/导出
│   ├── cache_manager_service.dart # 缓存管理：列表封面磁盘缓存查询/清除（进度条缩略图为纯内存，不占磁盘）
│   ├── super_resolution_service.dart   # 超分：模式持久化、着色器拷贝、mpv 应用
│   ├── chapter_tracker.dart   # 章节跟踪器（mpv chapter-list 读取 + 当前位置/片段/胶囊窗口状态）
│   ├── intro_outro_settings.dart # 片头片尾全局设置（开关/片头秒数/片尾秒数/各自范围，ChangeNotifier + 持久化）
│   ├── intro_outro_tracker.dart  # 片头片尾跟踪器（就绪/已处理状态 + 恢复点感知 + 动作决策）
│   ├── media_scan_settings.dart  # 媒体扫描与过滤设置（.nomedia/隐藏文件夹/黑白名单，ChangeNotifier + 持久化）
│   ├── audio_service.dart     # 音频控制器（音轨列表/aid 单选/外部音轨导入·移除（临时）/声道/af 滤镜链应用；声道与处理为会话级，随播放器生命周期重置）
│   ├── subtitle_settings.dart # 字幕设置（延迟/大小/位置/颜色/描边模式/内嵌样式覆盖/自定义字体/外挂字幕记忆/重置样式，ChangeNotifier + 持久化）
│   ├── subtitle_service.dart  # 字幕控制器（单选模型：track-list/sid 同步/sub-add/sub-remove + 同名字幕自动加载 + 设置应用 + 切集重应用 + 外挂字幕跨会话恢复）
│   ├── equalizer_settings.dart # 音频均衡器设置（5 频段/低音增强/虚拟环绕/预设，ChangeNotifier + 持久化，AudioController 订阅重应用 af 链）
│   ├── danmaku_service.dart    # 弹幕控制器（业务层：本地同名/手动导入/网络弹幕装载 + 1s tick 秒桶发射 + canvas 渲染层显隐/暂停/倍速同步 + 设置订阅应用 + 切集自动匹配，横竖屏共享）
│   ├── danmaku_scheduler.dart  # 弹幕调度器（纯逻辑：秒桶 + 前向补发 + seek 跳变检测 + 代数失效）
│   ├── danmaku_memory.dart     # 弹幕手动导入记忆（视频路径→弹幕文件路径，SharedPreferences JSON 持久化）
│   ├── danmaku_settings.dart   # 弹幕设置（样式：字号/字重/速度/描边/不透明度/随机色 + 配置：区域/行高/三类显隐/海量/去重 + 偏移：时间轴偏移，ChangeNotifier + 持久化）
│   ├── dandan_play_keys.dart   # 弹弹Play API 密钥（私有，gitignored，禁止上传 GitHub）
│   ├── dandan_play_api.dart    # 弹弹Play 开放弹幕网络 API 客户端（签名验证模式：搜索/拉取弹幕/文件匹配）
│   ├── danmaku_server_settings.dart # 弹幕服务器设置（默认+自建服务器增删启停 + 切集自动匹配开关及其与默认服务器的互斥裁决，ChangeNotifier + 持久化）
│   ├── danmaku_search_history.dart  # 网络弹幕搜索历史（关键词去重/上限淘汰最旧/一键清除，持久化）
│   ├── danmaku_auto_match_cache_store.dart # 弹幕自动匹配缓存存储（番剧+集列表，切集自动匹配用）
│   ├── danmaku_network_service.dart # 弹幕网络服务（搜索合并/文件匹配/下载落盘 filesDir/danmaku/network + 文件前16MB MD5，无 UI）
│   └── ...                    #   ⚠️ 不要在这里加全局 ValueNotifier hack（见 §4.1）
├── widgets/                   # 可复用 UI 组件（跨页面）
│   ├── app_frame.dart         #   ★ 全局框架：安全区 + 播放页全屏检测
│   ├── app_dialog.dart        #   showAppDialog（统一弹窗动画）
│   ├── player_panel.dart      #   ★ 右侧滑入面板壳 + showPlayerPanel（横屏二级界面外壳）
│   ├── player_bottom_panel.dart # ★ 竖屏底部弹出面板壳 + showPlayerBottomPanel
│   ├── player_option_chip.dart#   面板选项胶囊（倍速/超分共用）
│   ├── options_sheet.dart     #   统一排序弹窗（字段胶囊选择）
│   ├── folder_card.dart       #   文件夹卡片（列表/树状共用）
│   ├── video_card.dart        #   视频卡片（列表/树状/详情共用）
│   ├── settings_ui.dart       #   设置页公共组件（分组/卡片/设置项/滑杆主题 + 播放器暗色面板强调色派生 playerPanelAccent/playerPanelSliderTheme）
│   ├── raw_thumb_image.dart   #   RGBA 帧直渲组件（FastThumbFrame → ui.Image，帧切换保持上一帧无缝）
│   ├── capsule_nav_bar.dart   #   悬浮胶囊导航
│   ├── main_scaffold.dart     #   主壳（PageView + 悬浮胶囊）
│   └── marquee_text.dart      #   无缝循环跑马灯
├── pages/                     # 页面（每页一个目录）
│   ├── home/
│   │   ├── home_page.dart     #   首页（权限门禁 + 视图分发 + 搜索入口）
│   │   ├── views/             #   首页专属视图组件
│   │   │   ├── folder_list_view.dart  # 列表视图
│   │   │   └── tree_list_view.dart    # 树状一级视图
│   │   ├── folder_detail_page.dart    # 列表模式详情页（纯视频）
│   │   └── tree_folder_page.dart      # 树状目录页（混合内容 + 面包屑）
│   ├── player/
│   │   ├── player_page.dart   #   播放页（横屏沉浸式；手势/恢复进度/切集/EOF/画中画/面板）
│   │   ├── player_metrics.dart #  人体工学对齐常量 kPlayerLeftInset（横竖屏共用）
│   │   ├── player_portrait_page.dart # 竖屏播放页（共享横屏 Player/VideoController，切换零中断）
│   │   ├── audio_player_page.dart    # 听视频页（共享 Player 只播音频；封面模糊背景；1:1 圆角封面；后台播放；循环三态）
│   │   └── views/             #   播放页专属控制组件
│   │       ├── player_top_bar.dart        # 顶栏：返回 + 标题 + 5 槽位 + 更多
│   │       ├── player_status_bar.dart     # 顶部信息行：时间/电量居中 + 网速胶囊/数据类型靠右（多选控制）
│   │       ├── player_center_cluster.dart # 中央簇：快退/播放暂停/快进
│   │       ├── player_danmaku_layer.dart  # 弹幕渲染层（canvas_danmaku DanmakuScreen 封装，视频层与手势层之间，挂载/卸载即 rebind）
│   │       ├── player_danmaku_buttons.dart# 弹幕开关/设置按钮组（Kazumi 图标：开=内联 SVG 主题色对勾，关/设置=资源 SVG）
│   │       ├── player_danmaku_panel.dart  # 弹幕二级界面（本地弹幕=复用字幕选择器面板导入 / 网络弹幕 / 自动匹配 / 弹幕设置；DanmakuFileService）
│   │       ├── player_danmaku_network_panel.dart # 网络弹幕搜索三级界面（40dp 胶囊搜索框 + 框下关键词历史胶囊 + 命中后折叠为关键词条 + 结果卡自持动画展开集列表，横竖屏共用）
│   │       ├── player_danmaku_settings_panel.dart # 弹幕设置面板（样式：字号/字重/速度/描边/不透明度滑杆+随机渐变色；配置：区域/行高/三类显隐/海量/去重；偏移：时间轴偏移；横竖屏外壳共用）
│   │       ├── player_bottom_bar.dart     # 底栏：进度条 + 下一集 + 时间 + 弹幕开关/设置 + 右下角按钮簇
│   │       ├── player_seek_bar.dart       # 自绘进度条（替代 Slider，起点对齐 kPlayerLeftInset；章节圆点 + 跳过色段）
│   │       ├── player_chapter_bar.dart    # 章节名行（可点击呼出列表）+ 跳过胶囊（5 秒自动消失/控制层可见时常驻）
│   │       ├── player_chapter_panel.dart  # 章节列表面板（竖向滚动 + 实时高亮当前章节 + 点击跳转）
│   │       ├── player_intro_outro_panel.dart # 片头片尾设置面板内容（开关/滑杆/分秒换算/设为当前时间/一键重置）
│   │       ├── player_loop_panel.dart     # 循环播放面板内容（横竖屏共用）
│   │       ├── player_right_actions.dart  # 右侧竖排：截图 + 锁定
│   │       ├── player_fit_panel.dart      # 画面比例面板内容
│   │       ├── player_speed_panel.dart    # 倍速面板内容（预设/精确调速/临时应用）
│   │       ├── player_super_resolution_panel.dart  # 超分面板内容
│   │       ├── player_play_pause_button.dart  # 播放/暂停图标形变动画
│   │       ├── player_gesture_layer.dart      # ★ 手势层（裸识别器方案，见 §4.8）
│   │       ├── player_gesture_indicator.dart  # 音量/亮度手势指示器
│   │       ├── player_speed_indicator.dart    # 长按倍速指示器（胶囊样式）
│   │       ├── player_playlist_panel.dart     # 播放列表面板内容
│   │       ├── audio_player_panels.dart       # 听视频倍速/列表面板（胶囊式 + 定时关闭预设 + 统一关闭按钮）
│   │       ├── audio_panel.dart               # 音频面板（音轨单选+外部音轨导入·移除+音频声道胶囊+音频处理开关）
│   │       ├── equalizer_panel.dart           # 音频均衡器面板（开关+预设胶囊+5 段竖向滑块+低音增强/虚拟环绕+一键重置）
│   │       ├── subtitle_panel.dart            # 字幕面板（轨道单选+外挂导入+移除；延迟输入合一/样式卡片化/杂项缩放位置/自定义字体目录导入+列表选择）
│   │       ├── subtitle_file_picker.dart      # 外挂字幕选择（≤11 系统选择器 / >11 自建选择器+文件夹记忆+文件过滤器+死路径向上回退；音频/弹幕选择器复用同一面板）
│   │       ├── player_resume_indicator.dart   # 恢复进度指示器（胶囊样式，2.5s 自动隐藏）
│   │       ├── player_swipe_seek_overlay.dart # 水平滑动 seek 预览浮层
│   │       ├── player_thumbnail_preview.dart  # 进度条拖动缩略图预览气泡（RGBA 直渲 + 淡入淡出）
│   │       ├── portrait_player_top_bar.dart   # 竖屏顶栏（两行：返回+标题 / 5 槽位+更多横向均分，与横屏一致支持 5 槽位）
│   │       ├── portrait_player_bottom_bar.dart # 竖屏底栏（章节名+弹幕开关/设置行 → 进度条 → 操作行：超分→列表→倍速→选择屏幕）
│   │       └── portrait_edit_panel.dart       # 竖屏「编辑控制栏」页
│   ├── media_info/
│   │   └── media_info_page.dart # 媒体信息页（MediaInfoLib 解析 + 一键复制）
│   └── settings/
│       ├── settings_page.dart #   设置主页（分组结构）
│       ├── appearance_page.dart      # 外观设置子页
│       ├── player_settings_page.dart # 播放器设置子页（手势/视频方向/顶部信息/播放行为/阈值）
│       ├── media_scan_settings_page.dart # 媒体扫描与过滤设置子页（.nomedia/隐藏文件夹/黑白名单）
│       ├── danmaku_server_page.dart # 弹幕服务器设置子页（默认+自建服务器增删启停 + 切集自动匹配开关，互斥时变灰+原因文案+点击 toast）
│       ├── about_page.dart           # 关于页（软件信息/工具/信息）
│       ├── license_page.dart         # 许可证书页（列表 + 二级详情页，非折叠式）
│       ├── error_log_page.dart       # 错误日志页
│       └── cache_management_page.dart# 缓存管理页
├── theme/                     # 主题
│   ├── app_theme.dart         #   ThemeData 生成（light/dark/amoled）
│   └── theme_controller.dart  #   主题控制（模式/色/风格 + 迁移）
└── utils/                     # 纯工具函数
    ├── app_dialog.dart        #   （见 widgets/app_dialog.dart 说明）
    ├── formatters.dart        #   大小/日期/时长/倍速/网速格式化 + 在线媒体判定
    ├── natural_compare.dart   #   自然序（数字感知）比较
    ├── watch_state.dart       #   观看状态纯函数（未观看/观看中/已看完）
    ├── playback_completion.dart # EOF 动作解析纯函数（优先级链）
    ├── playback_restore.dart  #   恢复进度：openAndRestore（暂停加载→静音激活时间线→seek→确认）
    ├── pip_aspect.dart        #   画中画宽高比纯函数
    ├── player_gestures.dart   #   双击判定 + 滑动手势数学
    ├── chapter_utils.dart     #   章节纯函数（标题分类/片段派生/当前章节/跳过目标）
    ├── intro_outro_skip.dart  #   片头片尾动作决策纯函数（跳过片头/切下一集/无动作）
    ├── audio_shuffle.dart     #   听视频随机播放算法（结合当前时间刻，纯函数）
    ├── subtitle_auto_match.dart # 同名字幕自动匹配纯函数（扩展名优先级 + 同名优先 + 简/繁语言后缀，对齐小喵）
    ├── subtitle_sort.dart     #   自建字幕选择器排序纯函数（目录恒在前）
    ├── danmaku_timeline.dart  #   弹幕时间轴纯函数（同秒多条 1 秒内错峰延迟 + 时间轴偏移）
    ├── danmaku_local_file.dart #  同名弹幕文件查找纯函数（9 种命名规则，只查同目录）
    ├── danmaku_random_color.dart # 随机渐变色纯函数（HSV 色轮黄金角步进推进器，忽略文件颜色）
    ├── danmaku_dedup.dart     #   弹幕去重纯函数（文本归一化判同 + 时间窗合并）
    ├── danmaku_episode.dart   #   弹幕集数提取/匹配纯函数（文件名→集数 + 缓存集列表定位，切集自动匹配）
    ├── dandan_signature.dart  #   弹弹Play 签名纯函数（base64(sha256(AppId+Timestamp+Path+AppSecret))）
    ├── dandan_comment.dart    #   弹弹Play 评论→弹幕条目/B站 XML 纯函数（p 字段解析 + 排序 + 落盘 XML 生成）
    └── danmaku_xml.dart       #   B站 XML 弹幕解析/生成纯函数（解析供 compute 后台执行 + 实体反转义 + 文本转义）
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
- 现有控制器：`ViewSettings`（排序/字段/视图模式）、`ThemeController`（外观）、`PlaybackProgressService`（单例，进度）、`SuperResolutionService`（单例，超分模式+质量+记忆开关）、`SubtitleSettings`（单例，字幕延迟/大小/位置/对齐/颜色/字体/内嵌样式覆盖，默认关闭）、`EqualizerSettings`（单例，均衡器 5 频段/低音增强/虚拟环绕/预设，默认关闭，全局持久化）；控制按钮背景（底栏倍速/列表图标/顶栏控制图标，默认关闭）、倍速记忆（默认关闭）、画面比例（默认自动）、**长按倍速（倍率 1–4 步进 0.5/指示器开关/首次提示标记，阶段1 第 4 点）**、音量亮度手势灵敏度（默认 1.0）、保存音量到系统（默认开启）、双指缩小视频（默认开启）、进度条缩略图（默认开启，见 §4.9）、已观看进度阈值（5%–100% 步进 5%，默认 95%）、自动连播（默认开启）、播放完毕自动退出（默认开启）、循环播放模式（off/列表循环/单集循环，默认关闭）、视频方向（自动/锁定竖屏/锁定横屏，默认自动）、播放界面动画（默认开启）、**顶部信息多选（时间/电量/网速/数据类型四项，默认全选，阶段1 第 1 点；旧单选枚举一次性迁移）** 属 `PlayerControlsSettings`
- 播放页音量/亮度属于**页面局部状态**（进入时从系统同步，退出时按设置写回/恢复，见 §4.8），禁止做成全局服务
- 音频声道/音频处理（音量标准化/动态范围压缩）为**会话级状态**（随 `AudioController` 生命周期，每次进播放器重置为默认：安全自动/关/关），不持久化
- 片头片尾跳过设置属 `IntroOutroSettings`（独立单例 ChangeNotifier）：启用开关（默认关闭）、片头/片尾跳过秒数（默认 0）、各自范围上限（10–600 秒，默认 180）；范围收窄时秒数联动收窄；一键重置只清秒数与范围、保留开关；跟踪器 `IntroOutroTracker` 为普通类（随播放页生命周期），就绪门控防 open 期间误触发
- 弹幕服务器设置属 `DanmakuServerSettings`（独立单例 ChangeNotifier，阶段3）：服务器列表（默认弹弹Play 不可删 + 自建增删启停）+ 切集自动匹配开关（**与默认弹弹Play 服务器互斥**，互斥判定与提示文案统一由本服务提供，见 §4.11），启动 `ensureLoaded`（main.dart）
- 播放页位置/时长属于**页面局部 ValueNotifier + 局部订阅**（risk_audit #1）：位置流几十毫秒一次事件，若整页 `setState` 会重建整棵 Stack（视频层/手势层/控制层），实际只有进度条、时间文本、常驻进度线需要跟随。横竖屏播放页把 `_position`/`_duration`/`_dragPosition` 抽为页面级 `ValueNotifier`，底栏与常驻进度线用 `Listenable.merge` 局部订阅只重建自身；页面级 `setState` 只留给低频状态（播放/暂停、控制层显隐、锁定、切集）。**注意这是页面局部 ValueNotifier**（dispose 时销毁），不属于被禁的「全局 ValueNotifier hack」
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

- **push 播放页统一用 `playerPageRoute`**（`app_frame.dart`，**无进出场动画**、瞬时切换 + 自动带 `RouteSettings(name: playerRouteName)`）；勿用 `MaterialPageRoute` 手写 settings——用户明确要求去掉进出播放的动画（历史滑动转场暴露「一半播放页、一半 app 界面」的过渡帧），瞬时切换后播放页与列表页任何时刻不同框
- 播放页内部**不要**手动设置任何全局状态
- 现有三处 push 已改用 `playerPageRoute`（home_page / folder_detail_page / tree_folder_page 的 `_openVideo`/`_openPlayer`）

### 4.4 播放页全屏（系统栏）

`player_page.dart` 的 `_enterFullscreen()`：`immersiveSticky` + 透明系统栏（`_exitPlayer` / `dispose` 恢复竖屏 + edgeToEdge）。退出统一走 `PopScope` 拦截 + `_exitPlayer()`：**同一帧 `pause()` 冻结末帧**（mpv 零新帧，末帧随瞬时 pop 消失，不再「黑屏渐隐」）→ 发起竖屏方向 + 保存进度 + 恢复设备状态（均 `unawaited` 不阻塞）→ 恢复系统 UI → **立即 pop**（`playerPageRoute` 无动画，与系统旋转并行）；**播放器销毁交给 `dispose()` 幂等兜底**（pause 已停帧，flutter#188300 不复发）。竖屏页退出走 `_exitWithPortrait`：先置 `_exitBlackout` 把下层横屏页整体黑化 → `pause()` 冻结 → IO `unawaited` → 连续 pop 竖屏页 + 横屏页（下层纯黑，任何时刻两层不同框，「两个竖屏界面」在机制上不可能复现）。系统返回键与返回按钮行为一致。

### 4.5 弹窗 / 面板

- **所有弹窗统一用** `showAppDialog`（`lib/utils/app_dialog.dart`，缩放 + 淡入动画），**不要**直接 `showDialog`
- **播放器内右侧滑入面板统一用** `showPlayerPanel`（`lib/widgets/player_panel.dart`，滑入 + 淡入 + 面板内页面栈）。倍速 / 超分 / 画面比例 / 更多 / 编辑控制栏共用；面板内二级页面用 `PlayerPanelNavigator.of(context).push(...)` 就地切换，禁止叠加第二个面板。**新增类似右侧面板需求时直接复用，勿另写一套**。注意：`of` 必须用面板树内的 context（内容里先包一层 `Builder` 再取），不能用页面 State 的 context。`showPlayerPanel` / `showPlayerBottomPanel` 的 `animate` 参数（默认 null = 跟随「播放器设置 → 启用播放界面动画」开关）控制进出场与页内切换动画
- **播放界面二级界面硬性约定**：播放器内凡需弹出二级界面（倍速、超分、画面比例、字幕/音频等后续功能）的，**横屏一律使用 `showPlayerPanel` 右侧滑入外壳**（同款外壳必须保证）；**竖屏播放页（`player_portrait_page.dart`）一律使用 `showPlayerBottomPanel` 底部弹出外壳**（`lib/widgets/player_bottom_panel.dart`，底部上滑 + 淡入，Material 外壳，面板内页面栈 `PlayerBottomPanelNavigator`）。两种外壳的面板内容组件（倍速/超分/画面比例/编辑控制栏）共用同一份数据与交互逻辑，只换容器。面板内容可选用 `PlayerOptionChip` 胶囊选择（视功能而定），也可用列表等其他形式，但**不得另写一套弹窗/面板外壳**。**竖屏页高需求**：`PlayerPanelPage.bottomHeightFactor`（默认 null = 外壳 0.42）可按页覆写底部外壳最大高度占比，只影响该页、返回上一页自动收回（高度差 240ms easeOutCubic 过渡）；网络弹幕搜索页用 0.82。**禁止**为了页高另开一个外壳
- **「更多」面板交互**：横竖屏「更多」面板均只列出**未放入槽位的动作**（`PlayerTopAction.values` 中不在 `topActions` 的）；点面板类动作（字幕/音频/比例/循环/章节/片头片尾）→ 面板内 `push` 就地切换（外壳 header 自动显示返回按钮，可返回「更多」列表，勿再关面板重开）；点动作类（画中画/听视频）→ 先关「更多」面板再执行（防叠加第二面板）；未实现动作提示「即将上线」；「编辑控制栏」为固定入口。**一级菜单 ListView 带 `PageStorageKey('more_panel')` 记忆滚动位置**（进二级再返回不回顶部）
- **编辑控制栏交互**：横竖屏编辑控制栏的「已启用/可添加」列表项**无副标题**（图标与名字用 `titleAlignment: center` 对齐）；槽位已满（5/5）时点「添加」→ toast「最多允许放 5 个」（不再禁用按钮 + 副标题提示）；「重置控制栏」无副标题。竖屏与横屏一致最多 5 槽位（`PortraitPlayerTopBar.maxPortraitSlots = 5`），不再区分 4/5
- **排序/字段弹窗统一用** `showSortOptionsSheet(context, viewSettings, hasFolders:, hasVideos:, showViewMode:)`（`lib/widgets/options_sheet.dart`）
  - `hasFolders` / `hasVideos` 按页面内容动态传（纯文件夹页、纯视频页、混合页自动区分区块）
  - `showViewMode` 仅首页传 true
  - 视频字段共 7 个（时长/大小/日期/分辨率/进度/字幕指示器/帧率），弹窗按三行胶囊展示（第一行 时长/大小/日期，第二行 进度/帧率/分辨率，第三行 字幕指示器独占整行）
- 搜索入口：首页/目录页/详情页 AppBar 右上角「搜索」在「排序」左侧，点击切换为内嵌搜索框，按名称（不区分大小写）过滤当前列表
- 弹窗类命名为 `_XxxSheet`，放页面文件内或公共 `widgets/`（跨页共用时）

### 4.6 卡片复用（树状/列表视觉一致的根基）

- 文件夹 → `FolderCard`（`widgets/folder_card.dart`），参数：`node / fields / onTap`
- 视频 → `VideoCard`（`widgets/video_card.dart`），参数：`video / fields / onTap / onInfoTap`
- **任何新视图/新页面显示文件夹或视频时，必须复用这两个卡片**，禁止另写一套样式
- 字段由 `ViewSettings.fields`（FolderField）和 `viewSettings.videoFields`（VideoField）驱动
- VideoCard 字段布局：**时长** = 缩略图右下角标签、**大小** = 缩略图左下角标签（两者自动避让底部进度条，有进度条时上移）；其余字段（日期/分辨率/进度/帧率/字幕指示器）为名称下方标签行；最右侧「i」媒体信息入口（`onInfoTap`，点击打开 `MediaInfoPage`）
- 「排序与字段」弹窗的视频显示字段区为**三行胶囊**布局（7 字段 = 3 + 3 + 1，行内等宽均分）：第一行 **时长/大小/日期**、第二行 **进度/帧率/分辨率**、第三行 **字幕指示器独占整行**（长度与上方两行整体一致）——见 `options_sheet.dart` 的 `_videoFieldChips`（显式指定行序，不依赖枚举顺序）
- 观看状态：`classifyWatchState`（`utils/watch_state.dart`）按「已观看进度阈值」（`PlayerControlsSettings.watchThreshold`，默认 95%）判定 未观看/观看中/已看完，已看完的卡片置灰

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
| 长按（500ms） | 临时倍速（设置值 1–4x），指示器常驻 | 长按期间 `Listener` 裸指针事件驱动左右滑动调速 |
| 长按 + 左右滑动 | 动态调速 1.5–4x（间隔 0.5，离散），出现倍速条 | 灵敏度（阶段1 第 4 点重设计）：滑动约 **1/6 屏宽**扫完整个动态区间（倍率 6.0，旧 3.5 需滑近一屏太不灵敏）；倍速条在指示器下方，停在某档 3 秒自动隐藏；首次完成该操作后提示不再出现（`speedHintShown` 持久化） |
| 单指垂直滑动 | 左半屏亮度、右半屏音量 | 顶部/底部 8% 死区（避系统手势）；音量 0–100、亮度 0–1，带浮点累加器；**方向确认延迟 80ms**（给第二根手指加入时间，防捏合误触滑动） |
| 单指水平滑动 | 实时 seek（满屏 = 90 秒，40ms 节流），居中浮层显示目标时间 | 右侧 8% 死区（避系统返回手势）；若滑动中途加入第二指，先撤销 seek（`onSwipeCancel`）再进缩放 |
| 双指 | 缩放（0.75–4x，设置可禁缩小）+ 平移 | 以双指焦点为锚缩放 + 焦点位移平移；缩放后「还原画面」胶囊出现在播放/暂停按钮下方（Alignment 0.34） |

音量/亮度与系统交互约定（原生在 `MainActivity.kt`，走 `DeviceServices`）：
- 进入播放：读系统音量作为播放音量起点（如 20%）；亮度读系统值并**应用到窗口**
  （kt/mpvEx 做法：屏幕显示与指示器一致，播放期间亮度不随自动亮度漂移），**不改系统设置**；
- 播放中：音量只调 mpv 音量（`player.setVolume` 0–100），亮度只调窗口亮度（`WindowManager` 属性，无需权限）；
- 退出播放：**亮度恢复 -1（交还系统控制 = 进入前状态）**；音量按设置「保存音量到系统」（默认开）→ 写回系统，关闭 → 恢复进入前系统音量。`dispose` 兜底恢复，防异常路径泄漏；
- 音量指示器在**屏幕左侧**、亮度指示器在**屏幕右侧**（对称）；kazumi 风格进出场
  （从屏幕边缘滑入滑出 + 淡入淡出 + 轻微缩放），2 秒无操作自动隐藏。

### 4.9 进度条缩略图 —— FFmpeg 快速引擎（自建 libmpv 内核）

> 2026-08 重构：进度条抓帧从「原生 MediaMetadataRetriever + 磁盘缓存 + video_thumbnail_plus 兜底」
> 三级链路，整体替换为**自建内核 + FFmpeg 独立解码实例**。旧链路、磁盘缓存与预生成服务已全部移除。

**内核来源**：`third_party/media_kit_libs_android_video/`（本地包，pubspec `dependency_overrides` 指向），
内含 4 个 ABI 的 jar（`android/jars/`，`fileTree` 直接引用，**不走官方下载任务**）。
jar 构建自 [azxcvn/libmpv-android-video-build](https://github.com/azxcvn/libmpv-android-video-build)
（fork，补丁 `mk_thumbnail.patch` 给 libmpv 增加 `mk_thumbnail_grab/free/clear_cache` 三个导出符号，
push 即 CI 出包）。升级内核：换 jar → 无需改任何 Dart 代码。

**调用链**（自下而上）：

| 层 | 文件 | 职责 |
|---|---|---|
| 内核 | libmpv.so `mk_thumbnail_grab` | 独立 FFmpeg 解码实例：MediaCodec 硬解优先/失败自动软解、硬解 ctx 全局复用、极速探测、**关键帧优先向后 seek + 逐帧解码到目标帧（帧级精确匹配）**；输出 RGBA |
| 引擎 | `services/fast_thumbnails.dart` | FFI 绑定 + 后台 isolate + **单飞调度**（最多 1 在跑 + 1 待跑，新请求顶掉旧待跑） |
| 缓存 | `services/device_services.dart` | `getVideoFrameAt`：秒桶 + **32MB 内存 LRU**（RGBA 字节计）+ 在飞去重 + **失败 10s 冷却**（被顶掉 `stale` 不计冷却）；`peekFrame`/`peekNearestFrame`（兜底半径 **±3s**） |
| UI | `views/player_thumbnail_preview.dart` + `widgets/raw_thumb_image.dart` | 气泡 + RGBA 直渲（`ImageDescriptor.raw`，无 PNG/JPEG 编码往返） |
| 调度 | `pages/player/player_page.dart` / `player_portrait_page.dart` | 横竖屏两页同款：拖动邻近帧秒显 + 精确帧异步补齐；松手淡出 150ms 后卸载 + **空闲 350ms 预取 ±1/±2/±3 秒桶**（再拖动立即终止，拖动请求绝对优先）；共用同一 FFmpeg 引擎与内存缓存，受同一 `showThumbnailPreview` 开关控制 |

**关键事实**：
- JavaVM 无需自行注册——media_kit 启动时已通过官方补丁 `mpv_lavc_set_java_vm` 完成，MediaCodec 硬解天然可用
- 精确落帧：播放器初始化设 mpv `hr-seek=absolute`（`_applyExactSeek`），松手 seek 帧级精确、与预览帧一致
- 缩略图**无磁盘缓存**（单帧 ~85ms 无落盘必要）；「缓存管理」页只管列表封面
- 性能基线（一加 PLR110，1080p H.264）：硬解 63–134ms/帧；logcat `MKThumb` 可查每帧 `hw=` 与耗时
- 精确匹配耗时随关键帧距离（GOP）增长：短 GOP 基本不变（~85ms）；长 GOP 高码率（4K、10s 一个关键帧）明显变慢（需逐帧桥接解码到目标）
- 听视频页封面（`audio_player_page`）复用同一引擎（`maxWidth: 480`）

### 4.10 自定义字幕字体 —— media_kit 本地 fork + mpv_initialize 前注入

**目标**：对齐小喵 player——用户**先选择一个字体目录**（SAF 目录选择器，强制不选不用），
把目录里所有 `.ttf/.otf/.ttc/.otc` 一次性拷贝到应用私有 `filesDir/fonts/`，再在字体列表里点击选择；
目录可 ✕ 清除重选、可刷新重新拷贝（新增字体后）。字体仍作为 libass 字幕字体。

**架构**（自下而上）：

| 层 | 文件 | 职责 |
|---|---|---|
| media_kit 魔改 | `third_party/media_kit/`（本地 fork，`platform_player.dart` + `real.dart`） | 新增 `libassAndroidFontsDir` 字段，在 `mpv_initialize()` 前把目录注入 `sub-fonts-dir`（绕过只支持 asset 的 `AndroidAssetLoader`） |
| 原生层 | `MainActivity.kt` | `openFontDirectoryPicker`（`ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission`）、`copyFontsFromDirectory`（`DocumentFile` 遍历顶层文件 + 批量拷贝 + 兜底字库）、`listFontEntries`（扫描私有目录 + truetypeparser 解析族名去重、隐藏兜底字库）、`clearFontsDirectory`；`ensureFallbackFont`/`getFontFamilyName` 沿用 |
| 服务层 | `subtitle_settings.dart` / `device_services.dart` | 字体族名 + 私有目录 + **源目录 tree uri** 三者持久化（`setFontSourceDir`）；`openFontDirectoryPicker`/`copyFontsFromDirectory`/`listFontEntries`/`clearFontsDirectory` 封装 |
| 播放器 | `player_page.dart` / `subtitle_service.dart` | Player 构造读字体设置注入配置；有自定义字体时不再运行时 `setProperty('sub-fonts-dir')` |
| UI | `subtitle_panel.dart` | 「字幕字体」入口 + `SubtitleFontPanel`（目录选择/刷新/清除 + 字体列表单选 + 重启提示） |

**关键约束（勿违反）**：
- **`sub-fonts-dir` 必须在 `mpv_initialize()` 前注入**——libass 只在初始化时扫一次字体目录，运行时 `setProperty('sub-fonts-dir')` 会打坏字体缓存导致字幕整条消失（Gemini 历史教训）。
- **换字体需退出播放器重新进入**（重建 Player），与小喵一致。
- **不选目录不允许用自定义字体**（工作.md 第 1 点）：源目录未选时字体列表为空，只有「默认字体」。
- **目录授权需持久化**：`takePersistableUriPermission` + `FLAG_GRANT_PERSISTABLE_URI_PERMISSION`/`FLAG_GRANT_PREFIX_URI_PERMISSION`，否则重启后 tree uri 失效、无法刷新。
- **族名解析用 truetypeparser**（`TTFFile.open(...).families.values.firstOrNull()`），手写 sfnt name 表解析器有偏移 bug（曾把 table offset 读成 0x1700583C）。
- **兜底字库用复制、普通文件名**，不用 symlink + 隐藏文件名（fontconfig 跳过 `.` 开头文件且不 follow symlink）。

**维护**：`third_party/media_kit` 是本地 fork（`pubspec.yaml` `dependency_overrides` 指向），升级 media_kit 时需手动把 `libassAndroidFontsDir` 这处魔改 merge 进新版本，禁止直接 `pub upgrade` 覆盖。依赖 `io.github.yubyf:truetypeparser-light:2.1.4` 与 `androidx.documentfile:documentfile:1.0.1`（`android/app/build.gradle.kts`）。

### 4.11 弹幕 —— canvas_danmaku 渲染 + 本地同名加载 + 设置面板

> 弹幕移植方案（`杂项文件/弹幕移植方案/`）阶段1 + 阶段2：**阶段1** =
> 「显示/隐藏 + 本地同名弹幕加载」（开关为会话级，默认开启）；**阶段2** =
> 「弹幕设置面板」（样式 + 配置全量持久化，工作.md 弹幕第 4/6 点）。
> 渲染层用 pub `canvas_danmaku: ^0.3.3`（与参考项目 `canvas_danmaku-main` v0.3.3 同版本）。

**分层**（自下而上）：

| 层 | 文件 | 职责 |
|---|---|---|
| 数据模型 | `models/danmaku_entry.dart` | 单条弹幕（time/mode/color/text，纯数据可跨 isolate） |
| 纯函数 | `utils/danmaku_local_file.dart` / `danmaku_xml.dart` / `danmaku_timeline.dart` | 9 种同名命名规则查找 / B站 XML 解析（`compute` 后台 isolate）/ 同秒错峰延迟 + 时间轴偏移 |
| 调度 | `services/danmaku_scheduler.dart` | 秒桶索引 + 1s tick 前向补发 + seek 跳变检测（±阈值）+ 代数失效（纯逻辑可单测） |
| 业务 | `services/danmaku_service.dart` | `DanmakuController`：自订阅 `stream.position/playing/rate/buffering` + 1s Timer 发射（守卫链）+ 渲染层 registry + 倍速跟随 |
| 渲染 | `pages/player/views/player_danmaku_layer.dart` | `DanmakuScreen` 封装，挂载/卸载即 attach/detach 到业务控制器；初始 option 从设置单例构建 |
| UI | `pages/player/views/player_danmaku_buttons.dart` | 开关/设置按钮组（Kazumi 图标：开=内联 `kDanmakuOnSvg` 主题色对勾；关/设置=资源 SVG，`assets/icons/`） |
| 面板 | `pages/player/views/player_danmaku_panel.dart` | 弹幕二级界面（更多→弹幕/顶栏槽位共用）：本地弹幕=复用 `SubtitleFilePickerPanel`（只换过滤器/图标/记忆键，content:// 走原生 `copyDanmakuFromUri` → `filesDir/danmaku/`）；网络弹幕/自动匹配 toast 待上线；弹幕设置与底栏按钮同一回调 |
| 设置面板 | `pages/player/views/player_danmaku_settings_panel.dart` | 弹幕设置面板（横竖屏外壳共用）：三段式布局（样式 5 滑杆 + 随机渐变色 / 配置 2 滑杆 + 5 开关 / 偏移 1 滑杆）+ 恢复默认；字号/字重/描边/偏移松手提交，其余实时写 `DanmakuSettings` |
| 设置 | `services/danmaku_settings.dart` | 弹幕设置单例（`ChangeNotifier` + SharedPreferences 持久化）：字号/字重/速度/描边/不透明度/随机色 + 区域/行高/三类显隐/海量/去重 + 时间轴偏移；启动 `ensureLoaded`（main.dart） |
| 纯函数 | `utils/danmaku_random_color.dart` / `danmaku_dedup.dart` | 随机渐变色（HSV 色轮黄金角步进 + 随机漂移，种子可复现）/ 去重（文本归一化判同 + 时间窗合并，对齐 Kazumi） |

**关键决策**：
- **渲染层 registry（横竖屏双挂）**：横竖屏两个页面各挂一个 `DanmakuScreen`，业务层
  `DanmakuController` 用 `List<DanmakuController<void>>` 同步驱动全部已挂载层——切换
  屏幕（push/pop 竖屏页）时无需清屏重启，返回横屏时弹幕无缝续播；`attachLayer` 时补
  应用当前倍速/暂停态，`detachLayer` 由渲染层 widget 的 `dispose` 触发。
- **发射模型**：Kazumi 现网「秒桶 + 1s Timer + stagger + generation」+ 两处增强——
  ① tick 间**前向补发** `(上一秒, 当前秒]` 全部桶（高倍速/计时抖动不丢弹幕）；
  ② **实时 seek 检测**（Kazumi 体验）：位置流事件上以「倍速 × 事件间隔墙钟时间」为
  期望位移（`isSeekJump` 纯函数），判定跳变**立即**代数失效 + 清屏 + 锚点对齐
  （`notifySeeked`，落点秒 - 1 下个 tick 补发落点秒弹幕），不再等下一个 1s tick；
  tick 上的跳变检测保留为兜底。均无需逐个挂钩 8+ seek 调用点。
- **倍速跟随**：`duration/staticDuration = 基准 / rate`（基准独立存储、每次现算，
  零累计误差）；canvas `updateOption` 全局平滑变速，在屏弹幕同帧变速。
- **加载会话号**：`loadForVideo` 进入即 `++_loadSession` + 重置调度器 + 清屏，
  异步读文件/解析完成后会话号已变则丢弃（旧集弹幕不灌入新集）。
- **样式映射**：B站 mode 4→底部、5→顶部、其余一律滚动（对齐 Kazumi；高级弹幕后续阶段）。

**手动导入**：`loadDanmakuFromFile(path)`（真实绝对路径，content:// 已由原生拷贝）；
成功自动开启弹幕显示并**记忆到当前视频**（`DanmakuManualMemory`，SharedPreferences
持久化，重启播放器/软件自动恢复）；`loadForVideo` 优先级 = **手动记忆 → 同名查找**
（用户显式选择不被自动查找覆盖），记忆的弹幕文件已失效（被删除/不可读/空弹幕）时
清除该条记忆并回落同名查找。手动导入为会话级生效，记忆跨会话。
自动加载（同名 / 记忆恢复）成功经 `onAutoLoadedDanmaku` 由播放页弹 toast
「已自动加载弹幕：文件名」（对齐字幕 `onAutoLoadedSubtitle` 模式）；**每个视频只在
第一次自动加载时提示**（`DanmakuManualMemory` 另存「已提示」路径集合持久化去重，
重启播放器/软件不再重复）。

**选择器死路径防护**（字幕/音频/弹幕共用面板）：`DeviceServices.listDirectory` 对
「目录不存在/不可读」返回 **null**（区别于真实空目录）；打开选择器时记忆文件夹失效
则**向上回退**到最近存活祖先；导航到失效目录维持原状不落死路径（小喵 player 停在
死路径卡死的教训）。

**设置应用（阶段2）**：控制器订阅 `DanmakuSettings`（构造时 addListener，dispose 退订）。
样式/配置（字号/字重/速度/描边/不透明度/区域/行高/三类显隐/海量）经 `updateOption`
热更新下发渲染层（速度 = 横穿耗时 `scrollSeconds / rate`，静置弹幕取其一半）；
**去重**开/关变化时按原始条目重灌秒桶（`_rawEntries` 保留原始数据）并锚定当前位置；
**随机渐变色**开启时重建色轮（新随机起点）并清屏，发射时逐条覆盖文件颜色。新挂载
渲染层的初始 `DanmakuOption` 由 `danmakuOptionFromSettings` 从设置单例构建（首帧即
用户样式）。设置全量持久化（重启视频/播放/软件均保留，工作.md 弹幕第 6 点）；
三入口（横屏左下角设置按钮/竖屏进度条上方设置按钮/更多→弹幕→弹幕设置）进入同一
面板，面板内容横竖屏共用、只换外壳（§4.5）。

**时间轴偏移（阶段2 补充）**：设置项 `DanmakuSettings.timeOffsetSeconds`
（-180~+180 秒，整数步进，正 = 延后、负 = 提前），纯函数 `sourceDanmakuPosition`
（`utils/danmaku_timeline.dart`，source = playback − offset）在发射/seek 锚定时把
播放位置映射到源时间（负秒桶视为空）；偏移变化时重锚定秒桶 + 清屏重新对齐
（对齐 Kazumi `DanmakuTimeline.resolveSourceSecond` + `danmakuTimeOffset`）。

**阶段2 未做**（后续阶段）：屏蔽词、B站 gRPC。
顶栏「弹幕」槽位与「更多→弹幕」进入弹幕二级界面（`implemented=true`）。

**网络弹幕 / 自动匹配 / 弹幕服务器（阶段3）**：

| 层 | 文件 | 职责 |
|---|---|---|
| 数据模型 | `models/danmaku_server.dart` / `dandan_models.dart` / `danmaku_auto_match_cache.dart` | 服务器配置 / API DTO（番剧·集·评论·匹配）/ 切集自动匹配缓存 |
| 纯函数 | `utils/dandan_signature.dart` / `dandan_comment.dart` / `danmaku_episode.dart` | 签名 `base64(sha256(AppId+Timestamp+Path+AppSecret))` / 评论→条目 / 文件名集数提取+匹配 |
| API | `services/dandan_play_api.dart` | 签名验证模式：`/api/v2/search/episodes`、`/api/v2/comment/{id}?withRelated=true`、`/api/v2/match`（响应按 UTF-8 解码，非 200/业务错误抛 `DandanApiException`） |
| 网络业务 | `services/danmaku_network_service.dart` | 搜索合并（按 animeId 去重 + 记录来源服务器）、文件匹配合并、下载落盘 `filesDir/danmaku/network/`、文件前 16MB MD5 |
| 设置 | `services/danmaku_server_settings.dart` / `danmaku_search_history.dart` / `danmaku_auto_match_cache_store.dart` | 服务器增删启停 + 切集自动匹配开关（含与默认服务器的互斥裁决与提示文案）/ 搜索历史（上限淘汰最旧）/ 匹配缓存 |
| UI | `views/player_danmaku_network_panel.dart` | 网络弹幕三级界面：40dp 胶囊搜索框 + 框下关键词历史胶囊 + 命中后折叠搜索条 + 结果卡自持动画展开集列表 |
| 设置页 | `pages/settings/danmaku_server_page.dart` | 设置 → 弹幕 → 弹幕服务器（默认不可删 + 自建增删启停 + FAB 添加） |

**关键决策**：
- **密钥私有**：`AppId/AppSecret` 存 `services/dandan_play_keys.dart`（已 gitignore，禁止提交
  GitHub；工作.md 第 3 点，优先用 AppSecret2）。签名验证模式比凭证模式更安全（AppSecret
  不随每次请求外发）。
- **网络弹幕持久化（工作.md 第 2 点）**：无论本地导入 / 自动匹配 / 手动搜索下载，成功
  装载过一次即**落盘 + 记忆**——`DanmakuController.loadNetworkDanmaku`（及切集自动匹配）
  拉取评论后生成 B站 XML 落盘 `filesDir/danmaku/network/<番剧>_<集>_<episodeId>.xml`
  并写入 `DanmakuManualMemory`（视频路径 → 文件路径）。`loadForVideo` 第 1 步的记忆恢复
  **与切集自动匹配开关无关**；切集自动匹配开关只门控「新视频（无记忆）自动匹配下一集」。
- **toast 语义（工作.md 第 3 点）**：「已自动加载弹幕：文件名」只在**同名自动查找**路径
  触发（且每视频仅第一次，持久化去重）；记忆恢复一律**静默**（记忆里既有手动导入也有
  网络弹幕，恢复时不能误报「自动加载」）。网络弹幕显式加载经 `onNetworkDanmakuLoaded`
  弹「已加载弹幕：番剧 · 集」。
- **切集自动匹配（工作.md 第 7 点）**：`loadForVideo` 本地同名无匹配后，若
  `DanmakuServerSettings.autoMatchEnabled` 且存在 `DanmakuAutoMatchCache`，按
  `extractEpisodeNumber(文件名)` → `findMatchingEpisode(缓存集列表)` 定位对应集并下载；
  缓存由「自动匹配命中 / 网络搜索选中」写入（自动匹配命中后异步 `searchAnime` 取回
  完整集列表再存）；装载成功同样落盘记忆，该视频之后再进直接走记忆恢复。
- **自动匹配按钮**：`matchCurrentVideo` 算前 16MB MD5 + 文件名 + 大小 → 合并启用服务器
  候选；单候选直接加载，多候选 `showAppDialog` 弹「选择匹配结果」列表。
- **搜索 UI 设计规范（本轮重设计，工作.md 网络弹幕 4 点）**：
  - **紧凑搜索框**：自绘 40dp 定高胶囊 + `InputDecoration.collapsed` + 28dp 迷你按钮
    （清空/搜索）。**禁止**回到 `TextField` 默认 `OutlineInputBorder` + `IconButton` suffix
    ——后者的 48dp 最小点击区会把输入框顶到 60dp+（原「搜索框太高」的根因）。
  - **关键词历史**：胶囊 `Wrap` 直接贴在搜索框下方（末尾一枚「清除」胶囊），**不独占分组
    卡片、无分组标签**；搜索框折叠时历史一并隐藏。
  - **命中即折叠**：搜到结果后搜索区收成 34dp 的「关键词 · N 部」胶囊条（点击重新展开，
    结果保留），把竖向空间全部让给结果列表；无结果/出错保持展开便于改词。竖屏另经
    `PlayerPanelPage.bottomHeightFactor: 0.82` 抬高底部外壳（§4.5）。
  - **展开/收起动画**：每张结果卡自持 `AnimationController`（进 320ms easeOutCubic /
    退 250ms easeInCubic），`Align(heightFactor)` 高度与内容 `FadeTransition` **错峰**
    （展开先长高后显形 `Interval(0.30,1)`、收起先淡出后收高 `Interval(0.55,1)`），
    箭头 `RotationTransition` 共用同一曲线；完全收起时子树不构建、展开时卡头
    `Scrollable.ensureVisible` 顶到可视区；集数 > 6 时集列表落在 264dp 定高滚动容器
    （动画期间布局量恒定）。手风琴式，同时只展开一个。
- **切集自动匹配与默认服务器互斥（工作.md 第 7 点，收尾阶段已恢复）**：启用默认
  弹弹Play 服务器时**不允许**开启「切集自动匹配」。互斥**只在服务层裁决一处**
  （`DanmakuServerSettings`），防 UI 与运行时各判一次而漂移：
  - `autoMatchEnabled` = 唯一生效值（默认服务器启用时恒 false），设置页与
    `DanmakuController._tryAutoMatch` 共用，运行时无需二次判断；
  - `autoMatchPreference` = 用户原始偏好（**不含**互斥判定）：启用默认服务器只是
    「暂时不生效」，停用后自动恢复用户选择，不静默丢偏好；
  - `autoMatchAllowed` 判定是否可开；文案**两级**且都在服务层（页面内不写文案
    字面量）：`autoMatchBlockedReason` = 短指引「请先停用弹弹Play 服务器」（副标题用，
    窄屏单行不挤）、`autoMatchBlockedMessage` = 含服务器名与开关名的完整说明
    （toast 用）；
  - `setAutoMatchEnabled` 返回 `bool`：被互斥拒绝时返回 false 且不写偏好；**关闭
    动作永远允许**。
  - UI（`danmaku_server_page.dart` 的 `_AutoMatchTile`）：禁用时 `onChanged: null`
    使 Switch 与整行变灰 + 副标题换成 error 色**短**原因，并盖一层
    `kAutoMatchBlockedTapKey` 透明命中层吞掉点击、弹**完整说明** toast
    （**变灰必须配文本提示**，否则用户以为是 bug）。

---

## 5. 新增功能指南（按功能类型）

### 5.1 新增一个页面

1. 建目录 `lib/pages/<name>/`，页面文件 `xxx_page.dart`（StatefulWidget）
2. 页面用 `Scaffold` + `AppBar`，body 用 `ListView`（安全区自动处理，不用管）
3. 需要排序弹窗 → `showSortOptionsSheet`；需要弹窗 → `showAppDialog`
4. 跳转：`Navigator.push(MaterialPageRoute(builder: ...))`
   - 如果是播放页：用 `playerPageRoute(page)`（`app_frame.dart`，无进出场动画 + 自动带 `RouteSettings(name: playerRouteName)`）
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
4. 播放器设置分组约定（`player_settings_page.dart`）：**手势**组 = 双击手势 + 快进/快退时长 + 音量/亮度灵敏度 + 长按倍速滑杆（**全部归为一张卡片**，项间 `Divider(height:1, indent:16, endIndent:16)` 分隔）；**视频方向**组 = 自动/锁定竖屏/锁定横屏（RadioTile 三选一）；**顶部信息**组 = 时间/电量/网速/数据类型（CheckboxTile 四项多选，默认全选，阶段1 第 1 点）；**播放行为**组 = 常驻进度线/进度条缩略图/记住上次倍速/保存音量到系统/双指缩小视频/按钮背景/自动连播/播放完毕自动退出/循环播放模式（RadioTile 三选一：关闭/列表循环/单集循环）/倍速播放指示器/启用播放界面动画（组内每项之间用 `Divider(height:1, indent:16, endIndent:16)` 分隔）；「已观看进度阈值」独立滑杆组（5% – 100%，步进 5%，默认 95%）
5. **播放器暗色面板里的强调色/滑杆必须跟随主题**：面板恒为暗色外壳，但强调色不得写死。
   统一用 `settings_ui.dart` 的 `playerPanelAccent(context)`（强调色）与
   `playerPanelSliderTheme(context)`（滑杆主题）——它们以当前 `ColorScheme.primary` 为 seed
   **派生暗色方案**再取 primary：浅色主题下直接用 `scheme.primary` 在暗底上偏暗、对比不足，
   派生后自动提亮到暗底可读色阶且保留用户色相；派生结果按 seed 缓存（`fromSeed` 每次都跑
   HCT 调色板计算，滑杆拖动时逐帧 build，无缓存会掉帧）。
   例外：语义色不跟随主题——字幕 RGBA 通道滑杆的 R/G/B/A 轨道色就是通道语义本身。

### 5.4 新增模型字段

- 改 `lib/models/` 下对应模型（纯数据），注意 `TreeNode` 是不可变类，重建时传完整参数

### 5.5 新增测试（必须有）

每个新逻辑都要配测试（见 §6），文件放 `test/`，命名 `<被测文件>_test.dart`。

### 5.6 文档维护（必须）

完成**重大功能新增 / 优化或 Bug 修复**后，必须在本文件（ARCHITECTURE.md）同步以下内容，再算收工：

1. **§2 目录结构**：新增/删除/移动的文件、目录必须反映到树形图（含一行注释说明职责）；
2. **受影响章节**：改到状态管理 → §4.1；新增弹窗 → §4.5；改播放页 → §5.1 / §4.3/4.4；缩略图/抓帧 → §4.9；新增设置 → §5.3；新增测试 → §6；
3. **§7 已知注意事项**：新踩的坑（环境 / 框架 / 设备）要补进表格，防止他人重蹈覆辙。

**文档写作约定（工作.md 第 1 点，必须遵守）**：
- **§7 注意事项必须精简**：每条只写「坑 + 防护」一句话，能用 30 字讲清不写 60 字；
  表格行数控制在必要范围内，禁止长篇展开论述；
- **§2 目录结构中每个 dart 文件都必须带 `# 一行简短描述`**：只说明「这个文件负责什么」
  （一句话），不写实现细节、不重复类名可推断的内容；
- 改完代码后，**文档中任何与代码不一致的路径、文件名、组件名都算违约**。小改动（如改文案、调样式）不强制，但涉及结构 / 接口 / 行为变化必须更新。

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
  - `test/player_controls_settings_test.dart` — 播放器控制设置（槽位增删/排序/上限/时长档位/倍速预设/按钮背景/进度条样式/长按倍速/灵敏度/保存音量到系统/指示器开关/首次提示/双指缩放/自动连播/自动退出/循环模式/已观看阈值 5% 档位/视频方向/播放界面动画开关/旧数据迁移；倍速不在顶栏动作之列）
  - `test/player_gestures_test.dart` — 双击手势三模式判定（含边界）+ 滑动手势数学（seek 灵敏度/音量·亮度增量/动态倍速档位与索引/最近档位）
  - `test/player_panel_test.dart` — 右侧面板打开/面板内导航不崩溃（**改 PlayerPanel 必须跑**）
  - `test/player_bottom_panel_test.dart` — 竖屏底部面板打开/面板内二级导航/返回/关闭不崩溃（**改 PlayerBottomPanel 必须跑**）
  - `test/player_speed_panel_test.dart` — 倍速面板（「我的预设」✕ 删除 / 「添加到预设」随滑杆联动）
  - `test/playback_completion_test.dart` — 播放完成 EOF 动作解析纯函数（单集循环→自动连播→列表循环→自动退出→自动暂停优先级链，含边界）
  - `test/playback_restore_test.dart` — 恢复进度阈值判定纯函数（<5% / ≥已观看阈值不恢复，边界与自定义阈值）
  - `test/audio_shuffle_test.dart` — 听视频随机播放算法（时间刻种子：结果范围/不重复当前曲目/同刻可复现/不同刻不同）
  - `test/playlist_sort_test.dart` — 播放列表 4 排序纯函数（名称/日期 × 升/降序，自然序/无日期垫底）+ 目录过滤（folderOfPath/filterVideosInFolder）
  - `test/pip_aspect_test.dart` — 画中画宽高比纯函数（gcd 约分/0.5–2.39 钳制/未知尺寸回退 16:9）
  - `test/portrait_player_bottom_bar_test.dart` — 竖屏底栏右侧按钮簇顺序（超分辨率→列表→倍速→选择屏幕，左到右）+ 弹幕按钮（进度条上方右下角、与章节名同行、开关随 danmakuOn 切换）
  - `test/thumbnail_cache_test.dart` — FFmpeg 帧缓存查询（peekFrame 精确秒桶/peekNearestFrame 邻近匹配/跨视频隔离）+ 32MB LRU 超限淘汰
  - `test/watch_state_test.dart` — 观看状态纯函数（未观看/观看中/已看完判定 + 自定义阈值 + 百分比）
  - `test/chapter_utils_test.dart` — 章节纯函数（标题关键词分类/片段派生过滤/当前章节定位/跳过目标 EOF 保护）
  - `test/chapter_tracker_test.dart` — 章节跟踪器（位置流驱动的章节推进/胶囊 5 秒窗口/回拖重复触发/跳过与跳转）
  - `test/intro_outro_skip_test.dart` — 片头片尾动作决策纯函数（前置守卫/片头触发/片尾触发/整集保护/片头优先）
  - `test/intro_outro_settings_test.dart` — 片头片尾设置服务（默认值/钳制/范围收窄联动/一键重置/持久化恢复）
  - `test/intro_outro_tracker_test.dart` — 片头片尾跟踪器（就绪门控/每集一次/越过即标记/恢复点感知/切集重置）
  - `test/intro_outro_panel_test.dart` — 片头片尾面板（开关展开/输入换算 mm:ss/滑杆/设为当前时间与剩余时间/一键重置）
  - `test/formatters_network_test.dart` — 网速格式化（KB/MB 自动切换两位小数）与在线媒体判定纯函数（阶段1 第 1 点）
  - `test/subtitle_track_test.dart` — 字幕轨道纯函数（展示名/ASS 样式判定/格式过滤/对齐/颜色 + RGBA↔mpv 颜色转换，阶段1 第 3 点）
  - `test/subtitle_settings_test.dart` — 字幕设置服务（默认值/延迟叠加与钳制/描边模式/外挂字幕记忆/字体源目录记忆/重置样式持久化）
  - `test/subtitle_auto_match_test.dart` — 同名字幕自动匹配纯函数（同名候选/扩展名优先级/完全同名优先/简繁语言后缀/短名优先/无匹配）
  - `test/subtitle_sort_test.dart` — 自建字幕选择器排序纯函数（目录恒在前/大小日期升降序）
  - `test/audio_track_test.dart` — 音轨纯函数（展示名/声道枚举/格式过滤/audio-channels 映射/af 滤镜链组装，工作.md 音频功能）
  - `test/danmaku_timeline_test.dart` — 弹幕时间轴错峰纯函数（同秒多条 1 秒内均分、<1000ms 上界）
  - `test/danmaku_local_file_test.dart` — 同名弹幕查找纯函数（9 种命名规则优先级/排除视频自身/无匹配）+ 选择器文件过滤
  - `test/danmaku_xml_test.dart` — B站 XML 弹幕解析（基础字段/实体反转义/坏条目跳过/排序）
  - `test/danmaku_scheduler_test.dart` — 弹幕调度器（秒桶前向补发/首 tick 锚定/seek 检测/代数失效/微幅回抖）
  - `test/player_danmaku_panel_test.dart` — 弹幕二级界面（四入口齐全/网络·自动匹配回调注入/设置回调注入/无平台通道不崩溃）
  - `test/danmaku_memory_test.dart` — 弹幕手动导入记忆（set/get/remove/持久化恢复/损坏数据防御）
  - `test/danmaku_settings_test.dart` — 弹幕设置服务（默认值/钳制/持久化恢复/越界收窄/恢复默认/通知）
  - `test/danmaku_random_color_test.dart` — 随机渐变色纯函数（HSV 转换/色相环绕/种子可复现/色轮均匀分布/高明度约束）
  - `test/danmaku_dedup_test.dart` — 弹幕去重纯函数（归一化判同/时间窗合并/链式推进/无序输入/原文保留）
  - `test/danmaku_episode_test.dart` — 弹幕集数提取/匹配纯函数（文件名各规则 + 集列表定位，切集自动匹配）
  - `test/dandan_signature_test.dart` — 弹弹Play 签名纯函数（官方示例 + 三条真实路径的**合成密钥**已知向量；⚠️ 禁止写入真实 AppId/AppSecret）
  - `test/dandan_comment_test.dart` — 弹弹Play 评论→弹幕条目/B站 XML（p 字段解析/容错/排序/XML 往返转义）
  - `test/dandan_models_test.dart` — 弹弹Play API 数据模型 fromJson（字段映射/容错）
  - `test/danmaku_server_test.dart` — 弹幕服务器模型（默认服务器/toJson/fromJson/copyWith）
  - `test/danmaku_server_settings_test.dart` — 弹幕服务器设置服务（默认/增删启停/自动匹配开关/**与默认服务器互斥**：拒绝开启+偏好保留+停用后恢复+关闭永远允许/持久化/损坏防御）
  - `test/danmaku_server_page_test.dart` — 弹幕服务器设置页（默认服务器启用时自动匹配开关变灰+副标题短原因+点击弹完整说明 toast；副标题显著短于 toast；停用后恢复可用；启用默认服务器即回落变灰）
  - `test/danmaku_search_history_test.dart` — 搜索历史（去重/上限淘汰最旧/清除/持久化/损坏防御）
  - `test/danmaku_auto_match_cache_test.dart` — 自动匹配缓存存储（保存/读回/清空/持久化/损坏防御）
  - `test/danmaku_network_service_test.dart` — 弹幕网络服务（文件名清洗/搜索合并去重来源/下载落盘可回读/落盘失败降级）
  - `test/player_danmaku_network_panel_test.dart` — 网络弹幕搜索面板（40dp 搜索框定高/框下历史胶囊+清除/命中折叠与重新展开/结果卡收起态不构建子树+手风琴/选集回调+关闭面板）
  - `test/player_danmaku_settings_panel_test.dart` — 弹幕设置面板（两段式布局/开关滑杆实时写设置/恢复默认/读数联动）
  - `test/player_panel_theme_test.dart` — 播放器暗色面板强调色跟随主题（换主题色滑杆轨道/拇指随之改变且不等于旧写死蓝 0xFF4FC3F7；保留无气泡外观；浅色主题下派生色更亮；同 seed 复用缓存实例）
  - `test/subtitle_file_picker_panel_test.dart` — 自建选择器面板（记忆文件夹被删向上回退/空目录正常落地/导航失败维持原状/选择回调+文件夹记忆）
- 改以下代码必须跑对应测试：`AppFrame`、`ViewSettings` 排序、权限流程、`CapsuleNavBar`

---

## 7. 已知注意事项（踩过的坑）

> 文档约定（工作.md 第 1 点）：**本表必须精简**——每条只写「坑 → 防护」一句话，
> 不展开论述；新坑补一行即可。

| 坑 | 防护 |
|---|---|
| 挖孔屏横屏白条 / 系统栏露浅色背景 | AppFrame `left/right` 恒 false + 播放页豁免 bottom + ColoredBox 铺色（§4.2） |
| 播放页退出闪烁/黑屏（错向界面 ~1s 或退出黑一下） | 退出**同一帧 `pause()` 冻结末帧**（不再先 dispose 黑屏渐隐）+ IO `unawaited` + 无动画瞬时 pop；竖屏退出下层 `_exitBlackout` 黑化（§4.4） |
| 面板红底黄字崩溃（No Material） | PlayerPanel / PlayerBottomPanel 外壳必须用 `Material`，勿换 Container；拖拽 `proxyDecorator` 也用 `Material`（`ColoredBox` 非 Material，拖拽时 proxy 被放 overlay 脱离外壳会崩）（§4.5） |
| 面板内 `Navigator.of` 断言 scope==null | 内容先包 `Builder` 取面板树内 context 再调 `of`（§4.5） |
| 全局 ValueNotifier hack 引发连锁补丁 | 禁止；跨页面用 ChangeNotifier / 路由机制（§4.1） |
| DSH 沙箱卡住 flutter/dart 子进程 | `flutter analyze/test` 必须 danger-full-access 执行；勿用 `flutter --version` 探路 |
| mpv 着色器要绝对路径 / 切集后失效 | 拷贝 assets 到应用目录拼绝对路径；open 后与切集后都 `apply(player)` |
| 均衡器与声道/处理共享同一 `af` 属性 | 均衡器命名滤镜（`@eq/@bass/@virt`）统一由 `buildAudioFilterChain` 拼进 `af` 属性串、由 `applyAudioOptions` 一次性 `setProperty('af')`，勿另用 `af add`（会被整体覆盖）；「启用均衡器」开关同时门控低音增强与虚拟环绕（关时传 0，但存储值保留） |
| EOF 防重入（切集瞬间残留事件） | `_isSwitchingVideo` + `_isHandlingEndOfFile` 双标志 + 位置到结尾校验 + 纯函数 `resolveEndOfFileAction` |
| `Media(start:)` 失效（media_kit 1.2.x on_load hook 读到 playlist-pos=-1 跳过 start） | 弃用；恢复统一走 `openAndRestore`（`utils/playback_restore.dart`）。⚠️ v5.2 曾试 `open` 前 `setProperty('start')` 加载期定位，实测恢复失效，已还原 v5.1 |
| 恢复进度"从头播"（暂停态 seek 只改 time-pos、不改解码器，指示器跳但视频从头） | `openAndRestore`：`open(play:false)` 暂停加载 → 等时长 → **静音 `play()` 激活时间线** → 等位置推进 ≥150ms → `seek` → 位置流确认（重试一次）→ 位置**越过恢复点一 tick**（目标帧已上屏）才揭开不透明封层 → 取消静音 |
| 恢复进度"跳到又跳回 / 读取竞态" | `PlaybackProgressService` ensureLoaded（读盘完成后再置 `_loaded`）+ `_writeChain` 串行写盘 + 退出/切集 `save(forcePersist:true)` |
| 恢复进度指示器残留/不显示 | 只有 `openAndRestore` 返回 true 才显示；2.5s 自隐藏；竖屏/锁定竖屏由 `initialResumeVisible` 接住 |
| 已看完视频恢复后立即 EOF 连播 | `_resumeStartFor` 阈值过滤（<5% 或 ≥已观看阈值 → 不恢复从头播） |
| 循环播放无限恢复已看完视频 | `shouldRestorePosition`：<5% 或 ≥已观看阈值不恢复 |
| 横竖屏切换卡顿/黑屏/音频断 | v3：共享同一 Player/VideoController，竖屏页只换布局不重开；EOF 由当前栈顶页处理 |
| 竖屏返回不能直接退出 / 退出露横屏页 | 竖屏返回走 `_backExit` → `_exitWithPortrait`（先 `_exitBlackout` 黑化下层 → `pause()` → IO unawaited → 连 pop 竖屏页 + 横屏页，下层纯黑防「两个竖屏界面」复现）；「选择屏幕」仍仅回横屏 |
| 竖屏锁定不生效 | 手势层传 `locked`，各手势回调补 `if (_locked) return` |
| 手机竖拍视频仍横屏播放（自动方向） | 竖屏判定结合 `VideoParams.rotate`（90/270 时宽高互换，参考 KT：`video-params/aspect` + rotate 修正）；⚠️ 用**原始 w/h**（`videoParams.w/h`）而非 `state.width/height`（后者已被 media_kit 按 rotate 交换成显示尺寸，再套 rotate 会双重交换误判） |
| 画面比例不实时生效 | Video 外包 `ListenableBuilder(listenable: 设置)`；⚠️ 4:3→自动失效根因：media_kit `VideoViewParameters.copyWith(aspectRatio: null)` 保留旧值 → Video 加 `key: ValueKey(fit.index)` 强制重建 |
| 音量手势被系统音量封顶 | v3：手势直控系统媒体音量，mpv 音量固定 100；退出按「保存到系统」写回/恢复 |
| 窗口亮度泄漏到列表页 | 退出双重恢复 `setWindowBrightness(null)`（原生 -1 交还系统） |
| Material Slider 轨道起点无法对齐 | 自绘进度条 `player_seek_bar.dart`，起点精确落 `kPlayerLeftInset`，勿改回 Slider |
| 播放页整页随位置流高频重建 | 位置/时长抽页面级 `ValueNotifier`，底栏/进度线 `Listenable.merge` 局部订阅（§4.1） |
| 快速退出→进入刷假崩溃日志 | `_disposed` 标志 + 每个 await 后查 disposed/mounted + `openAndRestore`/`_openAndSetRate` 等 `on AssertionError` 兜底静默返回 |
| 播放进度表每次全量序列化 | `save` 30s 节流 + `_writeChain` 串行化 |
| 设置单例 load 竞态 | `ensureLoaded()` + 全部 setter 首行 await（risk_audit #9） |
| 播放界面动画无法关闭 | 「启用播放界面动画」设置：动画控制器时长归零 / `animate=false` 零时长转场 |
| MethodChannel 小整数是 Integer 非 Long | 取整型参数一律 `call.argument<Number>()?.toLong()/toInt()` |
| MediaMetadataRetriever 取帧不可靠 | 仅剩列表封面用（`getVideoInfo`）：SYNC/CLOSEST 独立 try/catch；进度条抓帧已换 FFmpeg 引擎（§4.9） |
| 缩略图缓存无限增长 / 体积大 | 进度条缩略图=纯内存 LRU 32MB（RGBA 字节计，播放页退出清空，无磁盘）；列表封面 384×216+q70 磁盘缓存由缓存管理页清理 |
| libmpv hidden visibility 吞掉新增符号 | 内核新导出函数必须经 `client.h` 的 `MPV_EXPORT` 声明携带可见性（.c 里 include client.h） |
| `Isolate.run` 闭包捕获 Completer → unsendable 崩 | `Isolate.run` 放**独立静态函数**、只捕获原始值；同作用域兄弟闭包捕获的对象会被编译器合并进上下文一起发送 |
| Flutter 插件统一构建目录（build/<插件名>）残留旧 jar | 官方下载式 libs 包改本地分发时，`fileTree` 直接指向 `android/jars/` 源目录，勿用「下载→复制到 build/output」模式（assemble 钩子不保证执行 + Gradle 9 隐式依赖校验报错） |
| media_kit seek 落最近关键帧（与预览帧对不上） | 播放器初始化设 mpv `hr-seek=absolute`（对齐 mpvRx 的 `seek absolute+exact`） |
| 松手后缩略图气泡不消失（要点屏才走） | 改变挂载条件的状态必须 `setState`；现走显式 `visible` 标志 + 定时器淡出后卸载 |
| 列表首屏并发拉元数据 | `VideoInfoService` 在飞去重（同 path 共享 Future） |
| 听视频共享 Player 语义 | 听视频页不建播放器/不恢复进度；切歌从 0 开始、切走前保存进度；EOF 由听视频页处理（播放页 `_audioActive` 让位）；循环三态：关闭/单曲/列表（点击循环按钮切换） |
| 听视频退后台自动暂停 | 阶段1 第 2 点：进入听视频启动前台服务（`BackgroundPlaybackService`，mediaPlayback 类型）保活进程，mpv 音频在后台继续播放；退出听视频停服务；前台服务仅保活不带媒体控制 |
| 外挂字幕 content:// 无法直接给 libmpv | `sub-add` 前先由原生侧拷贝到 `filesDir/subtitles/`（`copySubtitleFromUri`）；自建选择器直接返回文件真实路径 |
| 字幕切集后消失/勾选丢失 | `SubtitleController.reapplyForMedia` 按媒体路径去重后重新 `sub-add` 全部外挂字幕，并按 `external-filename`（源路径）恢复主/次勾选（轨道 id 重开会变） |
| 内嵌 ASS 字幕被强制换样式 | 默认 `sub-ass-override=no`（尊重自带样式字体）；开启「强制覆盖内嵌样式」才 `force`；主字幕为文本格式时用户样式恒生效 |
| 字幕面板在横竖屏外壳下导航器类不同 | 面板二级页推页由页面注入回调（横屏传 `PlayerPanelNavigator`、竖屏传 `PlayerBottomPanelNavigator`），面板不直接依赖外壳（§4.5 Builder 约定） |
| 听视频随机播放 | 纯函数 `audioShuffleNextIndex`：当前时刻折叠种子 + 乘性散列，不重复当前曲目（可单测） |
| 播放页顶部信息行 | 原生 `getBatteryLevel`/`getNetworkType`；时间 30s/电量 60s/网络类型 5s 刷新；四样多选（时间/电量/网速/数据类型，默认全选）；勾了时间或电量 → 时间电量居中、网速+数据类型靠右，否则网速+数据类型居中；网速胶囊仅在线播放显示（本地一律隐藏，`isOnlineMedia`）；渐变由播放页统一包「信息行+顶栏」一个连续渐变（勿各画各的，防断层）；竖屏压缩高度 |
| 许可证书页 | 折叠式改为列表 + 二级详情页（可复制），不用 ExpansionTile |
| 画中画进出检测 / 宽高比 | 用 `didChangeAppLifecycleState` 判断进出 PiP；`pipAspectRatio` 约分 + 0.5–2.39 钳制 |
| 超分 UI 不刷新 / 看不出效果 | 面板用 `ValueNotifier` 实时刷新；720p 以下动漫 + 激进档位测试 |
| 截图保存 / 右侧按钮背景 | `Player.screenshot` + `saver_gallery`；右侧截图/锁定固定灰黑底，不受按钮背景设置控制 |
| 全面屏手势误触 / 双指捏合误触发滑动 | 手势层死区（垂直上下 8%、水平右 8%）+ 方向确认延迟 80ms + `onSwipeCancel` 撤销 |
| 滑杆刻度过密被跳过 | `DenseSliderTickMarkShape` 声明极小宽度通过密度检查 |
| 播放器面板滑杆/强调色写死 `Color(0xFF4FC3F7)`（模块级 `ColorScheme.fromSeed` 常量），换主题色不跟随 | 改用 `playerPanelSliderTheme(context)` / `playerPanelAccent(context)`；模块级 `final` 派生的方案在首次加载时即固化，**不会**随主题重建（§5.3 第 5 条） |
| 暗色面板直接用 `Theme.of(context).colorScheme.primary` 作强调色 | 浅色主题下该色在暗底上偏暗、对比不足；必须以它为 seed 派生 `Brightness.dark` 方案后再取 primary |
| 自动亮度读不到实时亮度 | 进入播放把系统值应用到窗口，退出恢复 -1 |
| 崩溃日志无限累积 | 上限 50 条 / 10MB，读写后裁剪 |
| 关于页跳转邮件/GitHub | AndroidManifest 声明 `mailto`/`https` `<queries>` |
| 播放进度恢复重启后失效 | 恢复前 ensureLoaded；`save` 前等待加载完成 |
| 排序字段胶囊 | 排序弹窗字段选择用胶囊样式（选中主题色填充），与倍速面板视觉一致 |
| 三大金刚键遮挡 / AppBar 滚动变色 | AppFrame 全局 bottom 安全区；`app_theme.dart` 统一 `scrolledUnderElevation: 0` |
| 类成员与导入纯函数同名被解析成成员（chapter 的 `currentChapterIndex`） | 纯函数 import 加 `as` 别名（`chapter_utils.currentChapterIndex`） |
| mpv 章节子属性返回字符串、平台可能为 null | `NativePlayer.getProperty('chapter-list/$i/title'…)` 自行 parse；非 NativePlayer 静默无章节 |
| 底栏/控制组件错位跑到屏幕顶部 | Stack 非 Positioned 子项默认 topLeft 摆放：底栏等固定定位组件必须包 `Positioned(left/right/bottom)` |
| Stack 条件子项插入/移出导致无 key 兄弟错位重建（指示器动画重播） | 条件渲染的 Stack 子项（如缩略图气泡）前的有状态组件加稳定 key（`ValueKey`），防按索引错位丢 State |
| media_kit 默认 `libass:false` → mpv `sub-visibility=no`，无 SubtitleView 时字幕完全不渲染 | 播放器 `PlayerConfiguration(libass: true)` 走原生 libass 字幕管线（`player_page.dart`）；默认 `sub-fonts-dir=/system/fonts` + `sub-font=Noto Sans CJK SC`，自定义字体走 §4.10 |
| Android libass 字体解析 | 默认 `sub-fonts-dir=/system/fonts` 直通系统字库；自定义字体在 mpv_initialize 前注入 + truetypeparser 解析族名 + 复制系统字库兜底（§4.10） |
| mpv 颜色 8 位为 `#AARRGGBB`（alpha 在前），6 位 = 不透明 | `rgbaToMpvColor`/`mpvColorToRgba`（`subtitle_track.dart`）统一转换，alpha==255 输出 6 位保兼容 |
| 打开视频后 ASS 内嵌字幕被强制覆盖样式（需切轨道才恢复原生样式） | 选中态与 mpv 实际 `sid` 同步（`reload`/`_syncActiveFromMpv`），样式策略按真实轨道判断，首帧即生效 |
| 主/次字幕功能乱且难维护 | 改单选模型（只设 `sid`）：轨道点击两态循环 选中↔关闭；移除 secondary-sid 全部逻辑 |
| 导入的外挂字幕退出播放后丢失 | `SubtitleSettings` 记忆路径列表（SharedPreferences），`SubtitleController` 构造时恢复、`reapply` 时以 `sub-add auto` 重挂（按视频独立隔离存储） |
| 重置延迟/样式不生效（apply 竞态） | 先 await 设置变更、后 await `applyAllSettings()`，禁止同一事件内不等待的并行修改 |
| 自定义字体运行时 `setProperty('sub-fonts-dir')` → libass 字体缓存打坏、字幕消失 | `sub-fonts-dir` 只在 mpv_initialize 前注入（media_kit 魔改字段）；运行时只允许改 `sub-font`/`sub-ass-override`（§4.10） |
| 手写 sfnt name 表解析器读到错误 offset（族名解析成文件名） | 族名解析用 `truetypeparser` 库，勿手写 name 表字节解析（§4.10） |
| 系统字库兜底用 symlink+隐藏文件名 → fontconfig 不识别 → 缺字空白 | 兜底字库直接复制成普通文件名（§4.10） |
| media_kit 本地 fork 被 `pub upgrade` 覆盖 | `third_party/media_kit` 的魔改需手动 merge；升级前先备份 diff（§4.10） |
| SAF 目录选择器重启后 tree uri 失效、无法刷新字体 | `takePersistableUriPermission` + `FLAG_GRANT_PERSISTABLE_URI_PERMISSION`/`FLAG_GRANT_PREFIX_URI_PERMISSION`（§4.10） |
| 反向立体声直接写 `audio-channels` 无效（mpv 无该布局值） | 反向立体声改走 `af` 滤镜 `pan=[stereo|c0=c1|c1=c0]`，并把 `audio-channels` 重置为 `auto-safe`（`buildAudioFilterChain`/`audioChannelsPropertyValue`） |
| 外部音轨/字幕 content:// 无法直接给 libmpv | `audio-add`/`sub-add` 前由原生侧拷贝到 `filesDir/audio|subtitles/`（`copyAudioFromUri`/`copySubtitleFromUri`）；自建选择器直接返回真实路径 |
| 横竖屏页各挂一个 DanmakuScreen，只保存单个渲染层引用会在返回横屏时失联（`createdController` 仅在挂载时回调一次，pop 不重触发） | 业务层用渲染层 registry 同步驱动全部已挂载层，挂载/卸载走 `attachLayer`/`detachLayer`（§4.11） |
| 横屏底栏 Expanded 内放固定尺寸按钮，分屏/自由窗口把横屏页压到 ~390dp 时 RenderFlex 溢出 | 弹幕按钮组包 `Flexible` + `FittedBox(scaleDown)`（常规宽度原尺寸，极窄等比缩小）；新增固定按钮一律照此兜底 |
| 选择器记忆文件夹在系统侧被删除后，打开停在死路径（列表空白、看似卡死，小喵 player 实际踩坑） | `listDirectory` 目录不可用返回 null（区别空目录）；打开时向上回退最近存活祖先；导航失败维持原状（§4.11） |
| 弹幕显示区域滑到 0 时 canvas 轨道数为 0（无弹幕可画） | 区域滑杆下限 0.1；「弹幕速度」语义 = 横穿屏幕耗时秒（越小越快），静置弹幕取其一半（canvas staticDuration 与 duration 无关联） |
| 弹弹Play `AppSecret` 硬编码进源码会被上传 GitHub 泄露 | 密钥存 `lib/services/dandan_play_keys.dart` 并加入 .gitignore（工作.md 第 3 点，私有禁止提交） |
| 真实密钥经**测试文件**绕过 .gitignore 泄露（签名测试写死 AppId/AppSecret 生成已知向量） | 测试一律用合成凭据（`dandan_signature_test.dart` 的 `_testAppId/_testAppSecret`）；提交前 `git diff --cached` 扫一遍 secret 字面量 |
| 互斥限制在 UI 与运行时各判一次 → 两处漂移（开关看着关着却仍在自动匹配） | 互斥只在 `DanmakuServerSettings` 裁决：`autoMatchEnabled` 为唯一生效值，UI 与 `_tryAutoMatch` 共用；偏好另存 `autoMatchPreference` 不被擦除（§4.11） |
| 开关变灰但不说明原因 → 用户当成 bug | 变灰必须同时把副标题换成 error 色原因 + 盖透明命中层点击弹 toast；文案两级都在服务层（副标题短句 `autoMatchBlockedReason` / toast 完整 `autoMatchBlockedMessage`），页面内不写字面量（§4.11） |
| 副标题写整句解释 → 窄屏挤成两行 | 副标题只放短指引（≤15 字），完整解释交给 toast；⚠️ 别用像素高度断言行数——测试字体 Ahem 每字形等宽方块，把中文行宽算得远大于真实 CJK 字体，应断言字符数等字体无关量 |
| Dart `http` 响应体缺 charset 时按 latin1 解码，中文乱码 | 统一 `utf8.decode(response.bodyBytes)`，不依赖 `Response.body`（§4.11 `dandan_play_api.dart`） |
| 网络弹幕/自动匹配只存内存，重启播放/软件即丢（切集自动匹配与装载逻辑混在一起） | 成功装载即生成 B站 XML 落盘 `filesDir/danmaku/network/` 并写入 `DanmakuManualMemory`；`loadForVideo` 记忆恢复与开关无关（§4.11） |
| 手动导入/网络弹幕重启后被当「自动加载」重复弹 toast | 「已自动加载」toast 只挂在同名自动查找路径（且每视频仅第一次）；记忆恢复一律静默（§4.11） |
| 面板内搜索框被撑到 60dp+（`IconButton` suffix 的 48dp 最小点击区 + `OutlineInputBorder` 内边距） | 自绘 40dp 定高胶囊 + `InputDecoration.collapsed` + 28dp 迷你按钮（§4.11 搜索 UI 规范） |
| `AnimatedAlign(heightFactor)` 展开动画生硬（内容被裁边挤压、长列表反复布局） | 卡片自持 `AnimationController`：高度与内容淡入淡出 `Interval` 错峰 + 收起态不构建子树 + 超 6 集用定高滚动容器（§4.11） |
