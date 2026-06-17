# Recall — 项目规范

> macOS 剪贴板管理工具。技术方案见 [TECH_DESIGN.md](./TECH_DESIGN.md)。本文件是动手前必读的规则，与 TECH_DESIGN 冲突时以本文件为准。

## 技术栈

- Swift 5.9+，macOS 13+
- SwiftUI（主面板/设置）+ AppKit（菜单栏、无边框浮层窗口）
- 菜单栏常驻应用：`LSUIElement = true`，无 Dock 图标
- 索引用 SQLite（GRDB）；正文/图片落地为独立文件

## 目录约定

```
Recall/
├── App/          # AppDelegate、菜单栏入口、生命周期
├── Clipboard/    # 监听、类型识别、去重
├── Storage/      # Store、文件读写、索引、路径迁移
├── Features/     # History / Settings / MenuBar，每个功能一个子目录
├── Models/       # 数据模型
└── Resources/    # 图标、插画、Assets
```

- 新建功能 → 在 `Features/` 下开独立子目录，View + ViewModel 同目录
- 所有数据读写**只走 `Storage/ClipboardStore`**，UI 层不得直接碰文件系统或剪贴板

## 命名

- 类型/协议 `UpperCamelCase`，方法/变量 `lowerCamelCase`，常量同变量
- 文件名 = 主类型名（如 `ClipboardMonitor.swift`）
- View 以 `View` 结尾，ViewModel 以 `ViewModel` 结尾
- 一律英文命名；注释可中文

## 编码原则（继承全局 CLAUDE.md）

- **简洁优先**：用最少代码解决问题，不加需求外的功能/抽象/"灵活性"
- **精准修改**：只碰必须碰的，不顺手重构相邻代码，匹配现有风格
- 不为了让代码跑起来而注释报错或加绕过标记，找根本原因
- 困惑时停下来问，不要猜

## 验证（改完必须跑）

```bash
# 编译
xcodebuild -scheme Recall -configuration Debug build
# 测试
xcodebuild -scheme Recall -destination 'platform=macOS' test
```

改完代码主动跑以上命令，不要只改不验。

## 红线（即使 auto-accept 也先问）

继承全局 CLAUDE.md 红线，项目内额外强调：

- 删除文件/目录、git 回滚
- 修改用户的**保存文件夹**内的数据（迁移逻辑要可回滚，绝不丢数据）
- 改 `*.entitlements`、签名、沙盒配置
- 发布（公证、分发、上架）

## 隐私底线（必须实现，不可省）

- 命中 `org.nspasteboard.ConcealedType`（密码管理器等标记的敏感内容）→ **跳过不记录**
- 剪贴板数据只存本地，不上传任何服务器、不进日志

## 提交

- 一次 commit 一件事，message 用中文、说清「做了什么/为什么」
- 不提交：`.DS_Store`、`build/`、`DerivedData/`、密钥、entitlements 里的私密配置

## 开发顺序

按 TECH_DESIGN §9 的 M1→M5 推进，每个里程碑达到其「验证」标准再进下一个。当前阶段：**M1 已完成**（已实机验证）；**M2–M5 已实现并编译通过、数据链路已验证**，GUI 交互（⌥V 唤起、点击复制、搜索筛选、设置、深色）待在 Xcode 运行中人工验证（headless 环境受 TCC 限制无法驱动 GUI）。
