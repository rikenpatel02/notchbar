import AppKit
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        let size = model.size

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                island
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(Color.black)
                    .clipShape(islandShape)
                    .overlay(
                        islandShape.stroke(.white.opacity(model.geometry.isPhysical ? 0 : 0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(model.state == .open || !model.geometry.isPhysical ? 0.45 : 0), radius: 20, y: 10)
                    .opacity(size.height > 0 ? 1 : 0)
                    .contentShape(islandShape)
                    .onTapGesture { model.toggle() }
                    .padding(.leading, model.islandX)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(model.animation, value: model.state)
        .animation(model.animation, value: model.layoutKey)
        .environment(\.colorScheme, .dark)
    }

    private var islandShape: AnyShape {
        let radii = model.radii
        if model.geometry.isPhysical {
            return AnyShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        }
        return AnyShape(RoundedRectangle(cornerRadius: radii.bottom, style: .continuous))
    }

    @ViewBuilder
    private var island: some View {
        ZStack(alignment: .top) {
            switch model.state {
            case .open:
                Group {
                    if let request = model.claude.requests.first, !request.questions.isEmpty {
                        QuestionCard(model: model, request: request)
                            .id(request.id)
                    } else if let request = model.claude.requests.first {
                        PermissionCard(model: model, request: request)
                    } else {
                        ExpandedContent(model: model, battery: battery)
                    }
                }
                .transition(contentTransition)
            case .peek:
                if let toast = model.toast {
                    PeekContent(toast: toast, geometry: model.geometry)
                        .transition(contentTransition)
                }
            case .closed, .hidden:
                if model.geometry.isPhysical && model.claude.hasActivity {
                    ClosedActivity(claude: model.claude, notch: model.geometry.notchSize)
                        .transition(contentTransition)
                }
            }
        }
    }

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .top))
                .animation(.easeOut(duration: 0.22).delay(0.08)),
            removal: .opacity.animation(.easeIn(duration: 0.1))
        )
    }
}

/// Header row: sits beside the hardware notch, or along the top of a drop-down island.
private struct HeaderRow<Leading: View, Trailing: View>: View {
    let geometry: NotchGeometry
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer(minLength: geometry.isPhysical ? geometry.notchSize.width + 12 : 8)
            trailing
        }
        .font(.system(size: 12, weight: .medium))
        .frame(height: geometry.isPhysical ? geometry.notchSize.height : 34)
        .padding(.top, geometry.isPhysical ? 0 : 8)
        .padding(.horizontal, geometry.isPhysical ? 30 : 22)
    }
}

// MARK: - Peek

private struct PeekContent: View {
    let toast: Toast
    let geometry: NotchGeometry

    var body: some View {
        if geometry.isPhysical {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    icon
                    Spacer()
                    PulseDot(tint: toast.tint)
                }
                .frame(height: geometry.notchSize.height)
                text
            }
            .padding(.horizontal, 24)
        } else {
            HStack(spacing: 12) {
                icon
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(toast.tint.opacity(0.18)))
                text
                Spacer(minLength: 0)
                PulseDot(tint: toast.tint)
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
        }
    }

    private var icon: some View {
        Image(systemName: toast.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(toast.tint)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(toast.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if !toast.subtitle.isEmpty {
                Text(toast.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .lineLimit(1)
    }
}

private struct PulseDot: View {
    let tint: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 7, height: 7)
            .background(
                Circle()
                    .fill(tint.opacity(0.4))
                    .scaleEffect(pulsing ? 2.4 : 1)
                    .opacity(pulsing ? 0 : 1)
            )
            .onAppear {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Claude

/// Compact live activity in the ears beside a hardware notch.
private struct ClosedActivity: View {
    @ObservedObject var claude: ClaudeStore
    let notch: CGSize

    var body: some View {
        HStack {
            ClaudeSpinner(active: claude.workingCount > 0)
            Spacer(minLength: notch.width)
            if !claude.requests.isEmpty {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            } else {
                Text("\(claude.workingCount)")
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .frame(height: notch.height)
        .padding(.horizontal, 16)
    }
}

private struct ClaudeSpinner: View {
    let active: Bool
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(ClaudeStore.accent)
            .rotationEffect(.degrees(angle))
            .onAppear(perform: spin)
            .onChange(of: active) { _ in spin() }
    }

    private func spin() {
        guard active, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            angle = 0
            return
        }
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}

private struct PermissionCard: View {
    @ObservedObject var model: NotchViewModel
    let request: PermissionRequest

    var body: some View {
        let total = model.claude.requests.count

        VStack(spacing: 0) {
            HeaderRow(geometry: model.geometry) {
                Label("Claude Code", systemImage: "sparkle")
                    .foregroundStyle(ClaudeStore.accent)
            } trailing: {
                Text(total > 1 ? "\(request.project)  1 of \(total)" : request.project)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Text("Allow \(request.tool)?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(request.detail.isEmpty ? request.tool : request.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Deny") { decide(allow: false) }
                        .buttonStyle(CapsuleButtonStyle(fill: .white.opacity(0.1), text: .red))
                        .accessibilityLabel("Deny \(request.tool)")
                    Button("Approve") { decide(allow: true) }
                        .buttonStyle(CapsuleButtonStyle(fill: .green, text: .black))
                        .accessibilityLabel("Approve \(request.tool)")
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func decide(allow: Bool) {
        model.claude.resolve(request, allow: allow)
        if model.claude.requests.isEmpty {
            model.close()
        }
    }
}

/// Claude's multiple-choice question (AskUserQuestion). With one single-choice question, clicking
/// an option answers it; otherwise pick an option per question and press Submit.
private struct QuestionCard: View {
    @ObservedObject var model: NotchViewModel
    let request: PermissionRequest

    @State private var picked: [Int: [String]] = [:]

    private var answersImmediately: Bool {
        request.questions.count == 1 && request.questions[0].multiSelect != true
    }

    private var isComplete: Bool {
        request.questions.indices.allSatisfy { !(picked[$0] ?? []).isEmpty }
    }

    var body: some View {
        let total = model.claude.requests.count

        VStack(spacing: 0) {
            HeaderRow(geometry: model.geometry) {
                Label("Claude Code", systemImage: "sparkle")
                    .foregroundStyle(ClaudeStore.accent)
            } trailing: {
                Text(total > 1 ? "\(request.project)  1 of \(total)" : request.project)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(request.questions.enumerated()), id: \.offset) { index, question in
                            questionView(index, question)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Answer in Terminal") { answerInTerminal() }
                        .buttonStyle(CapsuleButtonStyle(fill: .white.opacity(0.1), text: .white.opacity(0.85)))
                        .help("Type your own answer in Claude Code")
                    Spacer()
                    if !answersImmediately {
                        Button("Submit") { submit() }
                            .buttonStyle(CapsuleButtonStyle(fill: isComplete ? .green : .white.opacity(0.1),
                                                            text: isComplete ? .black : .white.opacity(0.4)))
                            .disabled(!isComplete)
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 4)
            .padding(.bottom, 14)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func questionView(_ index: Int, _ question: ClaudeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill")
                    .foregroundStyle(ClaudeStore.accent)
                Text(question.question)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if question.multiSelect == true {
                    Text("Choose any")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            ForEach(question.options, id: \.self) { option in
                OptionRow(option: option,
                          selected: (picked[index] ?? []).contains(option.label),
                          multiSelect: question.multiSelect == true) {
                    choose(option.label, for: index, multiSelect: question.multiSelect == true)
                }
            }
        }
    }

    private func choose(_ label: String, for index: Int, multiSelect: Bool) {
        if multiSelect {
            var current = picked[index] ?? []
            if let at = current.firstIndex(of: label) { current.remove(at: at) } else { current.append(label) }
            picked[index] = current
        } else {
            picked[index] = [label]
        }
        if answersImmediately { submit() }
    }

    private func submit() {
        guard isComplete else { return }
        var answers: [String: String] = [:]
        for (index, question) in request.questions.enumerated() {
            let order = question.options.map(\.label)
            let labels = (picked[index] ?? []).sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            answers[question.question] = labels.joined(separator: ", ")
        }
        model.claude.answer(request, with: answers)
        closeIfDone()
    }

    private func answerInTerminal() {
        let session = model.claude.sessions.first { $0.id == request.sessionId }
        model.claude.answerInTerminal(request)
        closeIfDone()
        if let session {
            TerminalFocus.focus(tty: session.tty, term: session.term) {}
        }
    }

    private func closeIfDone() {
        if model.claude.requests.isEmpty {
            model.close()
        }
    }
}

private struct OptionRow: View {
    let option: ClaudeQuestion.Option
    let selected: Bool
    let multiSelect: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected
                      ? (multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (multiSelect ? "square" : "circle"))
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? ClaudeStore.accent : .white.opacity(0.4))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? ClaudeStore.accent.opacity(0.22) : .white.opacity(hovering ? 0.12 : 0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(option.description.map { "\(option.label). \($0)" } ?? option.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CapsuleButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(Capsule().fill(fill))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Click to bring the session's terminal tab to the front.
private struct SessionRow: View {
    let session: ClaudeSession
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(session.project)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(session.detail)
                    .font(.system(size: 11, design: session.status == .working ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 8)
                if session.bypassPermissions {
                    Image(systemName: "bolt.shield")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .help("Skips permission prompts (--dangerously-skip-permissions), so it never asks for approval here")
                }
                status
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Show in terminal")
        .accessibilityLabel("\(session.project), \(label). Show in terminal")
    }

    @ViewBuilder
    private var status: some View {
        if session.status == .working, let since = session.workingSince {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.elapsed(from: since, to: context.date))
            }
        } else {
            Text(label)
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }

    private var tint: Color {
        switch session.status {
        case .working: return ClaudeStore.accent
        case .waiting: return .orange
        case .done: return .green
        case .idle: return .gray
        }
    }

    private var label: String {
        switch session.status {
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .done: return "Done"
        case .idle: return "Idle"
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        VStack(spacing: 0) {
            HeaderRow(geometry: model.geometry) {
                HStack(spacing: 8) {
                    HeaderIconButton(title: "Downloads", symbol: "arrow.down.circle") {
                        openURL(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                    }
                    HeaderIconButton(title: "Capture", symbol: "camera.viewfinder") {
                        openURL(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
                    }
                    HeaderIconButton(title: "Settings", symbol: "gearshape") {
                        openURL(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                    }
                }
            } trailing: {
                if let level = battery.level {
                    HStack(spacing: 5) {
                        Text("\(level)%").monospacedDigit()
                        Image(systemName: battery.symbol)
                            .foregroundStyle(batteryTint(level))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }

            HStack(alignment: .center) {
                ClockView()
                Spacer(minLength: 12)
                LiveStats()
            }
            .padding(.horizontal, model.geometry.isPhysical ? 34 : 24)
            .frame(height: 100)

            TopApps()
                .padding(.horizontal, model.geometry.isPhysical ? 34 : 24)

            if !model.claude.sessions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.claude.sessions.prefix(4)) { session in
                        SessionRow(session: session) {
                            model.close()
                            TerminalFocus.focus(tty: session.tty, term: session.term) {
                                model.show(Toast(
                                    title: "Allow NotchBar to control Terminal",
                                    subtitle: "Privacy & Security > Automation",
                                    symbol: "lock.fill",
                                    tint: .orange
                                ), duration: 5)
                                TerminalFocus.openAutomationSettings()
                            }
                        }
                    }
                }
                .padding(.horizontal, model.geometry.isPhysical ? 26 : 16)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }

    private func batteryTint(_ level: Int) -> Color {
        if battery.isCharging { return .green }
        return level < 20 ? .red : .white.opacity(0.85)
    }

    /// Opens off the main thread: Launch Services can block while macOS asks for folder
    /// access (Downloads), and the prompt must not sit behind a frozen island.
    private func openURL(_ url: URL) {
        model.close()
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }
}

/// CPU and memory gauges plus network throughput, updated every second while visible.
private struct LiveStats: View {
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StatGauge(title: "CPU", value: monitor.cpuUsage, tint: StatGauge.tint(for: monitor.cpuUsage))
            StatGauge(
                title: "Memory",
                value: monitor.memoryUsage,
                tint: StatGauge.tint(for: monitor.memoryPressure),
                caption: monitor.swapUsedBytes > 0 ? "Swap \(SystemMonitor.formatBytes(monitor.swapUsedBytes))" : nil,
                captionTint: monitor.isSwapHigh ? .orange : .white.opacity(0.45)
            )
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    rate(symbol: "arrow.down", value: monitor.downloadPerSecond, tint: .cyan)
                    rate(symbol: "arrow.up", value: monitor.uploadPerSecond, tint: .pink)
                }
                .frame(width: 92, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
                Text("Network")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityElement(children: .combine)
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func rate(symbol: String, value: Double?, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(SystemMonitor.formatRate(value))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

private struct StatGauge: View {
    let title: String
    let value: Double?
    let tint: Color
    var caption: String? = nil
    var captionTint: Color = .white.opacity(0.45)

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: value ?? 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: value)
                Text(value.map { "\(Int(($0 * 100).rounded()))" } ?? "--")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            if let caption {
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(captionTint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, -4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue((value.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Loading") + (caption.map { ", \($0)" } ?? ""))
    }

    static func tint(for value: Double?) -> Color {
        switch value ?? 0 {
        case ..<0.6: return .green
        case ..<0.85: return .orange
        default: return .red
        }
    }

    /// Memory is judged by pressure, not percent: macOS keeps RAM full on purpose.
    static func tint(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// The three apps using the most memory or CPU, with a two-step Quit on hover.
private struct TopApps: View {
    @ObservedObject private var monitor = ProcessMonitor.shared
    @State private var byMemory = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Top apps")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                HStack(spacing: 2) {
                    tab("Memory", selected: byMemory) { byMemory = true }
                    tab("CPU", selected: !byMemory) { byMemory = false }
                }
                .padding(2)
                .background(Capsule().fill(.white.opacity(0.07)))
            }
            .frame(height: 22)

            let top = monitor.top(by: byMemory)
            ForEach(top) { usage in
                AppUsageRow(usage: usage, byMemory: byMemory)
            }
            if top.isEmpty {
                Text("Measuring...")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(height: 24)
            }
        }
        .frame(height: 104, alignment: .top)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
                .padding(.horizontal, 9)
                .frame(height: 18)
                .background(Capsule().fill(.white.opacity(selected ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AppUsageRow: View {
    let usage: AppUsage
    let byMemory: Bool

    @State private var hovering = false
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 16, height: 16)
            Text(usage.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            if usage.pids.count > 1 {
                Text("\(usage.pids.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                    .help("\(usage.pids.count) processes")
            }
            Spacer(minLength: 8)
            if hovering || confirming {
                Button(confirming ? "Quit?" : "Quit") {
                    if confirming {
                        ProcessMonitor.shared.quit(usage)
                        confirming = false
                    } else {
                        confirming = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(confirming ? .white : .red)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(confirming ? Color.red : .white.opacity(0.1)))
                .accessibilityLabel(confirming ? "Confirm quit \(usage.name)" : "Quit \(usage.name)")
            }
            Text(byMemory ? SystemMonitor.formatBytes(usage.memoryBytes) : "\(Int((usage.cpu * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 58, alignment: .trailing)
        }
        .frame(height: 26)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if !inside { confirming = false }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: confirming)
    }

    @ViewBuilder
    private var icon: some View {
        if let path = usage.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct HeaderIconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(hovering ? 0.18 : 0.09)))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
