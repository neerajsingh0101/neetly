import AppKit
import Sparkle

/// Wraps Sparkle's SPUStandardUpdaterController to provide auto-updates.
/// Reads SUFeedURL and SUPublicEDKey from the app's Info.plist.
class Updater: NSObject {
    static let shared = Updater()

    private let updaterController: SPUStandardUpdaterController

    override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }
}
