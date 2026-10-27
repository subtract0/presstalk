import AppKit
import Sparkle
import PressTalkCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}

@main struct UpdaterDelegateFixture {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let runtime = PressTalkUpdater()
        require(!runtime.isAvailable, "An unsigned command-line fixture became eligible for production updates")
        runtime.start()
        require(!runtime.canCheckForUpdates, "Ineligible bundle started Sparkle")
        require(!runtime.automaticallyChecksForUpdates && !runtime.automaticallyDownloadsUpdates,
                "Development tool enabled production update preferences")

        // The real framework object is never started. The dictionary initializer
        // is used only to manufacture a callback argument in this test process.
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let updater = controller.updater
        let item = SUAppcastItem(dictionary: [
            "title": "Test update", "enclosure": [
                "url": "https://example.invalid/PressTalk.zip", "sparkle:version": "999",
                "length": "1", "type": "application/octet-stream",
            ],
        ])!
        var busy = true, reserved = false
        var reservations = 0, releases = 0, installations = 0, immediateInstalls = 0
        runtime.isApplicationBusy = { busy }
        runtime.tryReserveInstallation = {
            guard !busy && !reserved else { return false }
            reserved = true; reservations += 1
            return true
        }
        runtime.releaseInstallationReservation = { reserved = false; releases += 1 }
        require(!runtime.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: true),
                "Scheduled update alert may steal focus during dictation")
        let postponed = runtime.updater(updater, shouldPostponeRelaunchForUpdate: item) {
            require(reserved, "Install callback ran before the app reserved termination")
            installations += 1
        }
        require(postponed && installations == 0, "Relaunch was not postponed before returning to Sparkle")
        runtime.activityDidChange()
        require(installations == 0 && reservations == 0, "Update interrupted busy dictation")
        busy = false
        require(runtime.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: false),
                "Standard reminder handling was replaced while idle")
        runtime.activityDidChange()
        runtime.activityDidChange()
        require(installations == 1 && reservations == 1 && reserved,
                "Idle continuation did not install exactly once under reservation")
        runtime.updater(updater, didFinishUpdateCycleFor: .updates, error: nil)
        require(!reserved && releases == 1,
                "Completed Sparkle cycle retained an installation reservation")
        runtime.activityDidChange()
        require(installations == 1, "Completed Sparkle cycle invoked its stale continuation")
        runtime.installationWasCancelled()
        runtime.installationWasCancelled()
        require(!reserved && releases == 1, "Cancelled termination left capture blocked or released twice")

        busy = true
        _ = runtime.updater(updater, shouldPostponeRelaunchForUpdate: item) { installations += 1 }
        runtime.updater(updater, didFinishUpdateCycleFor: .updates, error: nil)
        busy = false
        runtime.activityDidChange()
        require(installations == 1 && reservations == 1,
                "Nil-error cycle completion left a stale waiting handler that later reserved capture")

        let ownsSilentInstall = runtime.updater(updater, willInstallUpdateOnQuit: item) { immediateInstalls += 1 }
        require(!ownsSilentInstall && immediateInstalls == 0,
                "Runtime replaced standard install-on-quit with a silent relaunch scheduler")
        let downloadedStatus = runtime.status
        runtime.updater(updater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)
        require(runtime.status == downloadedStatus && !reserved && releases == 1,
                "Normal install-on-quit preparation was incorrectly treated as a cancelled install")
        require(runtime.allowedSystemProfileKeys(for: updater)?.isEmpty == true &&
                runtime.feedParameters(for: updater, sendingSystemProfile: true).isEmpty,
                "Update checks include system profile or custom identifying parameters")

        // A synchronous error may arrive from the continuation itself. Its
        // failure status must survive activityDidChange returning afterward.
        _ = runtime.updater(updater, shouldPostponeRelaunchForUpdate: item) {
            require(reserved, "Retry was not reserved")
            runtime.updater(updater, didAbortWithError: NSError(domain: "Fixture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected simulated failure"]))
        }
        runtime.activityDidChange()
        require(!reserved && releases == 2 && runtime.status.contains("Expected simulated failure"),
                "Synchronous installation failure lost its status or kept capture blocked")

        busy = true
        _ = runtime.updater(updater, shouldPostponeRelaunchForUpdate: item) { installations += 1 }
        runtime.updater(updater, didAbortWithError: NSError(domain: "Fixture", code: 2))
        busy = false
        runtime.activityDidChange()
        require(installations == 1 && reservations == 2,
                "An aborted waiting continuation was later invoked")
        require(NSApplication.shared.windows.allSatisfy { !$0.isVisible }, "Fixture showed a window")
        print("PASS: real Sparkle delegates defer busy relaunch, reserve before callback, clear terminal/cancelled cycles, recover from abort, and preserve install-on-quit/privacy")
    }
}
