import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let appModel: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let connectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
    private let developerSettingsItem = NSMenuItem(title: "", action: #selector(openDeveloperSettings), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")
    private var cancellables = Set<AnyCancellable>()

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
        configureMenu()
        configureStatusItem()
        bind()
    }

    private func configureMenu() {
        connectionItem.isEnabled = false
        settingsItem.target = self
        developerSettingsItem.target = self
        quitItem.target = self
        menu.items = [
            connectionItem,
            NSMenuItem.separator(),
            settingsItem,
            developerSettingsItem,
            NSMenuItem.separator(),
            quitItem
        ]
        update(status: appModel.connectionStatus)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        update(status: appModel.connectionStatus)
    }

    private func bind() {
        appModel.$connectionStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.update(status: status)
            }
            .store(in: &cancellables)

        appModel.$appLanguage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.update(status: self.appModel.connectionStatus)
            }
            .store(in: &cancellables)
    }

    private func update(status: ConnectionStatus) {
        settingsItem.title = appModel.localized("status_menu.open_main_window")
        developerSettingsItem.title = appModel.localized("status_menu.developer_settings")
        quitItem.title = appModel.localized("status_menu.quit")
        connectionItem.title = String(
            format: appModel.localized("status_menu.connection_status"),
            appModel.localized(status.labelKey)
        )

        guard let button = statusItem.button else { return }
        let image = statusBarIcon() ?? NSImage(
            systemSymbolName: status.systemImage,
            accessibilityDescription: appModel.localized(status.labelKey)
        )
        image?.isTemplate = false
        button.image = image
        button.imagePosition = .imageOnly
    }

    private func statusBarIcon() -> NSImage? {
        let url = Bundle.main.url(
            forResource: "icon_22x22",
            withExtension: "png",
            subdirectory: "resources/orb_icon_set"
        ) ?? Bundle.main.url(
            forResource: "icon_22x22",
            withExtension: "png"
        )

        guard let url else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    @objc
    private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }

        appModel.presentMainWindow()
    }

    @objc
    private func openSettings() {
        appModel.presentMainWindow()
    }

    @objc
    private func openDeveloperSettings() {
        appModel.showMaintenance()
        appModel.presentMainWindow()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
