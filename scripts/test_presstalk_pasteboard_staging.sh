#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/Sources/JarvisTap/PasteboardInsertionStaging.swift"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-pasteboard-staging-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cat >"$TEST_TMPDIR/PasteboardStagingTest.swift" <<'SWIFT'
import AppKit
import Foundation

@main
enum PasteboardStagingTest {
    static let customType = NSPasteboard.PasteboardType("com.am.presstalk.test.custom")

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            Foundation.exit(1)
        }
    }

    static func makePasteboard(_ name: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.am.presstalk.test.\(name).\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    static func seedRichItem(on pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setString("original text", forType: .string)
        item.setData(Data([0x70, 0x74, 0x21]), forType: customType)
        require(pasteboard.writeObjects([item]), "seed pasteboard write failed")
    }

    static func main() {
        let restoredPasteboard = makePasteboard("restore")
        seedRichItem(on: restoredPasteboard)

        let staging = PasteboardInsertionStaging.stage("dictated text", on: restoredPasteboard)
        require(restoredPasteboard.string(forType: .string) == "dictated text", "stage should place dictated text on pasteboard")
        staging.restoreIfUnchanged(on: restoredPasteboard)
        require(restoredPasteboard.string(forType: .string) == "original text", "restore should recover original string")
        require(
            restoredPasteboard.pasteboardItems?.first?.data(forType: customType) == Data([0x70, 0x74, 0x21]),
            "restore should preserve non-string pasteboard data"
        )

        let externallyChangedPasteboard = makePasteboard("external-change")
        seedRichItem(on: externallyChangedPasteboard)
        let externalChangeStaging = PasteboardInsertionStaging.stage("dictated text", on: externallyChangedPasteboard)
        externallyChangedPasteboard.clearContents()
        externallyChangedPasteboard.setString("user copied something else", forType: .string)
        externalChangeStaging.restoreIfUnchanged(on: externallyChangedPasteboard)
        require(
            externallyChangedPasteboard.string(forType: .string) == "user copied something else",
            "restore must not overwrite a later pasteboard change"
        )

        let emptyPasteboard = makePasteboard("empty")
        let emptyStaging = PasteboardInsertionStaging.stage("dictated text", on: emptyPasteboard)
        require(emptyPasteboard.string(forType: .string) == "dictated text", "empty stage should place dictated text")
        emptyStaging.restoreIfUnchanged(on: emptyPasteboard)
        require(
            (emptyPasteboard.pasteboardItems ?? []).isEmpty,
            "restore should recover an empty pasteboard"
        )

        print("PASS pasteboard_staging")
    }
}
SWIFT

swiftc "$SOURCE" "$TEST_TMPDIR/PasteboardStagingTest.swift" -o "$TEST_TMPDIR/PasteboardStagingTest"
"$TEST_TMPDIR/PasteboardStagingTest"
