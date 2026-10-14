import Foundation
import SwiftUI

/// Commands sent from the CLI (or any script / Claude Code hook) to the running app
/// via a distributed notification, so no sockets or permissions are required.
struct NotchCommand: Codable {
    static let notificationName = Notification.Name("com.rikenpatel.notchbar.command")

    var action: String
    var title: String? = nil
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: String? = nil
    var session: String? = nil
    var project: String? = nil
    var detail: String? = nil
    var requestId: String? = nil
    var tool: String? = nil
    var timeout: Double? = nil
    var tty: String? = nil
    var term: String? = nil
    var bypassPermissions: Bool? = nil
    var questions: [ClaudeQuestion]? = nil

    var toast: Toast {
        Toast(
            title: title ?? "",
            subtitle: subtitle ?? "",
            symbol: symbol ?? "bell.fill",
            tint: Self.color(named: tint)
        )
    }

    static func color(named name: String?) -> Color {
        switch name?.lowercased() {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        default: return .blue
        }
    }

    func post() {
        guard let data = try? JSONEncoder().encode(self), let json = String(data: data, encoding: .utf8) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.notificationName,
            object: json,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func decode(_ notification: Notification) -> NotchCommand? {
        guard let json = notification.object as? String, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NotchCommand.self, from: data)
    }
}

enum NotchCLI {
    static let usage = """
    Usage: NotchBar <command>

      toast <title> [subtitle] [sf-symbol] [tint]   Pop a live-activity banner
      open | close | toggle                         Expand or collapse the notch
      hide | show                                   Hide or show the resting notch
      setup                                         Open the setup window
      hook                                          Claude Code hook (reads event JSON on stdin)

    Tints: blue, green, orange, red, purple, yellow, pink, teal
    Example: NotchBar toast "Build passed" "notchbar - 12s" checkmark.circle.fill green
    """

    static func run(_ arguments: [String]) -> Int32 {
        guard let action = arguments.first else {
            print(usage)
            return 1
        }

        switch action {
        case "toast":
            guard arguments.count >= 2 else {
                print(usage)
                return 1
            }
            NotchCommand(
                action: action,
                title: arguments[1],
                subtitle: arguments.count > 2 ? arguments[2] : nil,
                symbol: arguments.count > 3 ? arguments[3] : nil,
                tint: arguments.count > 4 ? arguments[4] : nil
            ).post()
        case "open", "close", "toggle", "hide", "show", "setup":
            NotchCommand(action: action).post()
        case "hook":
            return ClaudeHook.run()
        case "help", "-h", "--help":
            print(usage)
            return 0
        default:
            print(usage)
            return 1
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        return 0
    }
}
