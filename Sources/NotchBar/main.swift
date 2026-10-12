import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    exit(NotchCLI.run(arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
