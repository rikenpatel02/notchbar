import AppKit
import Darwin

/// One app (with its helper processes folded in) or one standalone process.
struct AppUsage: Identifiable, Equatable {
    /// The .app bundle path, or the process name for command-line tools.
    let id: String
    let name: String
    let appPath: String?
    let pids: [pid_t]
    /// Physical footprint, the same figure Activity Monitor's Memory column shows.
    let memoryBytes: UInt64
    /// Share of one core, so a busy multi-threaded app can pass 100%.
    let cpu: Double
}

/// Biggest memory and CPU users among the current user's processes, sampled every two
/// seconds only while the expanded panel shows them.
final class ProcessMonitor: ObservableObject {
    static let shared = ProcessMonitor()

    @Published private(set) var apps: [AppUsage] = []

    private var timer: Timer?
    private var viewers = 0
    private var previousCPU: [pid_t: UInt64] = [:]
    private var lastSample: UInt64 = 0
    private var names: [pid_t: (key: String, name: String, appPath: String?)] = [:]
    private let queue = DispatchQueue(label: "com.rikenpatel.notchbar.processes", qos: .utility)
    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    func start() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func top(by memory: Bool, count: Int = 3) -> [AppUsage] {
        let sorted = memory
            ? apps.sorted { $0.memoryBytes > $1.memoryBytes }
            : apps.sorted { $0.cpu > $1.cpu }
        return Array(sorted.prefix(count))
    }

    /// Quits an app politely through AppKit, or sends SIGTERM to a standalone process.
    func quit(_ usage: AppUsage) {
        if let path = usage.appPath {
            let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path }
            if !running.isEmpty {
                running.forEach { $0.terminate() }
                return
            }
        }
        usage.pids.forEach { kill($0, SIGTERM) }
    }

    private func sample() {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.collect()
            DispatchQueue.main.async { self.apps = result }
        }
    }

    /// Runs on `queue`.
    private func collect() -> [AppUsage] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        guard count > 0 else { return [] }

        let now = mach_absolute_time()
        let elapsed = lastSample > 0 ? Double(now - lastSample) * timebase : 0
        let me = getpid()
        var groups: [String: (name: String, appPath: String?, pids: [pid_t], memory: UInt64, cpu: Double)] = [:]
        var currentCPU: [pid_t: UInt64] = [:]

        for pid in pids.prefix(count) where pid > 0 && pid != me {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0, let identity = identity(of: pid) else { continue }

            let cpuTime = info.ri_user_time + info.ri_system_time
            currentCPU[pid] = cpuTime
            var cpu = 0.0
            if elapsed > 0, let previous = previousCPU[pid], cpuTime >= previous {
                cpu = Double(cpuTime - previous) * timebase / elapsed
            }

            var group = groups[identity.key] ?? (identity.name, identity.appPath, [], 0, 0)
            group.pids.append(pid)
            group.memory += info.ri_phys_footprint
            group.cpu += cpu
            groups[identity.key] = group
        }

        previousCPU = currentCPU
        lastSample = now
        names = names.filter { currentCPU[$0.key] != nil }

        return groups.map { key, group in
            AppUsage(id: key, name: group.name, appPath: group.appPath, pids: group.pids, memoryBytes: group.memory, cpu: group.cpu)
        }
    }

    /// Helpers nested inside an app bundle belong to the outermost .app; anything else is
    /// named after its argv[0], which keeps titles such as "ng serve (my-app)".
    private func identity(of pid: pid_t) -> (key: String, name: String, appPath: String?)? {
        if let cached = names[pid] { return cached }

        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)

        let identity: (key: String, name: String, appPath: String?)
        if let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound]) + ".app"
            let name = FileManager.default.displayName(atPath: appPath).replacingOccurrences(of: ".app", with: "")
            identity = (appPath, name, appPath)
        } else {
            let name = argumentZero(of: pid) ?? URL(fileURLWithPath: path).lastPathComponent
            identity = (name, name, nil)
        }
        names[pid] = identity
        return identity
    }

    private func argumentZero(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Layout: argc, executable path, NUL padding, then argv[0].
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }
        let start = index
        while index < size && buffer[index] != 0 { index += 1 }
        guard index > start, let arg = String(bytes: buffer[start..<index], encoding: .utf8) else { return nil }
        return arg.hasPrefix("/") ? URL(fileURLWithPath: arg).lastPathComponent : arg
    }
}
