import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: OverlayWindow?
    let appState = AppState() // Shared state instance

    func applicationDidFinishLaunching(_ notification: Notification) {
        showOverlay()
    }
    
    func toggleOverlay() {
        if let window = overlayWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            showOverlay()
        }
    }
    
    private func showOverlay() {
        // Create the SwiftUI view that provides the window contents.
        // We inject the appState here.
        let contentView = ContentView()
            .environmentObject(appState)
            .frame(width: 360, height: 500) // Compact size
            .background(.ultraThinMaterial) // Use SwiftUI material for blur
            .cornerRadius(24) // Match the corner radius
            .ignoresSafeArea() // Ensure it fills the window

        let hostingView = NSHostingView(rootView: contentView)
        // hostingView.backgroundColor = .clear // Not available on NSView, handled by SwiftUI background

        
        let window = OverlayWindow(view: hostingView)
        window.makeKeyAndOrderFront(nil)
        self.overlayWindow = window
    }
}
