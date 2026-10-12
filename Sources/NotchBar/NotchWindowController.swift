import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchWindowController {
    private static let panelHeight: CGFloat = 340
    private static let hoverSlop: CGFloat = 6
    private static let closeDelay: TimeInterval = 0.3

    private let model: NotchViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var closeWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(model: NotchViewModel, battery: BatteryMonitor) {
        self.model = model
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: Self.panelHeight))
        panel.contentView = FirstMouseHostingView(rootView: NotchRootView(model: model, battery: battery))

        startMouseTracking()

        model.$geometry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] geometry in self?.reposition(for: geometry) }
            .store(in: &cancellables)

        model.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMouse() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.model.refreshGeometry() }
            .store(in: &cancellables)

        panel.orderFrontRegardless()
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    private func reposition(for geometry: NotchGeometry) {
        let screen = geometry.screenFrame
        panel.setFrame(
            NSRect(x: screen.minX, y: geometry.top - Self.panelHeight, width: screen.width, height: Self.panelHeight),
            display: true
        )
    }

    private func startMouseTracking() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in
            self?.updateMouse()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
            self?.updateMouse()
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, self.model.state == .open, !self.isMouseInside() else { return }
            self.model.close()
        } as Any)
    }

    /// The interactive region: the visible island. A hidden hardware notch keeps its footprint
    /// so hovering reveals it; in menu bar mode a collapsed island has no footprint at all.
    private func activeRect() -> NSRect {
        let geometry = model.geometry
        var size = model.size
        if geometry.isPhysical && model.state == .hidden {
            size = geometry.notchSize
        }
        return NSRect(
            x: geometry.screenFrame.minX + model.islandX,
            y: geometry.top - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func isMouseInside() -> Bool {
        let rect = activeRect()
        guard rect.height > 0 else { return false }
        return rect.insetBy(dx: -Self.hoverSlop, dy: -Self.hoverSlop).contains(NSEvent.mouseLocation)
    }

    private func updateMouse() {
        let inside = isMouseInside()
        panel.ignoresMouseEvents = !inside

        switch model.state {
        case .open:
            if inside {
                closeWork?.cancel()
                closeWork = nil
            } else if closeWork == nil, !model.isPinned {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.closeWork = nil
                    if !self.isMouseInside() { self.model.close() }
                }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDelay, execute: work)
            }
        case .closed, .hidden, .peek:
            if inside && model.expandOnHover {
                model.open(pinned: false)
            }
        }
    }
}
