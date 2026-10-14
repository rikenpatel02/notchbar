import AppKit
import Combine
import SwiftUI

enum NotchState {
    /// Notch: collapsed out of sight. Menu bar mode: nothing below the menu bar.
    case hidden
    /// Resting: matches the hardware notch, or collapsed into the status item.
    case closed
    /// Short-lived "live activity" banner.
    case peek
    /// Fully expanded panel.
    case open
}

struct Toast: Equatable {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
}

/// Where the island lives.
/// - Notched Macs: wrapped around the hardware notch (dead space, covers nothing).
/// - Other Macs: macOS Tahoe style. The compact view is a menu bar item and the
///   expanded view drops down below the menu bar, so no menu bar icons are covered.
struct NotchGeometry: Equatable {
    var notchSize: CGSize
    var screenFrame: CGRect
    var isPhysical: Bool
    /// Screen y of the island's top edge.
    var top: CGFloat
    /// Screen x the island centers on.
    var anchorX: CGFloat

    static func current(statusItemFrame: NSRect?) -> NotchGeometry {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            return NotchGeometry(
                notchSize: CGSize(width: screen.frame.width - left - right, height: screen.safeAreaInsets.top),
                screenFrame: screen.frame,
                isPhysical: true,
                top: screen.frame.maxY,
                anchorX: screen.frame.midX
            )
        }

        let anchorScreen = statusItemFrame.flatMap { frame in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
        }
        guard let screen = anchorScreen ?? NSScreen.screens.first else {
            return NotchGeometry(notchSize: .zero, screenFrame: .zero, isPhysical: false, top: 0, anchorX: 0)
        }
        let menuBarBottom = statusItemFrame?.minY
            ?? screen.frame.maxY - max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        return NotchGeometry(
            notchSize: .zero,
            screenFrame: screen.frame,
            isPhysical: false,
            top: menuBarBottom - 6,
            anchorX: statusItemFrame?.midX ?? screen.frame.midX
        )
    }
}

final class NotchViewModel: ObservableObject {
    private static let edgeInset: CGFloat = 10
    private static let topAppsHeight: CGFloat = 104

    @Published private(set) var state: NotchState = .closed
    @Published private(set) var toast: Toast?
    @Published private(set) var restingState: NotchState = .closed
    /// Opened explicitly (click, menu, CLI) rather than by hover; stays open until an outside click.
    @Published private(set) var isPinned = false
    @Published var expandOnHover = true
    @Published private(set) var geometry = NotchGeometry.current(statusItemFrame: nil)

    let claude = ClaudeStore()
    /// Supplies the status item's screen frame so menu bar mode can anchor under it.
    var statusItemFrame: () -> NSRect? = { nil }

    private var peekWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init() {
        claude.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var size: CGSize {
        geometry.isPhysical ? notchModeSize : menuBarModeSize
    }

    private var sessionRowsHeight: CGFloat {
        claude.sessions.isEmpty ? 0 : 10 + 28 * CGFloat(min(claude.sessions.count, 4))
    }

    /// Height of the question card's content: question lines, option rows and the button row.
    private var questionContentHeight: CGFloat? {
        guard let questions = claude.requests.first?.questions, !questions.isEmpty else { return nil }
        var height: CGFloat = 4 + 14 + 30 + 10
        for (index, question) in questions.enumerated() {
            height += (index > 0 ? 14 : 0) + 20 + 6
            let lines = CGFloat(max(1, question.question.count / 70 + 1))
            height += (lines - 1) * 16
            for option in question.options {
                height += (option.description?.isEmpty == false ? 46 : 30) + 6
            }
        }
        return min(height, 360)
    }

    private var notchModeSize: CGSize {
        let notch = geometry.notchSize
        switch state {
        case .hidden, .closed:
            return claude.hasActivity ? CGSize(width: notch.width + 96, height: notch.height) : notch
        case .peek:
            return CGSize(width: notch.width + 220, height: notch.height + 50)
        case .open:
            if let content = questionContentHeight {
                return CGSize(width: max(notch.width + 340, 560), height: notch.height + content + 12)
            }
            if !claude.requests.isEmpty {
                return CGSize(width: max(notch.width + 340, 560), height: notch.height + 156)
            }
            return CGSize(width: max(notch.width + 320, 540), height: notch.height + 130 + Self.topAppsHeight + sessionRowsHeight)
        }
    }

    private var menuBarModeSize: CGSize {
        switch state {
        case .hidden, .closed:
            return CGSize(width: 160, height: 0)
        case .peek:
            return CGSize(width: 360, height: 58)
        case .open:
            if let content = questionContentHeight {
                return CGSize(width: 520, height: content + 34)
            }
            if !claude.requests.isEmpty {
                return CGSize(width: 520, height: 178)
            }
            return CGSize(width: 520, height: 150 + Self.topAppsHeight + sessionRowsHeight)
        }
    }

    /// Island's leading edge in window coordinates (the window spans the full screen width).
    var islandX: CGFloat {
        let width = size.width
        let screen = geometry.screenFrame
        let ideal = geometry.anchorX - screen.minX - width / 2
        return min(max(ideal, Self.edgeInset), max(Self.edgeInset, screen.width - width - Self.edgeInset))
    }

    var radii: (top: CGFloat, bottom: CGFloat) {
        guard geometry.isPhysical else {
            switch state {
            case .peek: return (29, 29)
            case .open: return (26, 26)
            case .hidden, .closed: return (18, 18)
            }
        }
        switch state {
        case .hidden, .closed: return (6, 12)
        case .peek: return (10, 22)
        case .open: return (14, 30)
        }
    }

    /// Changes whenever the island needs to resize.
    var layoutKey: String {
        "\(claude.layoutKey)-\(geometry.anchorX)-\(geometry.top)"
    }

    var animation: Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .easeOut(duration: 0.2)
        }
        return .spring(response: 0.42, dampingFraction: 0.78)
    }

    func refreshGeometry() {
        let current = NotchGeometry.current(statusItemFrame: statusItemFrame())
        if current != geometry { geometry = current }
    }

    func open(pinned: Bool = true) {
        refreshGeometry()
        peekWork?.cancel()
        isPinned = pinned
        state = .open
    }

    func close() {
        isPinned = false
        state = restingState
    }

    func toggle() {
        state == .open ? close() : open()
    }

    func setHidden(_ hidden: Bool) {
        restingState = hidden ? .hidden : .closed
        if state != .open && state != .peek {
            state = restingState
        }
    }

    func show(_ toast: Toast, duration: TimeInterval = 3.5) {
        self.toast = toast
        guard state != .open else { return }

        refreshGeometry()
        state = .peek
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .peek else { return }
            self.state = self.restingState
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
