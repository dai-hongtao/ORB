import SwiftUI

@main
struct ORBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("app.name") {
            ContentView()
                .environmentObject(appModel)
                .environment(\.locale, appModel.appLocale)
                .onAppear {
                    appDelegate.configure(with: appModel)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("language.menu") {
                Picker("language.menu", selection: $appModel.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.titleKey))
                            .tag(language)
                    }
                }
            }
        }
    }
}
