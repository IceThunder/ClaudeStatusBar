# Claude Status Bar

macOS 菜单栏状态监控应用，在菜单栏中实时查看 **Claude**、**Foxcode**、**ZENMUX** 服务的运行状态和配额使用情况。

## 功能

- **Claude 状态** — 从 [status.claude.com](https://status.claude.com) 实时获取各组件状态（Claude.ai、Claude API、Claude Code 等），以可视化健康条展示
- **Foxcode 监控** — 从 Foxcode 状态页获取所有监控点的在线状态和延迟（ping），实时掌握服务可用性
- **ZENMUX 配额** — 安全存储 Management API Key（Keychain + Touch ID），展示订阅详情和 5 小时 / 7 天 / 月度三级配额使用进度
- **自动刷新** — 每 5 分钟自动拉取最新状态，菜单展开时实时更新"X 秒前获取"的相对时间

## 截图

> 菜单栏图标为 SF Symbol `circle.fill`，根据整体状态变色（绿/黄/橙/红/灰）。

## 原理

```
┌─────────────────────────────────────────────────┐
│                   Claude Status Bar              │
├─────────────────────────────────────────────────┤
│  StatusService         FoxcodeStatusService      │
│  status.claude.com     status.rjj.cc             │
│  /api/v2/components    /api/status-page/foxcode  │
│                                                 │
│  ZenmuxService                                  │
│  zenmux.ai/api/v1/management/subscription/detail │
│  (Keychain + Touch ID)                          │
├─────────────────────────────────────────────────┤
│  StatusBarController (AppKit, NSStatusBar)       │
│  ├─ ComponentStatusView (健康条 + 状态文字)       │
│  ├─ FoxcodeMonitorView (在线/离线 + ping)        │
│  └─ ZenmuxQuotaView (进度条 + 配额详情)          │
└─────────────────────────────────────────────────┘
```

三个服务独立并行请求，通过 `DispatchGroup` 汇聚后统一刷新菜单 UI。ZENMUX API Key 使用 `SecAccessControl` + `.userPresence` 存入 Keychain，读取时触发 Touch ID 验证。

## 快速开始

### 环境要求

- macOS 12.0+
- Xcode 15.0+（完整 Xcode，非仅 Command Line Tools）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（用于从 `project.yml` 生成 `.xcodeproj`）

### 构建运行

```bash
# 1. 生成 Xcode 项目
xcodegen generate

# 2. 打开并运行
open ClaudeStatusBar.xcodeproj
```

### 命令行构建

```bash
# Universal Binary（arm64 + x86_64）
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath ./build/ClaudeStatusBar.xcarchive archive

# 仅 M 系列（Apple Silicon）
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS=arm64 -archivePath ./build/arm64/ClaudeStatusBar.xcarchive archive

# 仅 Intel（x86_64）
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS=x86_64 -archivePath ./build/x86_64/ClaudeStatusBar.xcarchive archive

# 验证产物架构
lipo -info "./build/ClaudeStatusBar.xcarchive/Products/Applications/Claude Status Bar.app/Contents/MacOS/Claude Status Bar"
```

> 如果 `xcode-select -p` 指向 Command Line Tools，需通过 `sudo xcode-select --switch` 切换到完整 Xcode，或设置环境变量 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

## 项目结构

```
Sources/
├── main.swift                 # 应用入口
├── AppDelegate.swift          # 应用代理，LSUIElement 应用初始化
├── StatusBarController.swift  # 菜单栏 UI 控制器，菜单构建和交互
└── StatusService.swift        # 三个服务类：Claude/Foxcode/ZENMUX

Resources/
└── Info.plist

Assets.xcassets/               # 应用图标资源
project.yml                    # XcodeGen 项目配置
CLAUDE.md                      # 开发者文档
```

## 架构

| 层 | 组件 | 职责 |
|---|---|---|
| 服务层 | `StatusService` | 请求 status.claude.com API，解析组件状态 |
| 服务层 | `FoxcodeStatusService` | 请求 Foxcode 状态页和心跳 API，合并监控数据 |
| 服务层 | `ZenmuxService` | 管理 Keychain 中的 API Key，请求订阅详情 |
| UI 层 | `StatusBarController` | NSStatusBar 菜单管理，定时刷新，事件响应 |
| UI 层 | `ComponentStatusView` | Claude 组件行：名称 + 健康条 + 状态文字 |
| UI 层 | `FoxcodeMonitorView` | Foxcode 监控行：名称 + 状态 + 延迟 |
| UI 层 | `ZenmuxQuotaView` | 配额进度条：已用/剩余 flows 可视化 |

### 关键设计

- **LSUIElement** — 无 Dock 图标，纯菜单栏应用。需手动创建隐藏的 Edit 主菜单以支持 NSAlert 中文本框的 Command+C/V 快捷键
- **Touch ID 保护** — ZENMUX API Key 通过 `SecAccessControl` + `.userPresence` 存入 Keychain，每次读取需 Touch ID 验证
- **架构支持** — 显式声明 `ARCHS: "arm64 x86_64"`，支持构建 Universal Binary 或单架构版本

## 开发

详见 [CLAUDE.md](./CLAUDE.md) 获取完整开发者文档，包括设计决策和开发日志。

## License

MIT
