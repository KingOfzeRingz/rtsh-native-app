import SwiftUI

@main
struct rtsh_native_appApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Assistant", systemImage: "brain.head.profile") {
            Button("Show/Hide Assistant") {
                appDelegate.toggleOverlay()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
