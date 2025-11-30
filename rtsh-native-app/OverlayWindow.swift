import AppKit
import SwiftUI

class OverlayWindow: NSWindow {
    init(view: NSView) {
        let style: NSWindow.StyleMask = [.borderless, .resizable] // Added resizable for better behavior
        
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 500), // Compact size
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]
        
        self.ignoresMouseEvents = false
        self.isMovableByWindowBackground = true
        self.center()
        
        self.contentView = view
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}
