import AppKit
import ServiceManagement
import SwiftUI

/// First-run setup: connect Claude Code, Launch at Login, and Terminal control.
/// Shown once after install and again from "Setup..." in the menu.
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to NotchBar"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: OnboardingView { [weak window] in window?.close() })
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // A menu bar app activating at launch can lose the race to the frontmost app;
        // order the window front again once activation has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.orderFrontRegardless()
            self?.window?.makeKey()
        }
    }
}

private final class OnboardingModel: ObservableObject {
    @Published var claudeConnected = ClaudeSetup.isConnected
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var terminal = TerminalFocus.automationStatus()
    @Published var error: String?
    @Published var requestingTerminal = false

    let claudeInstalled = ClaudeSetup.isClaudeInstalled
    let canConnect = !AppMover.isTranslocated

    func refresh() {
        claudeConnected = ClaudeSetup.isConnected
        launchAtLogin = SMAppService.mainApp.status == .enabled
        terminal = TerminalFocus.automationStatus()
    }

    func toggleClaude() {
        do {
            claudeConnected ? try ClaudeSetup.disconnect() : try ClaudeSetup.connect()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
            error = nil
        } catch {
            self.error = "Couldn't change Launch at Login: \(error.localizedDescription)"
        }
        refresh()
    }

    func requestTerminal() {
        if terminal == .denied {
            TerminalFocus.openAutomationSettings()
            return
        }
        requestingTerminal = true
        TerminalFocus.requestAutomation { [weak self] status in
            self?.terminal = status
            self?.requestingTerminal = false
        }
    }
}

private struct OnboardingView: View {
    @StateObject private var model = OnboardingModel()
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NotchBar is running")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Look for it in the menu bar. Click it to open the panel, right-click for settings.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 22)

            VStack(spacing: 0) {
                SetupRow(
                    symbol: "sparkle",
                    tint: ClaudeStore.accent,
                    title: "Connect Claude Code",
                    detail: claudeDetail
                ) {
                    if model.claudeInstalled && model.canConnect {
                        if model.claudeConnected {
                            Button("Disconnect", action: model.toggleClaude)
                        } else {
                            Button("Connect", action: model.toggleClaude)
                                .buttonStyle(.borderedProminent)
                                .tint(ClaudeStore.accent)
                        }
                    }
                } status: {
                    StatusBadge(ok: model.claudeConnected, text: model.claudeConnected ? "Connected" : nil)
                }

                Divider().padding(.leading, 48)

                SetupRow(
                    symbol: "power",
                    tint: .green,
                    title: "Open at login",
                    detail: "Start NotchBar automatically when you log in. macOS lists it under Login Items."
                ) {
                    Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                        .toggleStyle(.switch)
                        .labelsHidden()
                } status: {
                    EmptyView()
                }

                Divider().padding(.leading, 48)

                SetupRow(
                    symbol: "terminal",
                    tint: .blue,
                    title: "Jump to terminal tabs",
                    detail: terminalDetail
                ) {
                    if model.terminal != .allowed {
                        Button(model.terminal == .denied ? "Open Settings" : "Allow", action: model.requestTerminal)
                            .disabled(model.requestingTerminal)
                    }
                } status: {
                    StatusBadge(ok: model.terminal == .allowed, text: model.terminal == .allowed ? "Allowed" : nil)
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(nsColor: .separatorColor)))

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label {
                Text("NotchBar never needs Accessibility, Screen Recording or internet access. Everything stays on this Mac.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Reopen this from Setup... in the menu bar item's right-click menu.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 22)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var claudeDetail: String {
        if !model.claudeInstalled {
            return "Claude Code isn't installed yet (no ~/.claude folder). Install it, then come back here."
        }
        if !model.canConnect {
            return "Move NotchBar to Applications first, then reopen it."
        }
        return "See working, waiting and done sessions, and approve tool calls from the island. Adds hooks to ~/.claude/settings.json and saves a backup first."
    }

    private var terminalDetail: String {
        switch model.terminal {
        case .allowed: return "Click a session in the panel to bring its Terminal tab to the front."
        case .denied: return "Turned off. Enable NotchBar under Terminal in Privacy & Security > Automation."
        case .notAsked, .notRunning: return "Optional. macOS will ask once whether NotchBar may control Terminal, so a click on a session can bring its tab to the front."
        }
    }
}

private struct SetupRow<Action: View, Status: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let action: Action
    @ViewBuilder let status: Status

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    status
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action
                .frame(minHeight: 30)
        }
        .padding(.vertical, 14)
    }
}

private struct StatusBadge: View {
    let ok: Bool
    let text: String?

    var body: some View {
        if ok, let text {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        }
    }
}
