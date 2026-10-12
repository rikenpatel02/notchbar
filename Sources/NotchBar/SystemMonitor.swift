import Darwin
import Foundation

enum MemoryPressure {
    case normal, warning, critical
}

/// Live CPU, memory and network throughput, sampled once a second only while a view shows it.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    /// 0...1
    @Published private(set) var cpuUsage: Double?
    /// 0...1, matching Activity Monitor's "Memory Used" (app + wired + compressed).
    @Published private(set) var memoryUsage: Double?
    @Published private(set) var memoryUsedBytes: UInt64 = 0
    /// The kernel's own verdict on whether RAM is running short; drives the warning colors.
    @Published private(set) var memoryPressure = MemoryPressure.normal
    @Published private(set) var swapUsedBytes: UInt64 = 0
    @Published private(set) var downloadPerSecond: Double?
    @Published private(set) var uploadPerSecond: Double?

    private var previousTicks: (busy: UInt64, total: UInt64)?
    private var previousNetwork: [String: (input: UInt32, output: UInt32)] = [:]
    private var lastNetworkSample: Date?
    private var timer: Timer?
    private var viewers = 0

    func start() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
        previousTicks = nil
        previousNetwork = [:]
        lastNetworkSample = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        if let previous = previousTicks, total > previous.total {
            cpuUsage = Double(busy - previous.busy) / Double(total - previous.total)
        }
        previousTicks = (busy, total)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let page = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let total = ProcessInfo.processInfo.physicalMemory
        memoryUsedBytes = used
        memoryUsage = total > 0 ? min(1, Double(used) / Double(total)) : nil

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
            memoryPressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsedBytes = swap.xsu_used
        }
    }

    /// Swap counts as high once it passes a quarter of physical memory.
    var isSwapHigh: Bool {
        swapUsedBytes > ProcessInfo.processInfo.physicalMemory / 4
    }

    private func sampleNetwork() {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }

        var current: [String: (input: UInt32, output: UInt32)] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data else { continue }
            let flags = Int32(interface.ifa_flags)
            let name = String(cString: interface.ifa_name)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            current[name] = (counters.ifi_ibytes, counters.ifi_obytes)
        }

        let now = Date()
        if let lastNetworkSample {
            let elapsed = now.timeIntervalSince(lastNetworkSample)
            var down: UInt64 = 0
            var up: UInt64 = 0
            for (name, counters) in current {
                guard let old = previousNetwork[name] else { continue }
                // 32-bit counters wrap at 4 GB; wrapping subtraction keeps the delta correct.
                down += UInt64(counters.input &- old.input)
                up += UInt64(counters.output &- old.output)
            }
            if elapsed > 0 {
                downloadPerSecond = Double(down) / elapsed
                uploadPerSecond = Double(up) / elapsed
            }
        }
        previousNetwork = current
        lastNetworkSample = now
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1_073_741_824 { return String(format: "%.1f GB", value / 1_073_741_824) }
        return "\(Int(value / 1_048_576)) MB"
    }

    static func formatRate(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond else { return "--" }
        switch value {
        case ..<1_000: return "0 KB/s"
        case ..<1_000_000: return "\(Int(value / 1_000)) KB/s"
        default: return String(format: "%.1f MB/s", value / 1_000_000)
        }
    }
}
