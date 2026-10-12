import Foundation
import SwiftUI

struct ClaudeSession: Identifiable, Equatable {
    enum Status { case working, waiting, done, idle }

    let id: String
    var project: String
    var status: Status
    var detail: String
    var updatedAt: Date
    /// When the current working stretch began; nil when not working or unknown.
    var workingSince: Date?
    var tty: String?
    /// TERM_PROGRAM of the session's terminal, such as "Apple_Terminal".
    var term: String?
    /// Started with --dangerously-skip-permissions, so it never asks for approval.
    var bypassPermissions = false
}

struct PermissionRequest: Identifiable, Equatable {
    let id: String
    let sessionId: String
    let project: String
    let tool: String
    let detail: String
    let expiresAt: Date
}

/// Live state of every Claude Code session reporting through the hook.
final class ClaudeStore: ObservableObject {
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

    private static let staleWorking: TimeInterval = 10 * 60
    private static let forgetAfter: TimeInterval = 30 * 60

    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var requests: [PermissionRequest] = []

    private static let statusDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/status", isDirectory: true)

    private var pruneTimer: Timer?
    /// Sessions backed by a status file whose terminal still runs `claude`.
    private var liveSessionIds = Set<String>()

    init() {
        syncFromStatusFiles()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.syncFromStatusFiles()
            self?.prune()
        }
    }

    var hasActivity: Bool {
        !requests.isEmpty || sessions.contains { $0.status == .working || $0.status == .waiting }
    }

    var workingCount: Int {
        sessions.filter { $0.status == .working }.count
    }

    /// Changes whenever the notch needs to resize.
    var layoutKey: String {
        "\(hasActivity)-\(requests.first?.id ?? "")-\(min(sessions.count, 4))"
    }

    func update(
        session id: String,
        project: String,
        status: ClaudeSession.Status,
        detail: String,
        tty: String? = nil,
        term: String? = nil,
        bypassPermissions: Bool? = nil
    ) {
        let existing = sessions.first { $0.id == id }
        var session = existing
            ?? ClaudeSession(id: id, project: project, status: status, detail: detail, updatedAt: Date())
        if status != .working {
            session.workingSince = nil
        } else if existing?.status != .working || session.workingSince == nil {
            session.workingSince = Date()
        }
        session.project = project
        session.status = status
        session.detail = detail
        session.updatedAt = Date()
        session.tty = tty ?? session.tty
        session.term = term ?? session.term
        session.bypassPermissions = bypassPermissions ?? session.bypassPermissions
        sessions.removeAll { $0.id == id }
        sessions.insert(session, at: 0)
    }

    func end(session id: String) {
        sessions.removeAll { $0.id == id }
        requests.removeAll { $0.sessionId == id }
    }

    func add(_ request: PermissionRequest) {
        requests.append(request)
        update(session: request.sessionId, project: request.project, status: .waiting, detail: "Approve \(request.tool)?")
    }

    func removeRequest(id: String) {
        guard let request = requests.first(where: { $0.id == id }) else { return }
        requests.removeAll { $0.id == id }
        if let index = sessions.firstIndex(where: { $0.id == request.sessionId }), sessions[index].status == .waiting {
            sessions[index].status = .working
            sessions[index].detail = request.tool
            sessions[index].workingSince = Date()
        }
    }

    /// Sends the decision back to the waiting hook process.
    func resolve(_ request: PermissionRequest, allow: Bool) {
        ClaudeReply(id: request.id, behavior: allow ? "allow" : "deny").post()
        removeRequest(id: request.id)
    }

    private func prune() {
        let now = Date()
        requests.removeAll { $0.expiresAt < now }
        sessions.removeAll { !liveSessionIds.contains($0.id) && now.timeIntervalSince($0.updatedAt) > Self.forgetAfter }
        for index in sessions.indices
        where sessions[index].status == .working && now.timeIntervalSince(sessions[index].updatedAt) > Self.staleWorking {
            sessions[index].status = .idle
            sessions[index].detail = "Idle"
            sessions[index].workingSince = nil
        }
    }

    /// Restores sessions that started before NotchBar launched, from the files written by
    /// `~/.claude/status/cc-status.py`. Hook events stay the live source; a file only wins
    /// when it is newer. Files whose terminal no longer runs `claude` are ignored.
    private func syncFromStatusFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.statusDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let liveTTYs = Self.terminalsRunningClaude()
        var live = Set<String>()

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = json["session_id"] as? String else { continue }

            let updatedAt = (json["updated_at"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
            let tty = json["tty"] as? String
            if let tty {
                guard liveTTYs[tty] != nil else { continue }
            } else if Date().timeIntervalSince(updatedAt) > Self.forgetAfter {
                continue
            }
            live.insert(id)

            let term = json["term"] as? String
            let bypass = tty.flatMap { liveTTYs[$0] } ?? false
            if let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].updatedAt >= updatedAt {
                sessions[index].tty = sessions[index].tty ?? tty
                sessions[index].term = sessions[index].term ?? term
                sessions[index].bypassPermissions = sessions[index].bypassPermissions || bypass
                continue
            }

            let status: ClaudeSession.Status
            switch json["status"] as? String {
            case "working": status = .working
            case "needs-attention": status = .waiting
            default: status = .done
            }
            let message = json["message"] as? String ?? ""
            let previous = sessions.first { $0.id == id }
            let session = ClaudeSession(
                id: id,
                project: json["project"] as? String ?? "Claude",
                status: status,
                detail: message.isEmpty ? (status == .done ? "Finished" : "Working") : message,
                updatedAt: updatedAt,
                workingSince: status == .working ? previous?.workingSince : nil,
                tty: tty,
                term: term,
                bypassPermissions: bypass || previous?.bypassPermissions == true
            )
            sessions.removeAll { $0.id == id }
            sessions.append(session)
        }

        liveSessionIds = live
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    /// tty of every terminal running `claude`, mapped to whether it skips permission prompts.
    private static func terminalsRunningClaude() -> [String: Bool] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "tty=,args="]
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [:] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        var ttys: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[0] != "??",
                  URL(fileURLWithPath: String(parts[1])).lastPathComponent == "claude"
            else { continue }
            let tty = "/dev/\(parts[0])"
            ttys[tty] = (ttys[tty] ?? false) || parts.contains("--dangerously-skip-permissions")
        }
        return ttys
    }
}

/// Decision sent from the app to the blocked `NotchBar hook` process.
struct ClaudeReply: Codable {
    static let notificationName = Notification.Name("com.rikenpatel.notchbar.reply")

    var id: String
    var behavior: String

    func post() {
        guard let data = try? JSONEncoder().encode(self), let json = String(data: data, encoding: .utf8) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.notificationName,
            object: json,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func decode(_ notification: Notification) -> ClaudeReply? {
        guard let json = notification.object as? String, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ClaudeReply.self, from: data)
    }
}
