import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let loginItemConfiguredKey = "loginItemConfigured"

    private let model = NotchViewModel()
    private let battery = BatteryMonitor()
    private var windowController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var menu = NSMenu()
    private var hoverItem: NSMenuItem?
    private var hideItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var statsItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        model.statusItemFrame = { [weak self] in self?.statusItem?.button?.window?.frame }
        model.refreshGeometry()
        windowController = NotchWindowController(model: model, battery: battery)
        configureLoginItemOnFirstLaunch()

        battery.onPowerSourceChange = { [weak self] battery in
            let level = battery.level.map { "\($0)%" } ?? ""
            self?.model.show(battery.isPluggedIn
                ? Toast(title: "Charging", subtitle: level, symbol: "bolt.fill", tint: .green)
                : Toast(title: "On Battery", subtitle: level, symbol: battery.symbol, tint: .orange))
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NotchCommand.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let command = NotchCommand.decode(notification) else { return }
            self?.handle(command)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.model.show(Toast(
                title: "NotchBar is running",
                subtitle: self?.model.geometry.isPhysical == true ? "Hover the notch to expand" : "Click the menu bar icon to expand",
                symbol: "sparkles",
                tint: .purple
            ))
        }
    }

    // MARK: - Commands

    private func handle(_ command: NotchCommand) {
        let claude = model.claude
        let session = command.session ?? "unknown"
        let project = command.project ?? "Claude"
        if ClaudeStore.isDemo && command.action.hasPrefix("claude.") && !session.hasPrefix("demo") { return }

        func update(_ status: ClaudeSession.Status, detail: String) {
            claude.update(
                session: session,
                project: project,
                status: status,
                detail: detail,
                tty: command.tty,
                term: command.term,
                bypassPermissions: command.bypassPermissions
            )
        }

        switch command.action {
        case "toast": model.show(command.toast)
        case "open": model.open()
        case "close": model.close()
        case "toggle": model.toggle()
        case "hide": setHidden(true)
        case "show": setHidden(false)

        case "claude.working":
            update(.working, detail: command.detail ?? "Working")
        case "claude.waiting":
            update(.waiting, detail: command.detail ?? "Waiting for you")
            if !claude.requests.contains(where: { $0.sessionId == session }) {
                showUnlessWatching(command, Toast(title: "Claude needs you", subtitle: "\(project) - \(command.detail ?? "Waiting for input")", symbol: "bubble.left.fill", tint: .orange))
            }
        case "claude.done":
            update(.done, detail: "Finished")
            showUnlessWatching(command, Toast(title: "Claude finished", subtitle: project, symbol: "checkmark.circle.fill", tint: .green))
        case "claude.end":
            claude.end(session: session)
        case "claude.permission":
            guard let id = command.requestId else { return }
            claude.add(PermissionRequest(
                id: id,
                sessionId: session,
                project: project,
                tool: command.tool ?? "tool",
                detail: command.detail ?? "",
                expiresAt: Date().addingTimeInterval((command.timeout ?? 120) + 5)
            ))
            NSSound(named: "Tink")?.play()
            model.open()
        case "claude.cancel":
            guard let id = command.requestId else { return }
            claude.removeRequest(id: id)
            if claude.requests.isEmpty && model.state == .open && model.isPinned {
                model.close()
            }
        default:
            break
        }
    }

    /// No banner when the session's own terminal tab is already in front of you.
    private func showUnlessWatching(_ command: NotchCommand, _ toast: Toast) {
        let session = model.claude.sessions.first { $0.id == command.session }
        TerminalFocus.isFrontmost(tty: command.tty ?? session?.tty, term: command.term ?? session?.term) { [weak self] watching in
            if !watching { self?.model.show(toast) }
        }
    }

    // MARK: - Status item (compact live activity)

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("NotchBar")

        menu.addItem(withTitle: "Toggle Island", action: #selector(toggleNotch), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "Send Test Alert", action: #selector(sendTestAlert), keyEquivalent: "a").target = self
        menu.addItem(withTitle: "Test Permission Card", action: #selector(sendTestPermission), keyEquivalent: "p").target = self
        menu.addItem(.separator())

        let hover = NSMenuItem(title: "Expand on Hover", action: #selector(toggleHover), keyEquivalent: "")
        hover.target = self
        hover.state = model.expandOnHover ? .on : .off
        menu.addItem(hover)
        hoverItem = hover

        if model.geometry.isPhysical {
            let hide = NSMenuItem(title: "Hide Notch When Idle", action: #selector(toggleHidden), keyEquivalent: "")
            hide.target = self
            menu.addItem(hide)
            hideItem = hide
        }

        let stats = NSMenuItem(title: "Show Stats in Menu Bar", action: #selector(toggleMenuBarStats), keyEquivalent: "")
        stats.target = self
        stats.state = showsMenuBarStats ? .on : .off
        menu.addItem(stats)
        statsItem = stats

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginItem = login

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem = item
        installStatusItemView()
        if showsMenuBarStats { SystemMonitor.shared.start() }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            model.toggle()
        }
    }

    private var showsMenuBarStats: Bool {
        UserDefaults.standard.object(forKey: StatusItemView.showStatsKey) as? Bool ?? true
    }

    /// SwiftUI content inside the status bar button; the item resizes to fit it.
    private func installStatusItemView() {
        guard let button = statusItem?.button else { return }
        let view = StatusItemView(claude: model.claude, monitor: .shared) { [weak self] width in
            guard let self, width > 0, self.statusItem?.length != width else { return }
            self.statusItem?.length = width
            DispatchQueue.main.async { self.model.refreshGeometry() }
        }
        let host = PassthroughHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = button.bounds
        host.autoresizingMask = [.width, .height]
        button.addSubview(host)
    }

    // MARK: - Menu actions

    @objc private func toggleNotch() {
        model.toggle()
    }

    @objc private func sendTestAlert() {
        let samples = [
            Toast(title: "Build passed", subtitle: "notchbar - 12.4s", symbol: "checkmark.circle.fill", tint: .green),
            Toast(title: "Deploy failed", subtitle: "Netlify - exit code 1", symbol: "xmark.octagon.fill", tint: .red),
            Toast(title: "Claude finished", subtitle: "my-website", symbol: "checkmark.circle.fill", tint: .green),
        ]
        model.show(samples.randomElement()!)
    }

    @objc private func sendTestPermission() {
        handle(NotchCommand(
            action: "claude.permission",
            session: "test",
            project: "notchbar",
            detail: "npm run build && npx tsc --noEmit",
            requestId: UUID().uuidString,
            tool: "Bash",
            timeout: 60
        ))
    }

    @objc private func toggleMenuBarStats() {
        let show = !showsMenuBarStats
        UserDefaults.standard.set(show, forKey: StatusItemView.showStatsKey)
        statsItem?.state = show ? .on : .off
        show ? SystemMonitor.shared.start() : SystemMonitor.shared.stop()
    }

    @objc private func toggleHover() {
        model.expandOnHover.toggle()
        hoverItem?.state = model.expandOnHover ? .on : .off
    }

    @objc private func toggleHidden() {
        setHidden(model.restingState != .hidden)
    }

    private func setHidden(_ hidden: Bool) {
        model.setHidden(hidden)
        hideItem?.state = hidden ? .on : .off
    }

    // MARK: - Launch at login

    private func configureLoginItemOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.loginItemConfiguredKey) else { return }
        if (try? SMAppService.mainApp.register()) != nil {
            defaults.set(true, forKey: Self.loginItemConfiguredKey)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            model.show(Toast(title: "Couldn't change login item", subtitle: error.localizedDescription, symbol: "exclamationmark.triangle.fill", tint: .red))
        }
        UserDefaults.standard.set(true, forKey: Self.loginItemConfiguredKey)
        loginItem?.state = service.status == .enabled ? .on : .off
    }
}
