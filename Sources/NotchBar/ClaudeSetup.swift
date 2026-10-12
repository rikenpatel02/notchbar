import Foundation

/// Adds or removes NotchBar's command hooks in ~/.claude/settings.json, leaving every
/// other setting and hook untouched. The first change saves a backup next to the file.
enum ClaudeSetup {
    enum SetupError: LocalizedError {
        case unreadableSettings

        var errorDescription: String? {
            "~/.claude/settings.json isn't valid JSON, so NotchBar left it alone. Fix the file, then try again."
        }
    }

    private static let events: [(name: String, timeout: Int)] = [
        ("UserPromptSubmit", 5),
        ("PreToolUse", 5),
        ("Notification", 5),
        ("Stop", 5),
        ("SessionEnd", 5),
        // Longer than the default 120s Approve/Deny wait in ClaudeHook.
        ("PermissionRequest", 130),
    ]

    private static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    private static var settingsURL: URL {
        claudeDirectory.appendingPathComponent("settings.json")
    }

    static var isClaudeInstalled: Bool {
        FileManager.default.fileExists(atPath: claudeDirectory.path)
    }

    private static var hookCommand: String {
        "\"\(Bundle.main.executablePath ?? "/Applications/NotchBar.app/Contents/MacOS/NotchBar")\" hook"
    }

    /// Matches hooks written by any NotchBar install, quoted or not, wherever it lived.
    private static func isNotchBarHook(_ hook: Any) -> Bool {
        guard let command = (hook as? [String: Any])?["command"] as? String else { return false }
        let unquoted = command.replacingOccurrences(of: "\"", with: "")
        return unquoted.hasSuffix("/NotchBar.app/Contents/MacOS/NotchBar hook")
    }

    /// Connected when every event runs this copy of NotchBar.
    static var isConnected: Bool {
        guard let settings = try? readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            let groups = hooks[event.name] as? [[String: Any]] ?? []
            return groups.contains { group in
                (group["hooks"] as? [Any] ?? []).contains {
                    let command = ($0 as? [String: Any])?["command"] as? String
                    return command?.replacingOccurrences(of: "\"", with: "") == hookCommand.replacingOccurrences(of: "\"", with: "")
                }
            }
        }
    }

    static func connect() throws {
        var settings = try readSettings()
        var hooks = removingNotchBarHooks(from: settings["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var groups = hooks[event.name] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": hookCommand, "timeout": event.timeout]]])
            hooks[event.name] = groups
        }
        settings["hooks"] = hooks
        try write(settings)
    }

    static func disconnect() throws {
        var settings = try readSettings()
        guard let existing = settings["hooks"] as? [String: Any] else { return }
        let hooks = removingNotchBarHooks(from: existing)
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try write(settings)
    }

    private static func removingNotchBarHooks(from hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = groups.compactMap { group in
                guard let entries = group["hooks"] as? [Any] else { return group }
                let kept = entries.filter { !isNotchBarHook($0) }
                if kept.isEmpty { return nil }
                var copy = group
                copy["hooks"] = kept
                return copy
            }
            result[event] = cleaned.isEmpty ? nil : cleaned
        }
        return result
    }

    private static func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        guard let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SetupError.unreadableSettings
        }
        return settings
    }

    private static func write(_ settings: [String: Any]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let backup = settingsURL.appendingPathExtension("notchbar-backup")
        if fileManager.fileExists(atPath: settingsURL.path), !fileManager.fileExists(atPath: backup.path) {
            try fileManager.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
