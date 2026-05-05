import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func configure(with appModel: AppModel) {
        guard statusItemController == nil else { return }
        statusItemController = StatusItemController(appModel: appModel)
    }
}
