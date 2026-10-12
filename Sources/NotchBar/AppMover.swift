import AppKit

/// Offers to move a freshly downloaded copy into /Applications. Run from a disk image,
/// Downloads or macOS's randomized "translocation" path, the app gets a location that
/// changes or disappears, which breaks the Claude Code hook path and Launch at Login.
enum AppMover {
    private static let destination = URL(fileURLWithPath: "/Applications/NotchBar.app")

    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    /// Only prompts for download-style locations, never for a developer build.
    static var shouldOfferMove: Bool {
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return isTranslocated
            || path.hasPrefix("/Volumes/")
            || path.hasPrefix("\(home)/Downloads/")
            || path.hasPrefix("\(home)/Desktop/")
    }

    /// Returns true when the app is relaunching from /Applications and this copy should quit.
    static func offerMoveIfNeeded() -> Bool {
        guard shouldOfferMove else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move NotchBar to Applications?"
        alert.informativeText = "NotchBar needs to live in Applications so Claude Code can reach it and it can open at login."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.trashItem(at: destination, resultingItemURL: nil)
            }
            try fileManager.copyItem(at: Bundle.main.bundleURL, to: destination)
            // The user already approved this download; don't make Gatekeeper ask twice.
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
            try? xattr.run()
            xattr.waitUntilExit()
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't move NotchBar"
            failure.informativeText = "\(error.localizedDescription)\n\nDrag NotchBar into your Applications folder in Finder, then open it from there."
            failure.runModal()
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }
}
