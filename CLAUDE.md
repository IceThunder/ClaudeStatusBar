# Claude Status Bar

macOS 菜单栏状态监控应用，用于实时查看 Claude、Foxcode、ZENMUX 等服务的运行状态。

## 项目概述

- **类型**：macOS Menu Bar 应用（LSUIElement，无 Dock 图标）
- **语言**：Swift 5.9，纯 AppKit（无 SwiftUI）
- **最低版本**：macOS 12.0
- **架构**：支持 arm64（Apple Silicon）和 x86_64（Intel），可构建 Universal Binary 或单架构版本
- **Bundle ID**：`com.claudestatus.CaudeStatusBar`
- **项目管理**：使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 通过 `project.yml` 生成 Xcode 项目

## 项目结构

```
Sources/
├── main.swift                 # 应用入口
├── AppDelegate.swift          # 应用代理，初始化主菜单和控制器
├── StatusBarController.swift  # 菜单栏 UI 控制器，菜单构建和交互逻辑
└── StatusService.swift        # 三个服务类：StatusService、FoxcodeStatusService、ZenmuxService

Resources/
└── Info.plist

Assets.xcassets/               # 应用图标资源
project.yml                    # XcodeGen 配置
```

## 架构

### 服务层（StatusService.swift）
- **StatusService**：从 `status.claude.com` 获取 Claude 各组件状态
- **FoxcodeStatusService**：获取 Foxcode 监控状态
- **ZenmuxService**：管理 ZENMUX API Key（Keychain 存储，Touch ID 保护）并获取订阅详情

### UI 层（StatusBarController.swift）
- 菜单栏图标和下拉菜单
- 自定义 NSView：ComponentStatusView、FoxcodeMonitorView、ZenmuxQuotaView
- 进度条通过 CALayer 实现
- 每 5 分钟自动刷新

### 关键设计决策
- LSUIElement 应用需要在 AppDelegate 中手动创建 Edit 主菜单，否则 NSAlert 中的文本框无法响应 Command+C/V 等快捷键
- ZENMUX API Key 使用 Keychain + SecAccessControl（`.userPresence`）存储，启动时通过 Touch ID 验证访问
- API Key 输入使用 NSAlert + NSSecureTextField，需设置 `initialFirstResponder` 确保文本框获焦

## 构建和运行

```bash
# 使用 XcodeGen 生成项目（如有修改 project.yml）
xcodegen generate

# 使用 Xcode 构建运行（Debug）
open ClaudeStatusBar.xcodeproj
```

### 命令行构建

```bash
# Universal Binary（arm64 + x86_64）
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath ./build/ClaudeStatusBar.xcarchive archive

# 仅 M 系列 (arm64)
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS=arm64 -archivePath ./build/arm64/ClaudeStatusBar.xcarchive archive

# 仅 Intel (x86_64)
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS=x86_64 -archivePath ./build/x86_64/ClaudeStatusBar.xcarchive archive

# 验证产物架构
lipo -info "./build/ClaudeStatusBar.xcarchive/Products/Applications/Claude Status Bar.app/Contents/MacOS/Claude Status Bar"
```

> **注意**：如果 `xcode-select -p` 指向 Command Line Tools，需先切换到完整 Xcode：
> ```bash
> sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
> ```
> 或使用 `DEVELOPER_DIR` 环境变量指向 Xcode 路径。

## 开发日志

### 2026-04-24：x86_64 架构支持
- **问题**：项目缺少显式 `ARCHS` 设置，Debug 配置 `ONLY_ACTIVE_ARCH=YES` 导致在 M 系列 Mac 上仅编译 arm64，无法在 Intel Mac 运行
- **修复**：在 `project.yml` 中显式设置 `ARCHS: "arm64 x86_64"`，Release 配置 `ONLY_ACTIVE_ARCH: NO`
- **注意**：`$(ARCHS_STANDARD)` 在 Intel Mac 上仅解析为 x86_64，因此直接硬编码双架构值；构建需使用 `-destination 'generic/platform=macOS'` 而非默认的 "My Mac" 目标
- **项目格式**：将 `objectVersion` 从 77 降至 56，兼容 Xcode 15.x

### 2026-03-29：ZENMUX 渠道优化
- **修复粘贴问题**：LSUIElement 应用缺少 Edit 菜单导致 Command+C/V 不工作。在 AppDelegate 中添加隐藏的 Edit 主菜单（Cut/Copy/Paste/Select All），并设置 NSAlert 的 `initialFirstResponder` 确保文本框自动获焦
- **添加 Touch ID 支持**：Keychain 保存 API Key 时使用 `SecAccessControlCreateWithFlags` + `.userPresence`，读取时自动弹出 Touch ID 验证，替代原来的 Keychain 密码弹窗
