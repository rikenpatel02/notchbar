// Gives a file a custom Finder icon and hides its extension:
//   swift scripts/set-icon.swift <icon.png> <file>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let image = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write("usage: set-icon.swift <icon.png> <file>\n".data(using: .utf8)!)
    exit(1)
}
var url = URL(fileURLWithPath: arguments[2])
var values = URLResourceValues()
values.hasHiddenExtension = true
try? url.setResourceValues(values)
exit(NSWorkspace.shared.setIcon(image, forFile: arguments[2], options: []) ? 0 : 1)
