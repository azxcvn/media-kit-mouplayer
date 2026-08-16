# 树状 / 列表模式 UI 统一 — 实施规格

> 目标：moumou Flutter 应用树状模式下文件夹、视频节点的 UI 与列表模式完全一致（同一套卡片组件），并统一排序行为。
> 状态：规格已定稿，待开发工程师实施。
> 工作区：`C:\Users\root\Desktop\moumou`

---

## 0. 差异核实结论（分析员已逐行核实源码）

队长背景描述全部属实，补充细节如下（行号基于当前代码）：

### 0.1 文件夹节点
| 维度 | 列表 `_FolderCard`（home_page.dart L230-366） | 树状 `_TreeFolderTile`（L405-514） |
|---|---|---|
| 背景 | `Card` elevation 0、`surfaceContainerLow`、radius 16 | 无 Card，纯 `InkWell` 行 |
| 图标容器 | 48×48 `primaryContainer` radius 14 + folder 图标 | `Icon(folder)` 22px `primary`，无容器 |
| 名称 | `MarqueeText` 16px w600（跑马灯） | `Text` maxLines1 15px w600（ellipsis） |
| 字段 | path（单独行）+ count/size/date（13px tag，Wrap spacing 14） | **完全不消费 `FolderField.path`**（L433-456 只处理 count/size/date）；count/size/date 用 12px `_treeTag` |
| 尾部箭头 | 静态 `chevron_right` | `AnimatedRotation`（展开时转 0.25，即向下） |
| 缩进 | 无 | `indent = depth * 16` |

### 0.2 视频节点
| 维度 | 列表 `VideoCard`（video_card.dart） | 树状 `_TreeVideoTile`（L517-671） |
|---|---|---|
| 背景 | Card elevation 0、radius 16 | 无 Card，InkWell 行 |
| 缩略图 | 120×68 radius 12 | 72×42 radius 8 |
| 角标 | size（左下）+ duration（右下），黑 65% alpha 圆角 4 | **无角标**，仅进度条 |
| 名称 | maxLines 2，15px w600 | maxLines 1，14px w500 |
| 字段 | 右侧 date/resolution 12px 标签 | duration/size/date/resolution 全部做成名称下方 12px 标签 |
| 图标 | `play_circle_outline` | `play_circle_outline` 20px |

### 0.3 排序（已确认缺失）
- 列表模式：`sortFolders(_folders)` 已应用（home_page L129）；详情页 `sortVideos` 已应用。
- 树状模式：顶层 `_buildTree(_roots)` 直接用原始 `_roots`，**未排序**；子级 `node.children` 直接渲染，**未排序**。`buildTree` 内部硬编码"文件夹前视频后、各按名称升序"，用户排序偏好完全无效。
- 交互（保持项）：树状文件夹点击 toggle `_expanded`（L462）；树状视频点击 `_openVideo` 直接播放（L399）；列表文件夹点击 push `FolderDetailPage`。

---

## a) 组件抽取方案

### a.1 新增 `lib/widgets/folder_card.dart` — 公共 `FolderCard`

从 `_FolderCard` 移植全部视觉规格（Card / 48×48 图标容器 / MarqueeText 16px w600 / 路径行 / 字段 tag / chevron），新增树状模式参数：

```dart
/// 文件夹卡片：列表模式与树状模式共用（字段驱动渲染）
class FolderCard extends StatelessWidget {
  final TreeNode node;
  final Set<FolderField> fields;
  final VoidCallback onTap;      // 列表=打开详情页；树状=切换展开/折叠
  final bool? expanded;          // 树状模式展开状态；null=列表模式（静态箭头）
  final double indent;           // 树状缩进 = depth*16（clamp 上限 48）；列表=0

  const FolderCard({
    super.key,
    required this.node,
    required this.fields,
    required this.onTap,
    this.expanded,
    this.indent = 0,
  });
}
```

**箭头渲染规则**（决定列表/树状行为差异的唯一分支）：
- `expanded == null`（列表模式）→ 静态 `Icon(Icons.chevron_right)`，`onTap` 走打开详情页。
- `expanded != null`（树状模式）→ `AnimatedRotation(turns: expanded! ? 0.25 : 0, duration: 200ms)` + `chevron_right`，`onTap` 走切换展开。

> 说明：不单独设 `onExpandToggle` 参数——树状模式把 `setState(() => _expanded = !_expanded)` 直接绑到 `onTap`，`expanded` 仅驱动箭头旋转。少一个参数且无"两个回调哪个优先"的歧义。若工程师坚持拆分回调，可加 `onExpandToggle`（非 null 时优先），但不推荐。

**内部结构**（保持列表模式像素不变）：
```
Padding(EdgeInsets.only(left: indent))  ← 树状缩进包在 Card 外
└─ Card(elevation: 0, surfaceContainerLow, RoundedRectangleBorder(16))
   └─ InkWell(onTap, radius 16)
      └─ Padding(horizontal 16, vertical 14)
         └─ Row
            ├─ 48×48 primaryContainer radius14 + Icon(folder)
            ├─ SizedBox(14)
            ├─ Expanded(Column
            │   ├─ MarqueeText(node.name, 16px w600)
            │   ├─ _buildFields(scheme)   // 沿用 _FolderCard 的字段逻辑
            │   └─ )
            └─ 箭头（按 expanded 规则）
```

**字段渲染**（从 `_FolderCard` 原样迁移，仅一处改进）：
- `FolderField.path` → `_fieldRow`（folder_open 图标 14px + 文本 13px `onSurfaceVariant`）；**改进：`Text` 加 `maxLines: 1, overflow: TextOverflow.ellipsis`**（现状无限制，树状深层绝对路径会换行撑高卡片）。
- count/size/date → `_fieldTag`（图标 14px + 文本 13px），`Wrap(spacing: 14, runSpacing: 4)`。
- 工具函数 `formatFileSize` / `formatDate`：见 a.3 建议抽到 `lib/utils/formatters.dart`；若不抽，`folder_card.dart` import `video_card.dart` 复用（改动最小，但不推荐 widget 互依赖）。

### a.2 树状模式复用 `VideoCard`（缩进包裹即可）

树状视频节点不再需要 `_TreeVideoTile`（L517-671 整类删除，含 `_loadThumb`/`_buildProgressBar`/`_treeTag`）：

```dart
Padding(
  padding: EdgeInsets.only(left: min(depth * 16.0, 48.0)),
  child: VideoCard(
    video: node.video!,
    fields: videoFields,      // 与详情页同一来源：viewSettings.videoFields
    onTap: () => onVideoTap(node.video!),
  ),
)
```

- `VideoCard` **零改动**：120×68 缩略图、size/duration 角标、进度条、maxLines2 15px w600 名称、date/resolution 标签、play 图标全部保留 → 树状与列表视觉逐像素一致。
- 缩进 `clamp(0, 48)`：depth≥3 不再加深，避免名称列被挤压到不可读（见 e 风险）。

### a.3（推荐）新增 `lib/utils/formatters.dart`

把 `formatFileSize` / `formatDate` / `formatDuration`（现位于 video_card.dart 底部 L216-239）迁出为公共工具，`video_card.dart` 与 `folder_card.dart` 共同 import。避免 folder_card → video_card 的 widget 间依赖。若为最小改动可不做，`folder_card.dart` 直接 `import video_card.dart` 复用函数即可（功能等价）。

---

## b) 树状模式交互保持（不可变更）

| 交互 | 现状 | 统一后 | 保证方式 |
|---|---|---|---|
| 文件夹点击 | toggle 展开/折叠 | 不变 | `FolderCard.onTap = () => setState(() => _expanded = !_expanded)` |
| 视频点击 | 直接播放 | 不变 | `VideoCard.onTap = () => onVideoTap(node.video!)` |
| 列表文件夹点击 | push FolderDetailPage | 不变 | `FolderCard.onTap = () => _openFolder(node)` |

两类节点在树状下互不重叠（folder 节点 → FolderCard，video 节点 → VideoCard），点击行为天然无冲突。

---

## c) 排序统一方案

### c.1 `ViewSettings` 新增混合排序（lib/services/view_settings.dart）

```dart
/// 树状节点混合排序：文件夹在前、视频在后（与 buildTree 结构一致）。
/// 文件夹按文件夹排序规则（SortField×SortOrder），视频按视频排序规则
/// （VideoSortField×VideoSortOrder），递归作用于全部层级。
List<TreeNode> sortTree(List<TreeNode> nodes) {
  final folders = <TreeNode>[];
  final videos = <TreeNode>[];
  for (final n in nodes) {
    if (n.isFolder) {
      folders.add(_sortFolderNode(n)); // 递归排序其 children
    } else {
      videos.add(n);
    }
  }
  _sortFolderList(folders);
  _sortVideoList(videos);
  return [...folders, ...videos];
}

TreeNode _sortFolderNode(TreeNode n) {
  if (n.children.isEmpty) return n;
  return TreeNode(
    name: n.name,
    path: n.path,
    type: n.type,
    children: sortTree(n.children),  // 子级递归排序
    videoCount: n.videoCount,
    totalSize: n.totalSize,
    dateModified: n.dateModified,
  );
}
```

### c.2 重构现有排序方法（消除重复比较器）

把 `sortFolders` / `sortVideos` 的 switch 比较器抽为私有方法，公开方法签名不变（列表模式/详情页零感知）：

```dart
int _compareFolders(TreeNode a, TreeNode b) { /* 原 L209-217 的 switch 逻辑 */ }
int _compareVideos(TreeNode a, TreeNode b) { /* 原 L227-237 的 switch 逻辑 */ }

List<TreeNode> sortFolders(List<TreeNode> folders) {
  final list = [...folders];
  list.sort((a, b) {
    final cmp = _compareFolders(a, b);
    return _sortOrder == SortOrder.asc ? cmp : -cmp;
  });
  return list;
}
// sortVideos 同理；_sortFolderList/_sortVideoList 即对已分组列表调用上述比较器+方向。
```

### c.3 应用点（home_page.dart）

- `_buildTree`：`final roots = widget.viewSettings.sortTree(_roots);`（在 ListenableBuilder 内，与列表模式 `sortFolders` 同级调用）。
- 子级：排序在 `sortTree` 递归中完成（重建 `TreeNode.children` 顺序），`_TreeFolderTile` 渲染时直接用 `node.children`，**无需在渲染层再排序**。

### c.4 排序规则结论

- 顶层混合列表：文件夹组按文件夹排序偏好 + 视频组按视频排序偏好，拼接为"文件夹在前、视频在后"——与 `buildTree` 的既有结构一致，无回归。
- 子级混合列表：同一规则递归。
- 用户切换排序 → `notifyListeners` → `ListenableBuilder` 重建 → `sortTree` 重算，即时生效。

---

## d) 逐文件改动清单

| 文件 | 改动 |
|---|---|
| **新增** `lib/widgets/folder_card.dart` | 公共 `FolderCard`（a.1）；import: material / tree_node / view_settings / marquee_text / formatters(或 video_card) |
| **新增** `lib/utils/formatters.dart`（推荐，可选） | 迁移 `formatFileSize` / `formatDate` / `formatDuration` |
| `lib/pages/home/home_page.dart` | ① import 增 `folder_card.dart`；若抽 formatters，`marquee_text.dart` 的 import 可移除（不再直接使用）；② `_buildList`：`_FolderCard` → `FolderCard`；③ `_buildTree`：`sortTree(_roots)`；④ `_TreeTile`：folder 分支 → `FolderCard`，video 分支 → `Padding+VideoCard`；⑤ `_TreeFolderTile` 保留为私有 StatefulWidget（仅持 `_expanded` + 渲染 FolderCard + 递归 children），**必须加 `key: ValueKey(node.path)`**；⑥ 删除：`_FolderCard` 类（L230-366）、`_TreeVideoTile` 类（L517-671）、`_treeTag` 函数（L673-685）、`_fieldRow`/`_fieldTag`（随 _FolderCard 删除，移入 FolderCard） |
| `lib/services/view_settings.dart` | 新增 `sortTree` / `_sortFolderNode`；抽 `_compareFolders` / `_compareVideos`；公开方法签名不变；无新增字段、无存储迁移 |
| `lib/widgets/video_card.dart` | 若抽 formatters：删 L216-239 三个工具函数 + import formatters；其余零改动 |
| `lib/pages/home/folder_detail_page.dart` | **不改**（已验证：VideoCard + sortVideos，已是列表规格） |
| `lib/models/tree_node.dart` | **不改**（重建用现有构造器即可） |
| `test/widget_test.dart` | **不改**（仅测 CapsuleNavBar） |

### 树状展开结构的渲染骨架（_TreeFolderTile 新实现）

```dart
class _TreeFolderTile extends StatefulWidget {
  final TreeNode node;
  final Set<FolderField> folderFields;
  final Set<VideoField> videoFields;
  final int depth;
  final void Function(VideoFile) onVideoTap;
  const _TreeFolderTile({super.key, ...}); // key 由调用方传 ValueKey(node.path)
}

class _TreeFolderTileState extends State<_TreeFolderTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FolderCard(
          node: widget.node,
          fields: widget.folderFields,
          indent: min(widget.depth * 16.0, 48.0),
          expanded: _expanded,
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final child in widget.node.children)
            _TreeTile(
              node: child,
              folderFields: widget.folderFields,
              videoFields: widget.videoFields,
              depth: widget.depth + 1,
              onVideoTap: widget.onVideoTap,
            ),
      ],
    );
  }
}
```

子级缩进对齐：子级视觉左缘 = `(depth+1)*16 + 4`（+4 为 Card 默认 margin 的补偿，见 e-3）。

---

## e) 风险点与注意事项

1. **展开状态错位（必须修）**：`_TreeFolderTile` 必须加 `key: ValueKey(node.path)`（folder path 唯一）。排序后节点位置会变，无 key 时 Flutter 按位置匹配 State，`_expanded` 会跟随错节点。当前代码无排序所以未暴露，排序落地后必修。
2. **MarqueeText 在深层缩进下的表现**：depth 大时名称列窄，MarqueeText 会自动滚动（现有实现仅 overflow 时启动动画，无空闲开销）。缩进 clamp 到 48 后名称列 ≥ 约 135dp，16px 中文约 8 字/屏，跑马灯可读。若观感不佳，可后续为树状模式把名称字号降到 15px（**不建议**，会破坏"与列表一致"）。
3. **Card 默认 margin 叠加**：Material 3 `Card` 默认 margin = 4。树状缩进包在 Card 外时，视觉缩进 = `depth*16 + 4`；子级对齐按 `(depth+1)*16 + 4` 即可自然对齐，无需特殊处理；列表模式维持现状（ListView padding 12 不变，像素无回归）。
4. **VideoCard 缩略图 120×68 在树状下的宽度**：depth≤2 时名称列 ≥150dp，maxLines2 可显示；clamp 后 depth≥3 仍 ≥135dp。行高从 42 增至 68，长列表滚动变长——这是"与列表一致"的直接代价，可接受。
5. **全树重建成本**：`TreeNode` 不可变，`sortTree` 每次调用递归重建节点。`PlaybackProgressService` / `viewSettings` 变化都会触发 `ListenableBuilder` 全量重算。树规模（几十～几百节点）下开销毫秒级，可忽略；如遇卡顿，可在 `_HomePageState` 缓存 `sortTree` 结果、按 settings 版本失效（进阶优化，非本次必须）。
6. **顶层根目录直接视频**：树状顶层为文件夹+视频混合，`sortTree` 后"文件夹前、视频后"，与 `buildTree` 现有结构一致，无回归。
7. **`FolderField.path` 超长文本**：FolderCard 路径行必须 `maxLines: 1 + ellipsis`（改进点，同时惠及列表模式长路径场景）。
8. **import 依赖方向**：`folder_card.dart → (tree_node, view_settings, marquee_text, formatters)`；`home_page.dart → (folder_card, video_card, view_settings, tree_node)`；无循环依赖。
9. **字段默认值**：`FolderField.path` 默认关闭（fields 默认 `{count, size}`），树状模式用户开启后才显示路径——与列表模式行为一致，无需迁移。
10. **验证清单（实施后）**：① 列表模式视觉零回归（像素级对比截图）；② 树状模式文件夹卡片 = 列表卡片 + 旋转箭头 + 缩进；③ 树状视频卡片 = 列表 VideoCard 含角标/进度条；④ 树状点击展开/折叠、视频直接播放；⑤ 切换排序方式，树状顶层与各级子节点即时重排且展开状态不串位；⑥ 开启 path 字段，树状显示路径且不换行。
