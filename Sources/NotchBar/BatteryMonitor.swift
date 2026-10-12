import Foundation
import IOKit.ps

final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Int?
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isCharging = false

    /// Fires when the power adapter is connected or removed.
    var onPowerSourceChange: ((BatteryMonitor) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    init() {
        refresh(notify: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().refresh(notify: true)
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    var symbol: String {
        if isCharging { return "battery.100percent.bolt" }
        switch level ?? 0 {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func refresh(notify: Bool) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let wasPluggedIn = isPluggedIn

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            level = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : nil
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        }

        if notify && wasPluggedIn != isPluggedIn {
            onPowerSourceChange?(self)
        }
    }
}
