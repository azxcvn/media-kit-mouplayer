# 设计参考报告（t1：参考项目深度研究）

> 任务：按「参考项目/工作.md」20 项要求，为 moumou v2 的 8 个主题整理设计参考。
> 本文只做**研究参考**，不修改任何 `lib/` 代码。工程师实现时以本文为起点，结合
> `ARCHITECTURE.md`（架构契约）与「参考项目」原文核对细节。
>
> 参考项目速览：
> - `参考项目/src/` — fam4k007 小牛播放器（Kotlin/Compose + mpv），**与需求同源**，8 个主题的主参考
> - `参考项目/Kazumi-main/` — Flutter + media_kit + audio_service，**与本项目同技术栈**（PiP/听视频的最佳 Flutter 参考）
> - `参考项目/PiliPlus-main/` — Flutter，设置体系/排序弹窗/拖拽排序（ReorderableListView 高亮修复参考）
> - `参考项目/mpvRx-master/` — Kotlin mpv 播放器，src 的"百分百复用 mpvEx"算法源头（本文不重复展开，src 已含同算法）

---

## 主题 1：恢复上次播放进度 + 指示器

### 关键 API / 参考文件

| 参考 | 文件 | 要点 |
|---|---|---|
| 恢复判定 + 显示时机 | `参考项目/src/main/java/com/fam4k007/videoplayer/VideoPlayerActivity+Playback.kt` L23–60 `loadVideo()` | `position = duration<30s ? 0 : savedPosition`；**`position > 5.0` 才 `showResumeToast()`**（避免几秒的进度也弹提示） |
| 指示器 UI | `参考项目/src/main/java/com/fam4k007/videoplayer/ui/player/PlayerControlsCompose.kt` L1331–1418 `ResumeProgressToast` | 黑色圆角胶囊 `Color.Black.copy(alpha=0.72)`；内容「已为您恢复至 MM:SS」+「重新开始」（主题色可点）+「✕」（关闭）；`LaunchedEffect(visible){ delay(5000); hide() }` 自动隐藏；`fadeIn(250)+slideInHorizontally(300)` 进出场 |
| 状态 | `参考项目/src/main/java/com/fam4k007/videoplayer/presentation/PlayerViewModel.kt` L842–847, L1875–1881 | `savedPosition` / `resumeToastVisible` StateFlow + `showResumeToast()/hideResumeToast()`；另有 `hasRestoredPosition`/`hasShownPrompt` 标志（一次会话只提示一次） |
| 恢复执行 | `参考项目/src/main/java/com/fam4k007/videoplayer/VideoPlayerActivity+Playback.kt` L219–221 | Intent 带 `lastPosition` → `setLastPlaybackPosition`；`playbackEngine.loadVideo(uri, position)` 直接带起始位置 |

### 本项目现状（直接可用）
- `lib/services/playback_progress_service.dart`：**已经按视频 path 单独记忆 ms**（`Map<String,int>` + shared_preferences + ChangeNotifier），无需新造记忆机制。
- `lib/utils/watch_state.dart`：已观看/观看中/已看完判定（含阈值），列表页进度显示已有。
- 播放页 `lib/pages/player/player_page.dart`：进入时已有 `getProgress(path)` 恢复逻辑（实现时确认）。

### 借鉴点
1. 阈值防打扰：短视频（<30s）不恢复；保存进度 >5s 才弹指示器。
2. 指示器按用户需求改文案与位置：**横屏顶部弹出**（src 是左下角，本项目按要求改为顶部），文案「已恢复上次播放进度｜重头开始（可点）｜关闭（红色可点）」，重头开始 → `seek(0)` 并隐藏；关闭 → 仅隐藏（本次不再显示）。
3. 5 秒自动隐藏：用 Timer/`Future.delayed`，点击时先 cancel 再隐藏（防残留）。
4. 指示器独立于控制层显隐（不随单击显隐控制层而消失）。

### 坑
- 先 seek 再显示指示器，避免"提示了但进度没恢复"。
- 隐藏计时器在 dispose/切集时要清理。
- 恢复后的进度必须**回写**（继续播放后覆盖旧值），否则每次进都弹。
- 指示器 z 序放最顶层（Stack 最后），横屏下避让顶栏标题/槽位。

---

## 主题 2：自动连播 / 自动退出 / 循环播放 / 重复播放

### 关键 API / 参考文件

| 参考 | 文件 | 要点 |
|---|---|---|
| 播完处理（核心算法） | `参考项目/src/main/java/com/fam4k007/videoplayer/VideoPlayerActivity.kt` L1420–1497 `handleEndOfFile()` | 优先级：①单集循环（`RepeatMode.ONE`）→ `seek 0 absolute` + 取消暂停 + `resetEofDetection()`；②有下一集且自动连播 → `savePlaybackStateAsCompleted()` + `playNext()`；③列表循环（`RepeatMode.ALL`）无下一集 → 回到第 0 集（shuffle 则重新生成乱序）；④`closeAfterEOF` → `finishAndRemoveTask()`；⑤否则停住不动 |
| 防重入 | 同上 L1426–1432 | `isSwitchingVideo || isHandlingEndOfFile` 时忽略 END_FILE（切集时旧文件会触发 EOF，必须防） |
| 循环模式状态 | `参考项目/src/main/java/com/fam4k007/videoplayer/presentation/PlayerViewModel.kt` L32–37, L251–296, L1782–1806 | `RepeatMode { OFF, ONE, ALL }`；`cycleRepeatMode()`：OFF→ONE→(有播放列表时 ALL)→OFF；`shouldRepeatCurrentFile()/shouldRepeatPlaylist()`；`hasNext/hasPrevious` 用 `combine(index, list, repeatMode)` 计算（ALL 时恒有） |
| 设置默认值 | `参考项目/src/main/java/com/fam4k007/videoplayer/preferences/PreferencesManager.kt` L1747–1766 | `autoplay_next_video` 默认 **true**；`close_after_eof` 默认 **true** |
| 设置项 UI | `参考项目/src/main/java/com/fam4k007/videoplayer/ui/screens/PlaybackSettingsScreen.kt` L145–146 | Switch：开启="当前视频结束后自动播放下一个视频"；关闭="播放完当前视频后停止" |
| 系列识别/连播列表 | `参考项目/src/main/java/com/fam4k007/videoplayer/domain/player/SeriesManager.kt` | 文件名剥离 `[...]`/`(...)`/分辨率/编码 → 匹配集数模式（`S01E02`、`第X集`、`[02]`、`(02)`、`_02_`、` 02 `）→ 同名系列归组 → **自然排序** → 去重 → 系列只匹配 1 个时**回退为整个文件夹** |
| 播放列表生成 | `参考项目/src/main/java/com/fam4k007/videoplayer/VideoPlayerActivity.kt` L1503+ `generatePlaylistFromFolder` | 同目录视频扩展名过滤 + 排除 `.` 隐藏文件 + 自然序排序 |
| 自动连播语义 | `参考项目/src/main/java/com/fam4k007/videoplayer/VideoPlayerActivity.kt` L1461–1462 | **`RepeatMode.ALL` 时强制自动连播，不受开关影响** |

### 借鉴点（映射到 Flutter / media_kit）
1. 播完事件：media_kit `player.stream.completed` → 走 `handleEndOfFile` 同款优先级链。
2. 循环三态 + 切循环顺序：OFF→ONE→ALL→OFF；`RepeatMode.ALL` 时"下一集"按钮恒可用、播完强制连播。
3. 自动退出：检测到最后一个是本文件夹最后一个 → 播完直接退出播放页（`Navigator.pop`）。
4. 开关默认开、放「播放行为」组（`lib/pages/settings/player_settings_page.dart` 已有该组，直接加 Switch）。
5. 连播列表 = 当前文件夹视频（复用现有 `VideoScanner`/播放页已传的 `playlist` 参数；`PlayerPage.playlist` 已存在，仅需在播完时推进索引）。

### 坑
- **EOF 防重入**是 src 踩过的大坑：mpv 加载新文件会对旧文件发 END_FILE，Flutter 侧同样要用"切换中"标志挡掉 completed 事件。
- 切集前必须 `PlaybackProgressService.save` 当前进度 + 标记该集已完成（工作.md 第 8 点：任何切换路径都要记忆）。
- 切集后要重新应用超分着色器（`ARCHITECTURE.md` §7 已记录的坑：mpv 打开新文件需重设 glsl-shaders）。
- 自动退出用 `finishAndRemoveTask`（src）；Flutter 是 pop 播放页路由，注意 `AppFrameObserver`/`_exitPlayer` 的既有退出流程（保存进度→恢复竖屏→pop），别绕开。

---

## 主题 3：播放列表面板 + 4 排序胶囊

### 关键 API / 参考文件

| 参考 | 文件 | 要点 |
|---|---|---|
| 播放列表面板（右侧抽屉） | `参考项目/src/main/java/com/fam4k007/videoplayer/manager/compose/VideoListDrawer.kt`（644 行） | 320dp 右抽屉，半透明渐变背景；标题「视频列表」+ 排序按钮 + ✕；`LazyColumn` 列表项 = 序号 + 文件名 + 「播放中」高亮（蓝底/蓝边）+ 时长/大小；点击 → 延迟 200ms 切换 + 关闭；**排序改变或切集后 `animateScrollToItem(currentIndex)` 滚动到当前项**；排序设置持久化到 SharedPreferences |
| 排序模型 | 同上 L40–53 | `SortBy { NAME, SIZE, DURATION, DATE }` × `SortOrder { ASCENDING, DESCENDING }`；排序后 `indexOfFirst { it.uri == currentVideoUri }` 定位当前项 |
| 排序算法 | `参考项目/src/main/java/com/fam4k007/videoplayer/utils/NaturalOrderComparator.kt` | 自然序（数字感知） |
| 本项目已有 | `lib/services/view_settings.dart` L219 `sortVideos`（`VideoSortField.name/date/...` × `SortOrder`，名称用 `naturalCompare`）；`lib/widgets/player_option_chip.dart`（面板胶囊）；`lib/widgets/options_sheet.dart`（三行胶囊布局先例）；`lib/widgets/player_panel.dart`（右侧滑入面板壳） | 复用，勿另写 |

### 借鉴点
1. **4 个排序胶囊 = 名称升序 / 名称降序 / 日期升序 / 日期降序**（用户只要这 4 个，工作.md 第 7 点）——一行四个胶囊（横屏面板宽度足够）或两行两列，复用 `PlayerOptionChip`，选中态高亮。
2. 面板入口：底栏「倍速按钮左边」的**图标按钮**（工作.md 第 7/18 点，注意第 18 点的右下角顺序：选择屏幕→倍速→列表→超分）。
3. 面板内容：当前文件夹视频列表（点开时重新检测文件夹，见主题 2 的生成逻辑），点击项 → 保存当前进度 + 切换视频 + 高亮定位。
4. 当前播放项高亮 + 排序变化后按 path 重定位 + 滚动到可视区（src 的 `animateScrollToItem` 思路）。
5. 面板外壳：横屏用 `showPlayerPanel` 右侧滑入；**竖屏播放页改用底部弹出**（见主题 7），数据/排序逻辑共用。

### 坑
- 排序后当前索引变化：**用 path 匹配**而不是存 index。
- 临时排序（仅面板内生效）与全局排序（`ViewSettings`）互不干扰；工作.md 说"排序参考外部的排序，弄一个简化版本"——面板内排序可独立于 `ViewSettings`，但比较函数复用 `naturalCompare`。
- 切换集后：标题/进度条/缩略图/超分着色器全部要刷新（同一 `open()` 路径）。
- 列表按钮是图标（用户明确"使用图标表示，不要用文本"）。

---

## 主题 4：Android 画中画（PiP）

> 本项目是 **Flutter + media_kit（libmpv）**，与 Kazumi 同栈 → **首选 Kazumi 的 MethodChannel 方案**；
> `src` 的 `PipHelper.kt` 是 mpv 原生对照（同 Activity 复用 SurfaceView，无需新 Surface）。

### 关键 API / 参考文件

| 参考 | 文件 | 要点 |
|---|---|---|
| Flutter 侧封装 | `参考项目/Kazumi-main/Kazumi-main/lib/services/player/pip_utils.dart` | MethodChannel `com.predidit.kazumi/pip`：`isPictureInPictureSupported` / `enterPictureInPictureMode({width,height})` / `updatePictureInPictureActions({playing,danmakuEnabled,width,height})` / `setAndroidAutoEnterPIPEnabled` / `setAndroidPIPInPlayerPage`；`initPipHandler(onAction)` 收原生回传（`onAction` → Flutter 执行播放/暂停/快进）；`getPIPAspectSize` 用 `gcd` 约分宽高比 |
| 原生侧（Kotlin） | `参考项目/Kazumi-main/Kazumi-main/android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt` L183–337 | `packageManager.hasSystemFeature(FEATURE_PICTURE_IN_PICTURE)` + SDK≥O；`PictureInPictureParams.Builder().setAspectRatio(Rational(w,h))`；S+ 加 `setAutoEnterEnabled(autoEnter && inPlayerPage)` + `setSeamlessResizeEnabled(false)`；`RemoteAction`（播放/暂停/快进）→ `PendingIntent.getBroadcast(FLAG_IMMUTABLE\|FLAG_UPDATE_CURRENT)` → 自定义 action 的 `BroadcastReceiver` → `pipChannel.invokeMethod("onAction", {action})`；`maxNumPictureInPictureActions` 裁剪按钮数 |
| mpv 原生对照 | `参考项目/src/main/java/com/fam4k007/videoplayer/domain/player/PipHelper.kt`（155 行） | 宽高比取 `MPVLib video-out-params/dw, dh`，比例限制 0.5f..2.39f；`setSourceRectHint` 按视频/视图比例算居中 Rect；进 PiP 注册 receiver、退出注销；PiP 内快退/快进 `seek ±10 relative+keyframes` |
| 进出场 | `参考项目/src/main/java/com/fam4k007/videoplayer/VideoPlayerActivity.kt` L1101–1126 | `onFloatingWindow()`：先隐藏控制 UI（`alpha=0`）再 `enterPipMode()`；`onPictureInPictureModeChanged`：进 PiP 注册 receiver，退出恢复控制层，`pipCloseRequested` 时 finish |
| Manifest | `参考项目/src/main/AndroidManifest.xml` L86–91 | 播放 Activity：`android:supportsPictureInPicture="true"` + `configChanges="orientation\|screenSize\|screenLayout\|smallestScreenSize\|keyboardHidden\|keyboard\|navigation\|uiMode"` |

### 借鉴点
1. 原生通道方法集直接照 Kazumi 的 5+1 个方法（含 native→Flutter 的 `onAction` 回传），通道名换成本项目的包名。
2. PiP 内动作：播放/暂停 + 快进（±自定义秒数）；图标可用 `android.R.drawable.ic_media_*`（免资源）。
3. 宽高比：Flutter 从 media_kit `player.state.width/height`（或 `video-out-params`）取，`gcd` 约分后下发。
4. 进 PiP 时隐藏控制层（Flutter 侧隐藏控制 UI 再调通道），退出恢复；PiP 期间**不暂停**。
5. 入口：作为新 `PlayerTopAction`（槽位可选，见主题 6）或固定入口。

### 坑
- **`ARCHITECTURE.md` §7 已知坑**：Dart 小整数经 MethodChannel 到 Android 是 `Integer` 不是 `Long`，原生取参必须 `call.argument<Number>()?.toInt()/toLong()`。
- Android 12+ 广播注册必须 `ContextCompat.registerReceiver(..., RECEIVER_NOT_EXPORTED)`。
- 比例范围限制（0.5–2.39，src）防系统拒绝；`setSourceRectHint` 可选（Kazumi 没设也能用）。
- media_kit 的 Video surface 在 PiP 下无需重建（同 Activity），但退出 PiP 回播放页时要恢复控制层与全屏状态。
- `setAutoEnterEnabled`（Android 12+ 自动进 PiP）默认关，按设置决定。

---

## 主题 5：听视频（音频模式）

> 重点参考 `参考项目/src` 的 AudioPlayerActivity.kt / AudioPlayerScreen.kt（工作.md 第 10 点指定）。

### 关键 API / 参考文件

| 参考 | 文件 | 要点 |
|---|---|---|
| Activity 壳 | `参考项目/src/main/java/com/fam4k007/videoplayer/AudioPlayerActivity.kt`（29 行） | 薄壳：`ComponentActivity` + Compose `AudioPlayerScreen`，复用 `PlayerViewModel`（**同一个播放引擎实例**，不重建） |
| 听视频 UI（重点） | `参考项目/src/main/java/com/fam4k007/videoplayer/ui/screens/AudioPlayerScreen.kt`（634 行） | ①毛玻璃封面背景：封面 Bitmap `blur(40dp)` + 黑 0.75 蒙层（无封面则渐变降级）；②16:9 封面卡片 + 标题（2 行省略）；③Slider 拖动（`isDragging`/`dragFraction`/`onValueChangeFinished→seekTo`）+ 已播/总时长；④底部控制卡片 **5 按钮：倍速｜上一集｜播放暂停｜下一集｜播放列表**；⑤底部弹层 `SpeedBottomSheet`（0.5/0.75/1/1.25/1.5/2/2.5/3x）、`PlaylistBottomSheet`（当前项**三竖条等化器动画 `EqualizerBars`**（无限 tween 400/580/760ms Reverse）+ footer「随机播放/循环模式」两卡片）；`BottomSheet` 通用壳：全屏遮罩点击关闭 + 底部 Surface 圆角 + 标题 + 滚动内容 + footer + 「关闭」 |
| 前台保活服务 | `参考项目/src/main/java/com/fam4k007/videoplayer/service/BackgroundPlaybackService.kt`（100 行） | 极简前台服务：NotificationChannel IMPORTANCE_LOW + `FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK` + `START_STICKY`，仅保活不带控制 |
| 进入听视频 | `参考项目/src/main/java/com/fam4k007/videoplayer/VideoPlayerActivity.kt` L1079–1097 `onBackgroundPlayback()` | 需已开始播放（否则 Toast「请先开始播放视频」）；暂停弹幕 → 同步状态到共享容器 → `startForegroundService` + 打开 AudioPlayerActivity |
| Flutter 同栈参考 | `参考项目/Kazumi-main/.../lib/services/player/audio_controller.dart`（audio_service `BaseAudioHandler`）；`参考项目/Kazumi-main/.../lib/pages/settings/player_settings.dart` L350–364 | `audio_service` 后台播放；设置项「后台播放：应用退到后台或熄屏时继续播放音频」 |
| Manifest | `参考项目/src/main/AndroidManifest.xml` L81–85, L130–138, L12–13 | `AudioPlayerActivity` `screenOrientation="portrait"`；`<service foregroundServiceType="mediaPlayback">`；权限 `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` / `POST_NOTIFICATIONS` |

### 借鉴点
1. Flutter 实现：**同一 `Player` 实例继续播**，进入独立"听视频"页（新文件、竖屏、黑背景）——移除/隐藏 `Video` 组件即可"只听"（media_kit 音频不受影响）。
2. 页面结构照 AudioPlayerScreen：封面缩略图（本项目已有 `VideoInfoService`/原生抓帧）+ 标题 + Slider + 5 按钮 + 底部弹层（倍速/播放列表，弹层可复用主题 7 的底部弹出壳）。
3. 保活：最小方案 src 的前台服务思路；若做完整后台播放（锁屏/熄屏），用 Kazumi 的 `audio_service` 方案。
4. 入口：作为新 `PlayerTopAction`（槽位可增删，见主题 6）→ 进入听视频页；退出回播放页，进度继续记忆。

### 坑
- 进入听视频前必须已开始播放（src 的 Toast 校验）；未播放时提示。
- 听视频页退出（finish）≠ 停止播放：回到播放页继续；只有用户主动退出播放页才停。
- 前台服务通知在 Android 13+ 要 `POST_NOTIFICATIONS` 运行时权限（src manifest 已声明）。
- 听视频页是**竖屏**（src `screenOrientation="portrait"`）；Flutter 用 `SystemChrome.setPreferredOrientations` 切换并在退出时恢复。
- 封面加载走 IO 线程（src 用 `Dispatchers.IO` + ThumbnailCacheManager），避免卡 UI。

---

## 主题 6：均衡器 / 解码 / 片头片尾 —— 仅入口

> 用户要求"仅入口"（工作.md 第 11–13 点）：不实现功能本身，入口可自由加入/移出顶栏 5 槽位与「更多」列表（工作.md 第 14 点）。

### 关键 API / 参考文件

| 参考 | 文件 | 要点 |
|---|---|---|
| "更多"菜单（入口列表先例） | `参考项目/src/main/java/com/fam4k007/videoplayer/domain/player/PlayerDialogManager.kt` L933–988 `showMoreOptionsDialog()` | 菜单项 = 章节(有章节时)/**解码/听视频/片头片尾/小窗播放/重复播放/音频均衡器**/自动旋转；按项索引 when 分发；竖屏右对齐、横屏居中 |
| 均衡器（全量实现，仅参考入口） | `参考项目/src/main/java/com/fam4k007/videoplayer/manager/compose/EqualizerDrawer.kt` | 右侧抽屉；`EqualizerState(enabled, bands[5] ±15dB, bassBoost, virtualizer)` |
| 片头片尾（全量实现，仅参考入口） | `参考项目/src/main/java/com/fam4k007/videoplayer/manager/compose/SkipSettingsDrawer.kt`；`manager/SkipIntroOutroManager.kt`；`player/SkipSegment.kt` | 抽屉：开关 + 秒数输入 + 滑杆 + 范围 + 一键重置；跳转实现 `SkipSegment` |
| 解码 | `参考项目/src/main/java/com/fam4k007/videoplayer/ui/screens/MediaSettingsScreen.kt`（decoder 选择） | hwdec 选择等 |
| 本项目占位先例 | `lib/models/player_action.dart` `PlayerTopAction` | 已有 `implemented=false` 的占位动作（subtitle/danmaku/audio），顶栏点击 `_showComingSoon(label)`；**新动作照此模式扩展枚举即可自动进入"可添加"列表** |

### 借鉴点
1. 新动作枚举（`PlayerTopAction` 加 `equalizer` / `decode` / `skipIntroOutro`，`implemented=false`）→ 自动出现在「更多 → 编辑控制栏 → 可添加」；加入槽位后顶栏显示、点击提示"功能即将上线"（现有 `_showComingSoon` 机制）。
2. 未加入槽位的动作自动出现在「更多」列表（工作.md 第 14 点"剩下的自动出现在更多里面"）——扩展 `_buildMorePanel`（`player_page.dart` L847）的动作列表，按"不在槽位且非隐藏"过滤。
3. 若后续要做真入口面板：复用 `showPlayerPanel` 右侧滑入（横屏）/底部弹层（竖屏），内容可参考 src drawer 的简化版。
4. 「编辑控制栏」的"可添加"区按动作枚举全量展示 + 槽位满提示（现有 `full = enabled.length >= 5` 逻辑已具备）。

### 坑
- 不要过度实现：用户明确"仅入口"，别引入 mpv 属性/音频 DSP 复杂度。
- 动作 id 一旦持久化不可改（`ARCHITECTURE.md`：`PlayerTopAction.id` 是稳定持久化标识）。
- 顶栏槽位满 5 个时的提示文案与"先移除"交互保持现状一致。

---

## 主题 7：竖屏播放页 + 底部弹出面板

> 工作.md 第 17 点：竖屏播放页**独立 dart 文件**、布局与横屏对应、右下角按钮切换；竖屏下所有展开页面**从底部弹出**。

### 关键 API / 参考文件

| 参考 | 文件 | 要点 |
|---|---|---|
| 竖屏控制层（Kotlin） | `参考项目/src/main/java/com/fam4k007/videoplayer/ui/player/PortraitControls.kt`（820 行） | `PortraitTopBar`：返回｜标题（弹性，可点击）｜电量/时间｜字幕｜弹幕｜比例｜锁定｜更多；顶部 padding 48 避刘海；电量走 `BroadcastReceiver(ACTION_BATTERY_CHANGED)`、时钟 30s 刷新。竖屏与横屏功能一致，只是布局换方向 |
| 横竖屏切换 | `参考项目/src/main/java/com/fam4k007/videoplayer/VideoPlayerActivity+Orientation.kt`（49 行） | `applyPortraitUiEnabled`：`SCREEN_ORIENTATION_SENSOR_PORTRAIT / SENSOR_LANDSCAPE`；`syncPortraitUiWithConfiguration`；`refreshVideoLayoutAfterOrientationToggle`：切向后 `seekTo(暂停位置)` 保持进度不跳变 |
| 底部弹层壳（最佳范本） | `参考项目/src/main/java/com/fam4k007/videoplayer/ui/screens/AudioPlayerScreen.kt` L566–629 `BottomSheet()` | 全屏遮罩（点击关闭）+ 底部 `Surface`（`fillMaxHeight(0.5f)`、top 圆角 20dp）+ 标题 + 滚动内容 + footer + 关闭行；进出场 `slideInVertically/slideOutVertically` |
| 本项目现状 | `lib/pages/player/player_page.dart`（横屏播放页，1532 行）；`lib/widgets/player_panel.dart`（右侧滑入面板壳 + `PlayerPanelNavigator`） | 竖屏页新建文件，不共用 |

### 借鉴点
1. 新建 `lib/pages/player/portrait_player_page.dart`（独立 StatefulWidget）：顶部 = 返回 + 标题 + 固定「更多」；中央 = 播放/暂停 + 快退快进；底部 = 进度条 + 下一集 + 时间（"已播放/总时长"可点击切换剩余时长，工作.md 第 20 点）。
2. 竖屏下所有二级界面（倍速/播放列表/更多/编辑控制栏）**从底部弹出**：写一个 `showPlayerPortraitSheet` 壳（参照 src BottomSheet 组成：遮罩+底部圆角 Surface+标题+内容+关闭），内容组件与横屏面板**共用**（数据/排序/切集逻辑同一份，只换容器）。
3. 切换按钮：横屏/竖屏都放屏幕右下角（工作.md 第 17 点）。
4. 手势层（`PlayerGestureLayer`）在竖屏下方向死区/灵敏度需按竖屏尺寸重新评估（横屏假设不通用）。
5. 横竖屏切换时保持播放位置：切向前记住 `_position`，切回后 seek 回去（src `refreshVideoLayoutAfterOrientationToggle` 的思路）。

### 坑
- 竖屏也要沉浸式黑背景 + 安全区处理（`AppFrame` 播放页 `bottom:false`；竖屏页面要自己处理状态栏/手势条避让，参考 PortraitControls 的 `statusBarsPadding`/`navigationBarsPadding`）。
- 不要复制横屏整页代码再改：用户要求"竖屏参考复用横屏代码"但文件独立——把共用逻辑（播放控制、进度、面板内容）下沉，页面壳分开。
- 底部弹层与横屏 `showPlayerPanel` 的差异：竖屏弹层不遮挡画面、可下拉关闭（可选）；`PlayerPanelNavigator.of` 的 context 约束同样适用（面板内取 context 要用 Builder）。
- 方向切换时 `SystemChrome.setPreferredOrientations` 与现有 `_enterFullscreen/_exitPlayer` 流程（`ARCHITECTURE.md` §4.4）配合，别破坏既有退出逻辑。

---

## 主题 8：ReorderableListView 拖拽高亮修复（深色下长按发白）

> 问题：工作.md 第 14 点——"已启用"区长按拖拽某项时，被长按项是白色的，深色界面下刺眼。
> 根因：`ReorderableListView` 默认 `proxyDecorator` 把拖拽项包在带 elevation 的 `Material` 里，M3 深色主题下产生泛白效果。

### 关键 API / 参考文件

| 参考 | 文件 | 要点 |
|---|---|---|
| 修复方案 A（PiliPlus） | `参考项目/PiliPlus-main/PiliPlus-main/lib/common/widgets/reorder_mixin.dart`（18 行） | `proxyDecorator(child,_,_) => ColoredBox(color: scheme.onInverseSurface, child: child)` —— 深色主题下 `onInverseSurface` 是深色，**彻底消除白底** |
| 修复方案 B（Kazumi，独立拖拽手柄） | `参考项目/Kazumi-main/Kazumi-main/lib/pages/plugin_editor/plugin_view_page.dart` L277–286, L371–375 | `buildDefaultDragHandles: false` + `proxyDecorator: Material(elevation: 0, color: Colors.transparent)` + 每项 `ReorderableDragStartListener(index: i, child: Icon(Icons.drag_handle))` —— 长按整项不再触发拖拽高亮，只有手柄可拖 |
| 本项目现状 | `lib/pages/player/player_page.dart` L884–923 `_buildEditPanel` | 已用 `ReorderableListView.builder(shrinkWrap, NeverScrollableScrollPhysics, onReorderItem: reorderTopAction)`；注意本 SDK 参数名是 `onReorderItem`（新 Flutter 版本 API，旧版为 `onReorder`，实现前确认当前 SDK 签名） |
| 排序持久化 | `lib/services/player_controls_settings.dart` L385–392 `reorderTopAction(old,new)` | `list.insert(new, list.removeAt(old))` 已存在 |

### 借鉴点
1. 最小改动（推荐先做）：给 `_buildEditPanel` 的 `ReorderableListView.builder` 加
   `proxyDecorator: (child, _, _) => ColoredBox(color: ColorScheme.of(context).onInverseSurface, child: child)`（PiliPlus 同款）。
2. 若还嫌整项长按触发拖拽误触，可叠加 Kazumi 方案：`buildDefaultDragHandles: false` + 尾部 `drag_indicator` 图标用 `ReorderableDragStartListener` 包裹。
3. 拖拽索引修正：Flutter 原生 `onReorder(oldIndex,newIndex)` 语义是"newIndex>oldIndex 时需 -1"（移除后再插入）；本项目 `reorderTopAction` 已实现，勿改。

### 坑
- 不要给 proxyDecorator 套回带 elevation 的 `Material`（白底根源）；用 `ColoredBox` 或 `Material(elevation:0, transparent)`。
- 若列表项内已有长按手势（如长按删除/选中），方案 B 的手柄能避免手势冲突。
- 修改后必须跑 `flutter test` 中相关测试（`player_panel_test.dart` 等涉及编辑面板的用例），并回归「已启用/可添加」交互。

---

## 附：本项目落地文件速查（工程师开工前必读）

| 需求 | 主要涉及现有文件 |
|---|---|
| 恢复进度 + 指示器 | `player_page.dart`（initState 恢复/新增顶部指示器组件）、`playback_progress_service.dart`、`player_top_bar.dart` |
| 自动连播/循环/退出 | `player_page.dart`（completed 事件）、`player_controls_settings.dart`（新开关）、`player_settings_page.dart`（播放行为组） |
| 播放列表面板 | `player_page.dart`（底栏列表按钮 + 面板）、`player_bottom_bar.dart`、`view_settings.dart`（排序比较函数）、`player_option_chip.dart` |
| PiP | 新 MethodChannel + `android/app/src/main/kotlin/**/MainActivity.kt`、`AndroidManifest.xml`、`player_page.dart`（入口） |
| 听视频 | 新 `portrait/audio` 页文件 + `player_page.dart`（入口）、原生前台服务（可选） |
| 仅入口动作 | `models/player_action.dart`（枚举扩展）、`player_page.dart`（`_buildMorePanel`/`_handleSlotAction`） |
| 竖屏播放页 | 新 `portrait_player_page.dart` + 底部弹层壳 + `player_page.dart`（切换按钮） |
| 拖拽高亮 | `player_page.dart` `_buildEditPanel`（proxyDecorator） |

> 测试约束：新增/改动逻辑必须配测试（`ARCHITECTURE.md` §6）；改 `AppFrame`/`ViewSettings` 排序/`PlayerPanel` 的必须跑对应回归测试。
