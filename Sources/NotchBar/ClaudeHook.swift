import AppKit

/// `NotchBar hook`: Claude Code command hook. Reads the hook event JSON from stdin and
/// forwards it to the running app. For PermissionRequest it blocks until Approve/Deny is
/// clicked in the notch; on timeout it prints nothing so Claude falls back to its own prompt.
enum ClaudeHook {
    private static let bundleIdentifier = "com.rikenpatel.notchbar"

    private static var permissionTimeout: TimeInterval {
        ProcessInfo.processInfo.environment["NOTCHBAR_PERMISSION_TIMEOUT"].flatMap(TimeInterval.init) ?? 120
    }

    static func run() -> Int32 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard isAppRunning,
              let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = input["hook_event_name"] as? String else { return 0 }

        let session = input["session_id"] as? String ?? "unknown"
        let project = (input["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude"
        let tool = displayName(forTool: input["tool_name"] as? String ?? "")
        let summary = describe(input)
        let tty = TerminalFocus.controllingTTY()
        let term = ProcessInfo.processInfo.environment["TERM_PROGRAM"]
        let bypass = (input["permission_mode"] as? String).map { $0 == "bypassPermissions" }

        func send(_ action: String, detail: String? = nil) {
            NotchCommand(
                action: action,
                session: session,
                project: project,
                detail: detail,
                tty: tty,
                term: term,
                bypassPermissions: bypass
            ).post()
        }

        switch event {
        case "UserPromptSubmit":
            send("claude.working", detail: "Thinking")
        case "PreToolUse":
            send("claude.working", detail: summary.isEmpty ? tool : "\(tool)  \(summary)")
        case "Notification":
            send("claude.waiting", detail: input["message"] as? String)
        case "Stop":
            send("claude.done")
        case "SessionEnd":
            send("claude.end")
        case "PermissionRequest":
            return requestPermission(session: session, project: project, tool: tool, summary: summary)
        default:
            return 0
        }

        flush()
        return 0
    }

    private static var isAppRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != getpid() }
    }

    private static func requestPermission(session: String, project: String, tool: String, summary: String) -> Int32 {
        let id = UUID().uuidString
        let timeout = permissionTimeout
        var behavior: String?

        let observer = DistributedNotificationCenter.default().addObserver(
            forName: ClaudeReply.notificationName,
            object: nil,
            queue: nil
        ) { notification in
            guard let reply = ClaudeReply.decode(notification), reply.id == id else { return }
            behavior = reply.behavior
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        NotchCommand(
            action: "claude.permission",
            session: session,
            project: project,
            detail: summary,
            requestId: id,
            tool: tool,
            timeout: timeout
        ).post()

        let deadline = Date().addingTimeInterval(timeout)
        while behavior == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        }

        guard let behavior else {
            NotchCommand(action: "claude.cancel", requestId: id).post()
            flush()
            return 0
        }

        let decision: [String: Any] = behavior == "allow"
            ? ["behavior": "allow"]
            : ["behavior": "deny", "message": "Denied from NotchBar"]
        let output: [String: Any] = [
            "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]
        ]
        if let json = try? JSONSerialization.data(withJSONObject: output),
           let text = String(data: json, encoding: .utf8) {
            print(text)
        }
        return 0
    }

    private static func flush() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private static func displayName(forTool tool: String) -> String {
        let parts = tool.components(separatedBy: "__")
        if parts.count >= 3, parts[0] == "mcp" {
            return "\(parts[1]): \(parts[2...].joined(separator: "__"))"
        }
        return tool
    }

    private static func describe(_ input: [String: Any]) -> String {
        guard let toolInput = input["tool_input"] as? [String: Any] else { return "" }
        let keys = ["command", "file_path", "notebook_path", "url", "pattern", "query", "description", "prompt"]
        guard let value = keys.lazy.compactMap({ toolInput[$0] as? String }).first else { return "" }
        let text = value.hasPrefix("/") && !value.contains(" ") ? URL(fileURLWithPath: value).lastPathComponent : value
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 300 ? String(singleLine.prefix(300)) + "..." : singleLine
    }
}
