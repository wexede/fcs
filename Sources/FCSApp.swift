import SwiftUI
import AppKit

@main
struct FCSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("FCS", id: "main") {
            RootView()
                .environmentObject(FCSStore.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    /// Закрытие окна не завершает приложение — блокировка приложений работает в фоне.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard FCSStore.shared.isActive else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Блокировка активна"
        alert.informativeText = "Если выйти из FCS, блокировка приложений (Telegram, Spotify и др.) перестанет работать. Сайты останутся заблокированными до остановки или конца таймера."
        alert.addButton(withTitle: "Отмена")
        alert.addButton(withTitle: "Выйти")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
