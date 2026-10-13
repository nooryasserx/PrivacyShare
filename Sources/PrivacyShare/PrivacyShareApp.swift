import AppKit
import SwiftUI

@main
struct PrivacyShareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = OverlayManager()
    @StateObject private var settings = PrivacySettings.shared

    var body: some Scene {
        Window("PrivacyShare", id: "control") {
            ContentView()
                .environmentObject(manager)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)

        // Small icon in the menu bar so the app keeps protecting you after you close the window.
        MenuBarExtra("PrivacyShare", systemImage: manager.isEnabled ? "eye.slash.fill" : "eye") {
            MenuContent()
                .environmentObject(manager)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var manager: OverlayManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(manager.isEnabled ? "إيقاف الحماية" : "تشغيل الحماية") {
            Task { await manager.toggle() }
        }
        Button("الإعدادات…") {
            openWindow(id: "control")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("خروج") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
