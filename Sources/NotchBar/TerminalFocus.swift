import AppKit
import Darwin

/// Finds and focuses the terminal tab a Claude Code session runs in.
/// Apple Terminal and iTerm2 are matched by tty; other terminals are just activated.
enum TerminalFocus {
    private static let queue = DispatchQueue(label: "com.rikenpatel.notchbar.terminal", qos: .userInitiated)

    private static let genericApps = [
        "vscode": "Visual Studio Code",
        "warpterminal": "Warp",
        "wezterm": "WezTerm",
        "ghostty": "Ghostty",
        "hyper": "Hyper",
        "kitty": "kitty",
        "tabby": "Tabby",
        "alacritty": "Alacritty",
    ]

    /// Controlling terminal of the nearest ancestor that has one, such as "/dev/ttys004".
    /// Hooks run without a tty of their own, but the `claude` process above them has one.
    static func controllingTTY() -> String? {
        var pid = getpid()
        for _ in 0..<12 {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
            let device = info.kp_eproc.e_tdev
            if device != -1, let name = devname(device, S_IFCHR) {
                let tty = String(cString: name)
                if tty != "??" { return "/dev/\(tty)" }
            }
            pid = info.kp_eproc.e_ppid
            if pid <= 1 { return nil }
        }
        return nil
    }

    /// `onDenied` runs on the main queue when macOS blocks NotchBar from controlling the terminal.
    static func focus(tty: String?, term: String?, onDenied: @escaping () -> Void) {
        let tty = tty.flatMap(sanitized)
        queue.async {
            let source: String
            switch term?.lowercased() {
            case "apple_terminal", nil:
                source = tty.map(terminalFocusScript) ?? #"tell application "Terminal" to activate"#
            case "iterm.app", "iterm2", "iterm":
                source = tty.map(iTermFocusScript) ?? #"tell application "iTerm" to activate"#
            case let other?:
                let name = genericApps[other] ?? (other.hasSuffix(".app") ? String(other.dropLast(4)) : other)
                source = #"tell application "\#(name.replacingOccurrences(of: "\"", with: ""))" to activate"#
            }
            if run(source).denied {
                DispatchQueue.main.async(execute: onDenied)
            }
        }
    }

    enum AutomationStatus {
        case allowed, denied, notAsked, notRunning
    }

    /// Checks without prompting; macOS can only answer while the terminal is running.
    static func automationStatus(bundleIdentifier: String = "com.apple.Terminal") -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .notAsked
        }
    }

    /// Shows macOS's "control Terminal" prompt now, instead of on the first session click.
    static func requestAutomation(completion: @escaping (AutomationStatus) -> Void) {
        queue.async {
            _ = run(#"tell application "Terminal" to count windows"#)
            let status = automationStatus()
            DispatchQueue.main.async { completion(status) }
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Calls back on the main queue with whether this tty's tab is the one in front.
    static func isFrontmost(tty: String?, term: String?, completion: @escaping (Bool) -> Void) {
        guard let tty = tty.flatMap(sanitized),
              let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            completion(false)
            return
        }

        let script: String
        switch (front, term?.lowercased()) {
        case ("com.apple.Terminal", "apple_terminal"?), ("com.apple.Terminal", nil):
            script = #"tell application "Terminal" to get tty of selected tab of front window"#
        case ("com.googlecode.iterm2", _):
            script = #"tell application "iTerm" to get tty of current session of current window"#
        default:
            completion(false)
            return
        }

        queue.async {
            let frontTTY = run(script).value
            DispatchQueue.main.async { completion(frontTTY == tty) }
        }
    }

    private static func sanitized(_ tty: String) -> String? {
        let name = tty.dropFirst("/dev/".count)
        guard tty.hasPrefix("/dev/"), !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return tty
    }

    private static func terminalFocusScript(_ tty: String) -> String {
        """
        tell application "Terminal"
          activate
          repeat with w in windows
            try
              repeat with t in tabs of w
                if (tty of t) is "\(tty)" then
                  set selected of t to true
                  set index of w to 1
                  return
                end if
              end repeat
            end try
          end repeat
        end tell
        """
    }

    private static func iTermFocusScript(_ tty: String) -> String {
        """
        tell application "iTerm"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                try
                  if (tty of s) is "\(tty)" then
                    select w
                    tell t to select
                    tell s to select
                    return
                  end if
                end try
              end repeat
            end repeat
          end repeat
        end tell
        """
    }

    /// errAEEventNotPermitted: the user said no to (or never answered) the Automation prompt.
    private static let notPermitted = -1743

    private static func run(_ source: String) -> (value: String?, denied: Bool) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        let code = error?[NSAppleScript.errorNumber] as? Int
        return (result?.stringValue, code == notPermitted)
    }
}
