import AppKit
import SwiftUI

/// Content of the menu bar item: Claude's live activity plus always-on CPU, memory and network.
struct StatusItemView: View {
    static let showStatsKey = "showStatsInMenuBar"

    @ObservedObject var claude: ClaudeStore
    @ObservedObject var monitor: SystemMonitor
    @AppStorage(StatusItemView.showStatsKey) private var showStats = true
    let onWidthChange: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 9) {
            if let badge = claudeBadge {
                HStack(spacing: 4) {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(badge.tint)
                    Text(badge.title)
                        .font(.system(size: 12, weight: .medium))
                }
            } else if !showStats {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 14))
            }

            if showStats {
                MenuBarStat(label: "CPU", value: monitor.cpuUsage, tint: MenuBarStat.tint(for: monitor.cpuUsage))
                MenuBarStat(label: "MEM", value: monitor.memoryUsage, tint: MenuBarStat.tint(for: monitor.memoryPressure))
                VStack(alignment: .trailing, spacing: -1) {
                    rate(arrow: "\u{2193}", value: monitor.downloadPerSecond)
                    rate(arrow: "\u{2191}", value: monitor.uploadPerSecond)
                }
                .frame(width: 58, alignment: .trailing)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .frame(height: NSStatusBar.system.thickness)
        .fixedSize()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: WidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthKey.self, perform: onWidthChange)
        .accessibilityElement(children: .combine)
    }

    private var claudeBadge: (symbol: String, title: String, tint: Color)? {
        if let request = claude.requests.first {
            return request.questions.isEmpty
                ? ("hand.raised.fill", "Approve", .orange)
                : ("questionmark.bubble.fill", "Question", .orange)
        }
        let working = claude.workingCount
        guard working > 0 else { return nil }
        return ("sparkle", working > 1 ? "\(working) working" : "Working", ClaudeStore.accent)
    }

    private func rate(arrow: String, value: Double?) -> some View {
        Text("\(arrow) \(SystemMonitor.formatRate(value))")
            .font(.system(size: 9, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
    }
}

private struct MenuBarStat: View {
    let label: String
    let value: Double?
    let tint: Color

    var body: some View {
        VStack(spacing: -1) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .opacity(0.7)
            Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "--")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(width: 30)
    }

    static func tint(for value: Double?) -> Color {
        switch value ?? 0 {
        case 0.9...: return .red
        case 0.75...: return .orange
        default: return .primary
        }
    }

    /// Memory warns on real pressure only; a high percent alone is normal on macOS.
    static func tint(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Hosting view that lets clicks fall through to the status bar button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
