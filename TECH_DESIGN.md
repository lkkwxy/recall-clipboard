# Recall — 技术设计文档

> macOS 剪贴板管理工具。自动记录复制过的文本与图片，保存到本地文件夹，并提供界面浏览、搜索历史。

---

## 1. 项目概述

Recall 是一款常驻 macOS 菜单栏的剪贴板管理工具。用户复制任何文本或图片后，Recall 自动捕获并保存到**本地文件夹**（用户可配置），之后可通过全局快捷键唤起浮层面板，浏览、搜索、重新复制历史记录。

核心定位：**数据存本地、用户可掌控存储位置**，区别于把数据锁在应用内部数据库里的同类工具。

---

## 2. 功能需求

| # | 功能 | 说明 |
|---|------|------|
| 1 | 捕获复制内容 | 监听系统剪贴板，保存复制过的**文本**和**图片** |
| 2 | 本地文件夹存储 | 所有记录以文件形式保存到本地文件夹，而非封闭数据库 |
| 3 | 存储位置可配置 | 用户可在设置中更改保存文件夹路径 |
| 4 | 历史浏览界面 | 提供界面展示历史文本 & 图片，支持搜索与按类型筛选 |

衍生需求（设计阶段已纳入，开发可分期）：历史条数上限、按时间自动清理、来源 App 记录、全局快捷键唤起。

---

## 3. 技术选型

| 维度 | 选择 | 理由 |
|------|------|------|
| 语言 | Swift 5.9+ | macOS 原生首选，无运行时依赖 |
| UI | SwiftUI（主面板/设置）+ AppKit（菜单栏、浮层窗口） | SwiftUI 写列表/设置高效；菜单栏常驻和无边框浮层窗口需 AppKit 补足 |
| 应用形态 | 菜单栏常驻应用（`LSUIElement = true`） | 无 Dock 图标、无主窗口，符合剪贴板工具的交互习惯 |
| 剪贴板监听 | `NSPasteboard` + 定时轮询 `changeCount` | 系统无剪贴板变化通知，轮询是唯一可行方案（见 §6） |
| 全局快捷键 | `CGEvent` Tap 或第三方 `HotKey` 库 | 唤起面板，默认 ⌥ + V |
| 索引存储 | 系统 SQLite3（薄封装）| 元数据与搜索；正文/图片落地为文件。零外部依赖，见 §10 修订 |
| 最低系统 | macOS 13 Ventura | SwiftUI 在 13+ 才足够成熟 |

> 不引入跨平台框架（Electron/Flutter）。剪贴板工具对启动速度、内存占用、系统集成度敏感，原生是正确选择。

---

## 4. 架构设计

```
┌─────────────────────────────────────────────┐
│                  App (菜单栏常驻)              │
├─────────────────────────────────────────────┤
│  ClipboardMonitor   ← 轮询 NSPasteboard       │
│         │ 捕获到新内容                          │
│         ▼                                      │
│  ClipboardStore     ← 写入本地文件 + 更新索引   │
│         │                                      │
│   ┌─────┴──────┬──────────────┐                │
│   ▼            ▼              ▼                │
│ HistoryPanel  Settings    MenuBarMenu          │
│ (浮层面板)    (设置窗口)   (菜单栏下拉)          │
└─────────────────────────────────────────────┘
```

模块职责：

- **ClipboardMonitor**：定时检测剪贴板变化，识别内容类型（文本/图片），去重，交给 Store。
- **ClipboardStore**：唯一的数据出入口。负责把内容写入本地文件夹、维护索引、提供查询/搜索/删除接口。UI 层只与它交互。
- **HistoryPanel**：全局快捷键唤起的浮层窗口，展示历史列表，支持搜索/筛选/复制/删除。
- **SettingsWindow**：标准窗口，配置存储路径、开关、历史上限、自动清理。
- **MenuBarMenu**：菜单栏图标 + 下拉菜单（最近 5 条 + 打开面板/设置/退出）。

---

## 5. 本地存储方案

存储位置默认 `~/Documents/Recall/`，用户可在设置中更改。目录结构：

```
<保存文件夹>/
├── index.sqlite          # 索引：id、类型、时间、来源 App、文件名、文本预览
├── texts/
│   ├── 2026-06-16T08-30-12-ab12.md
│   └── ...
└── images/
    ├── 2026-06-16T08-31-05-cd34.png
    └── ...
```

设计要点：

- **正文落地为独立文件**，文本存 `.md`，图片存 `.png`。文本用 Markdown 后缀，便于在编辑器/笔记工具里直接打开预览。这样用户在 Finder 里就能直接看到、备份、甚至用其他工具处理——这是「数据存本地、用户可掌控」定位的核心体现。
- **索引（index.sqlite）只存元数据**：id、类型、创建时间、来源 App、对应文件名、文本前若干字的预览。搜索和列表渲染走索引，不必读全部文件，保证面板秒开。
- **更改存储路径时**：把旧文件夹整体迁移到新路径（移动文件 + 重建/迁移索引），失败要回滚，避免数据丢失。
- 图片大缩略图按需生成并缓存，列表里不直接加载原图。

### 数据模型（索引记录）

```swift
struct ClipItem: Identifiable {
    let id: UUID
    let type: ClipType          // .text / .image
    let createdAt: Date
    let sourceApp: String?      // 来源 App bundle id / 名称
    let fileName: String        // 对应 texts/ 或 images/ 下的文件名
    let preview: String         // 文本预览；图片为尺寸描述如 "1280×720"
    let byteSize: Int
}

enum ClipType { case text, image }
```

---

## 6. 关键技术点：剪贴板监听

**macOS 没有提供剪贴板内容变化的系统通知。** 唯一可靠方式是用定时器轮询 `NSPasteboard.general.changeCount`——这个整数每次剪贴板被写入都会递增。

```swift
final class ClipboardMonitor {
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        // 0.5s 轮询：响应足够快，CPU 占用可忽略
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // 优先级：图片 > 文本（图片复制有时会同时带文件名文本）
        if let image = pb.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            store.saveImage(image, sourceApp: frontmostAppName())
        } else if let text = pb.string(forType: .string), !text.isEmpty {
            store.saveText(text, sourceApp: frontmostAppName())
        }
    }
}
```

注意事项：

- **去重**（文本与图片统一用内容哈希）：
  - 文本：对文本内容算 SHA-256，与最近记录的哈希比对，相同则跳过——重复复制同一段文字不会产生多条记录。
  - 图片：对图片字节算 SHA-256，与最近记录比对，相同则跳过——避免连续截图、重复复制同一张图刷屏。
  - 哈希统一存入索引，便于快速比对。
- **轮询间隔**：0.5s 是体验与能耗的平衡点，不要做到几十毫秒。
- **隐私/敏感内容**：部分 App 会在剪贴板标记 `org.nspasteboard.ConcealedType`（如密码管理器），命中时应**跳过不记录**。这是隐私底线，必须实现。
- **来源 App**：通过 `NSWorkspace.shared.frontmostApplication` 在捕获瞬间获取。

---

## 7. 页面与模块对应

已完成 5 个页面的设计需求，对应实现模块：

| 页面 | 模块 | 说明 |
|------|------|------|
| 主历史面板 | HistoryPanel | 浮层窗口，搜索框 + 全部/文本/图片筛选 + 卡片列表 |
| 设置窗口 | SettingsWindow | 存储路径、保存开关、历史上限、自动清理、占用空间 |
| 菜单栏下拉 | MenuBarMenu | 最近 5 条 + 打开面板/设置/退出 |
| 空状态 | HistoryPanel（无数据态） | 插画 + 「按 ⌥+V 唤起」新手引导 |
| 搜索无结果 | HistoryPanel（无匹配态） | 回显搜索词 + 清除搜索出口 |

视觉基调：遵循 macOS 原生设计语言，毛玻璃浮层 + 圆角，浅色/深色双版本，气质参考 Raycast / Paste。

---

## 8. 建议目录结构（代码）

```
Recall/
├── TECH_DESIGN.md          # 本文档
├── Recall.xcodeproj
├── Recall/
│   ├── App/                # AppDelegate、菜单栏入口、生命周期
│   ├── Clipboard/          # ClipboardMonitor、类型识别、去重
│   ├── Storage/            # ClipboardStore、文件读写、索引、路径迁移
│   ├── Features/
│   │   ├── History/        # 主面板、卡片、空状态、无结果
│   │   ├── Settings/       # 设置窗口
│   │   └── MenuBar/        # 菜单栏图标与下拉
│   ├── Models/             # ClipItem、ClipType 等
│   └── Resources/          # 图标、插画、Assets
└── Tests/
```

---

## 9. 开发阶段（里程碑）

每个阶段都有可验证的产出，避免「让它跑起来」式的模糊目标。

1. **M1 — 捕获与存储跑通**
   - 监听剪贴板 → 文本/图片写入本地文件夹 + 索引
   - 验证：复制文本和图片，Finder 里能看到对应文件，索引有记录
2. **M2 — 历史面板可用**
   - 快捷键唤起面板，展示列表，点击重新复制
   - 验证：复制 → 唤起 → 看到记录 → 点击粘贴成功
3. **M3 — 搜索与筛选**
   - 搜索框 + 全部/文本/图片筛选 + 空状态 + 无结果态
   - 验证：搜关键词命中/不命中分别走对状态
4. **M4 — 设置与存储配置**
   - 更改保存路径（含数据迁移）、保存开关、历史上限、自动清理
   - 验证：改路径后旧数据迁移成功、新内容写到新路径
5. **M5 — 打磨**
   - 深色模式、隐私跳过（ConcealedType）、缩略图缓存、性能

---

## 10. 已定决策

- [x] **CLAUDE.md 已建**：项目规范先行（命名、目录、验证命令、红线、隐私底线）。
- [x] ~~**索引用 SQLite（GRDB）**~~ → **修订（M1）：改用系统自带 libsqlite3 + 薄封装**。GRDB 需手改 pbxproj 加 SPM 包并联网解析；系统 SQLite3 零依赖、`import SQLite3` 即用、不动包配置，已足够支撑 index 的增删查/去重/排序。封装在 `Storage/SQLiteIndex`，仅 Storage 层内部使用。
- [x] **初期非沙盒 + 自分发**：不上架 App Store，避免沙盒对文件访问的限制——用户可自由选择任意保存文件夹。分发时做 Developer ID 签名 + 公证（Notarization）即可在他人机器正常打开。

## 11. 已定决策（续）

- [x] **全局快捷键用 `sindresorhus/KeyboardShortcuts` 库**（底层 Carbon `RegisterEventHotKey`，**无需辅助功能权限**）。不自写 CGEvent Tap：Tap 需 Accessibility 授权、有性能开销、能力远超「单一快捷键唤起」的需求。选 KeyboardShortcuts 而非 soffes/HotKey 是因为它自带 SwiftUI 录制控件 `KeyboardShortcuts.Recorder` + 持久化，直接复用到设置页的「快捷键」分组。

## 12. 已定决策（续）

- [x] **文本存为 `.md`**：便于在编辑器/笔记工具直接预览。
- [x] **文本与图片统一用 SHA-256 内容哈希去重**：相同内容（重复复制同段文字 / 同张图）跳过，不产生重复记录；哈希存入索引。

> 至此技术决策全部敲定，无待确认项。
