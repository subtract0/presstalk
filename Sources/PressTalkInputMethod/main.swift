import AppKit
import Foundation
import InputMethodKit

private enum PressTalkInputMethodConfig {
    static let bundleIdentifier = "com.am.presstalk.inputmethod"
    static let connectionName = "PressTalkInputMethod_1_Connection"
    static let insertNotification = "com.am.presstalk.inputmethod.insert"

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap", isDirectory: true)
    }

    static var pendingInsertURL: URL {
        supportDirectory.appendingPathComponent("input-method-insert.txt")
    }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/presstalk_input_method.log")
    }
}

private final class InputMethodLog {
    private let url = PressTalkInputMethodConfig.logURL
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            fputs("[PressTalkInputMethod] log write failed: \(error)\n", stderr)
        }
    }
}

private let inputMethodLog = InputMethodLog()

@objc(PressTalkIMController)
final class PressTalkIMController: IMKInputController {
    private static weak var activeController: PressTalkIMController?

    private var currentClient: IMKTextInput?

    override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        super.init(server: server, delegate: delegate, client: client)
        updateClient(client, context: "init")
        inputMethodLog.write("controller initialized")
    }

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        updateClient(sender, context: "inputText")
        return false
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        updateClient(sender, context: "handle")
        return false
    }

    override func didCommand(by aSelector: Selector!, client sender: Any!) -> Bool {
        updateClient(sender, context: "didCommand")
        return false
    }

    private func updateClient(_ sender: Any!, context: String) {
        guard let client = sender as? IMKTextInput else {
            inputMethodLog.write("client update skipped context=\(context) reason=not_imk_text_input")
            return
        }

        currentClient = client
        Self.activeController = self
        inputMethodLog.write("client updated context=\(context)")
    }

    private func insert(_ text: String) -> Bool {
        guard let currentClient else {
            inputMethodLog.write("insert failed reason=no_current_client")
            return false
        }

        currentClient.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        inputMethodLog.write("insert requested characters=\(text.count)")
        return true
    }

    static func insertIntoActiveClient(_ text: String) -> Bool {
        activeController?.insert(text) ?? false
    }
}

@main
final class PressTalkInputMethodApp: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        inputMethodLog.write("app launched")
        server = IMKServer(
            name: PressTalkInputMethodConfig.connectionName,
            bundleIdentifier: PressTalkInputMethodConfig.bundleIdentifier
        )
        installInsertNotificationObserver()
    }

    func applicationWillTerminate(_ notification: Notification) {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
        inputMethodLog.write("app terminating")
    }

    private func installInsertNotificationObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let app = Unmanaged<PressTalkInputMethodApp>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                app.handleInsertNotification()
            },
            PressTalkInputMethodConfig.insertNotification as CFString,
            nil,
            .deliverImmediately
        )
        inputMethodLog.write("insert notification observer installed name=\(PressTalkInputMethodConfig.insertNotification)")
    }

    private func handleInsertNotification() {
        do {
            let text = try String(
                contentsOf: PressTalkInputMethodConfig.pendingInsertURL,
                encoding: .utf8
            ).trimmingCharacters(in: .newlines)
            guard !text.isEmpty else {
                inputMethodLog.write("insert notification ignored reason=empty_payload")
                return
            }

            let inserted = PressTalkIMController.insertIntoActiveClient(text)
            inputMethodLog.write("insert notification handled inserted=\(inserted ? 1 : 0)")
        } catch {
            inputMethodLog.write("insert notification failed reason=read_payload error=\(error)")
        }
    }
}
