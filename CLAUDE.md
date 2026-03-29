# Claude Status Bar

macOS 菜单栏状态监控应用，用于实时查看 Claude、Foxcode、ZENMUX 等服务的运行状态。

## 项目概述

- **类型**：macOS Menu Bar 应用（LSUIElement，无 Dock 图标）
- **语言**：Swift 5.9，纯 AppKit（无 SwiftUI）
- **最低版本**：macOS 12.0
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

# 使用 Xcode 构建运行
open ClaudeStatusBar.xcodeproj
```

## 开发日志

### 2026-03-29：ZENMUX 渠道优化
- **修复粘贴问题**：LSUIElement 应用缺少 Edit 菜单导致 Command+C/V 不工作。在 AppDelegate 中添加隐藏的 Edit 主菜单（Cut/Copy/Paste/Select All），并设置 NSAlert 的 `initialFirstResponder` 确保文本框自动获焦
- **添加 Touch ID 支持**：Keychain 保存 API Key 时使用 `SecAccessControlCreateWithFlags` + `.userPresence`，读取时自动弹出 Touch ID 验证，替代原来的 Keychain 密码弹窗
