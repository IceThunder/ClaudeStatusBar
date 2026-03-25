import AppKit

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let statusService = StatusService.shared
    private let foxcodeService = FoxcodeStatusService.shared
    private var cachedComponents: [Component] = []
    private var cachedFoxcodeMonitors: [FoxcodeMonitor] = []
    private var isLoading = false
    private var lastFetchTime: Date?
    private var autoRefreshTimer: Timer?
    private var relativeTimeTimer: Timer?

    private var lastFetchMenuItem: NSMenuItem?

    override init() {
        super.init()
        setupStatusItem()
        setupAutoRefresh()
    }

    deinit {
        autoRefreshTimer?.invalidate()
        relativeTimeTimer?.invalidate()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Claude Status")
            button.image?.isTemplate = true
        }

        rebuildMenu()
        fetchStatus()
    }

    private func setupAutoRefresh() {
        autoRefreshTimer?.invalidate()
        let interval: TimeInterval = 300
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.fetchStatusWithoutMenuRebuild()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }

    private func fetchStatusWithoutMenuRebuild() {
        let group = DispatchGroup()

        group.enter()
        statusService.fetchComponents { [weak self] components in
            self?.cachedComponents = components
            group.leave()
        }

        group.enter()
        foxcodeService.fetchStatus { [weak self] monitors in
            self?.cachedFoxcodeMonitors = monitors
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.lastFetchTime = Date()
            self?.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let titleItem = NSMenuItem(title: "Claude 状态", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "刷新状态", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // Last fetch time item
        lastFetchMenuItem = NSMenuItem(title: lastFetchTimeText(), action: nil, keyEquivalent: "")
        lastFetchMenuItem?.isEnabled = false
        menu.addItem(lastFetchMenuItem!)

        menu.addItem(NSMenuItem.separator())

        if isLoading {
            let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        } else if cachedComponents.isEmpty {
            let errorItem = NSMenuItem(title: "无法获取状态", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        } else {
            for component in cachedComponents {
                let menuItem = NSMenuItem()
                menuItem.isEnabled = false

                let view = ComponentStatusView(component: component)
                menuItem.view = view
                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Foxcode 状态
        let foxcodeTitleItem = NSMenuItem(title: "Foxcode 状态", action: nil, keyEquivalent: "")
        foxcodeTitleItem.isEnabled = false
        menu.addItem(foxcodeTitleItem)

        menu.addItem(NSMenuItem.separator())

        if cachedFoxcodeMonitors.isEmpty {
            let errorItem = NSMenuItem(title: "无法获取 Foxcode 状态", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        } else {
            for monitor in cachedFoxcodeMonitors {
                let menuItem = NSMenuItem()
                menuItem.isEnabled = false

                let view = FoxcodeMonitorView(monitor: monitor)
                menuItem.view = view
                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func lastFetchTimeText() -> String {
        guard let lastFetch = lastFetchTime else {
            return "尚未获取"
        }

        let interval = max(0, Int(Date().timeIntervalSince(lastFetch)))

        if interval < 60 {
            return "\(interval)秒前获取"
        }

        let minutes = interval / 60
        return "\(minutes)分钟前获取"
    }

    private func updateLastFetchMenuItem() {
        lastFetchMenuItem?.title = lastFetchTimeText()
    }

    private func startRelativeTimeTimer() {
        stopRelativeTimeTimer()

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLastFetchMenuItem()
        }
        RunLoop.main.add(timer, forMode: .common)
        relativeTimeTimer = timer
    }

    private func stopRelativeTimeTimer() {
        relativeTimeTimer?.invalidate()
        relativeTimeTimer = nil
    }

    @objc private func refreshStatus() {
        fetchStatus()
    }

    private func fetchStatus() {
        isLoading = true
        cachedComponents = []
        cachedFoxcodeMonitors = []
        rebuildMenu()

        let group = DispatchGroup()

        group.enter()
        statusService.fetchComponents { [weak self] components in
            self?.cachedComponents = components
            group.leave()
        }

        group.enter()
        foxcodeService.fetchStatus { [weak self] monitors in
            self?.cachedFoxcodeMonitors = monitors
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            self?.lastFetchTime = Date()
            self?.rebuildMenu()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateLastFetchMenuItem()
        startRelativeTimeTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopRelativeTimeTimer()
    }
}

// MARK: - Component Status View

class ComponentStatusView: NSView {
    private let component: Component
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusBar = StatusHealthBar()
    private let statusLabel = NSTextField(labelWithString: "")

    init(component: Component) {
        self.component = component
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Name label
        nameLabel.stringValue = getDisplayName(for: component.name)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.sizeToFit()

        // Status bar
        statusBar.status = component.status
        statusBar.frame = NSRect(x: 0, y: 0, width: 60, height: 8)

        // Status text label
        statusLabel.stringValue = getStatusText(for: component.status)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.sizeToFit()

        addSubview(nameLabel)
        addSubview(statusBar)
        addSubview(statusLabel)

        nameLabel.frame = NSRect(x: 16, y: 28, width: nameLabel.frame.width, height: nameLabel.frame.height)
        statusBar.frame = NSRect(x: 16, y: 12, width: 60, height: 8)
        statusLabel.frame = NSRect(x: 82, y: 10, width: statusLabel.frame.width, height: statusLabel.frame.height)
    }

    private func getStatusText(for status: String) -> String {
        switch status {
        case "operational": return "正常"
        case "degraded_performance": return "性能下降"
        case "partial_outage": return "部分故障"
        case "major_outage": return "重大故障"
        default: return "未知"
        }
    }

    private func getDisplayName(for name: String) -> String {
        switch name {
        case "claude.ai": return "Claude.ai"
        case "platform.claude.com": return "Platform"
        case "Claude API (api.anthropic.com)": return "Claude API"
        case "Claude Code": return "Claude Code"
        case "Claude for Government": return "Government"
        default: return name
        }
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 280, height: 44)
    }
}

// MARK: - Status Health Bar

class StatusHealthBar: NSView {
    var status: String = "operational" {
        didSet { needsDisplay = true }
    }

    private let segmentCount = 10

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let segmentWidth = bounds.width / CGFloat(segmentCount)
        let segmentHeight = bounds.height
        let cornerRadius: CGFloat = 2

        // Background (gray - no data/unknown)
        NSColor.systemGray.withAlphaComponent(0.3).setFill()
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        bgPath.fill()

        // Colored segments based on status
        let color = getStatusColor()
        color.setFill()

        // Draw filled segments (showing health)
        let filledCount = getFilledSegmentCount()
        for i in 0..<filledCount {
            let rect = NSRect(
                x: CGFloat(i) * segmentWidth + 1,
                y: 0,
                width: segmentWidth - 2,
                height: segmentHeight
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            path.fill()
        }
    }

    private func getStatusColor() -> NSColor {
        switch status {
        case "operational":
            return NSColor.systemGreen
        case "degraded_performance":
            return NSColor.systemYellow
        case "partial_outage":
            return NSColor.systemOrange
        case "major_outage":
            return NSColor.systemRed
        default:
            return NSColor.systemGray
        }
    }

    private func getFilledSegmentCount() -> Int {
        switch status {
        case "operational": return 10
        case "degraded_performance": return 7
        case "partial_outage": return 4
        case "major_outage": return 1
        default: return 0
        }
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 60, height: 8)
    }
}

// MARK: - Foxcode Monitor View

class FoxcodeMonitorView: NSView {
    private let monitor: FoxcodeMonitor
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusBar = StatusHealthBar()
    private let statusLabel = NSTextField(labelWithString: "")

    init(monitor: FoxcodeMonitor) {
        self.monitor = monitor
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Name label
        nameLabel.stringValue = monitor.name
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.sizeToFit()

        // Status bar
        statusBar.status = monitor.status == 1 ? "operational" : "major_outage"
        statusBar.frame = NSRect(x: 0, y: 0, width: 60, height: 8)

        // Status text label
        if monitor.status == 1 {
            if let ping = monitor.ping {
                statusLabel.stringValue = "在线 \(ping)ms"
            } else {
                statusLabel.stringValue = "在线"
            }
        } else {
            statusLabel.stringValue = "离线"
        }
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.sizeToFit()

        addSubview(nameLabel)
        addSubview(statusBar)
        addSubview(statusLabel)

        nameLabel.frame = NSRect(x: 16, y: 28, width: nameLabel.frame.width, height: nameLabel.frame.height)
        statusBar.frame = NSRect(x: 16, y: 12, width: 60, height: 8)
        statusLabel.frame = NSRect(x: 82, y: 10, width: statusLabel.frame.width, height: statusLabel.frame.height)
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 280, height: 44)
    }
}
