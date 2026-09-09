import AppKit
import Foundation

let app = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func fail(_ reason: String) -> Never { fputs("FAIL: app icon \(reason)\n", stderr); exit(1) }
guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let name = info["CFBundleIconFile"] as? String, name == "PressTalk.icns"
else { fail("is not registered in Info.plist") }
let url = app.appendingPathComponent("Contents/Resources").appendingPathComponent(name)
guard let image = NSImage(contentsOf: url),
      image.representations.contains(where: { $0.pixelsWide >= 512 && $0.pixelsHigh >= 512 }),
      image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil
else { fail("is missing or cannot be decoded at full resolution") }
print("PASS: registered app icon decodes at full resolution")
