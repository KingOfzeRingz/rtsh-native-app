import AppKit
import SwiftUI

class OverlayWindow: NSWindow {
    init(view: NSView) {
        let style: NSWindow.StyleMask = [.borderless, .resizable] // Added resizable for better behavior
        
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 450, height: 625), // Increased size by 25%
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
        
        // Create the visual effect view for the glass background
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .hudWindow // The native "heavy glass" look
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 24
        visualEffect.layer?.masksToBounds = true
        
        // Add the SwiftUI view as a subview of the visual effect view
        view.frame = visualEffect.bounds
        view.autoresizingMask = [.width, .height]
        visualEffect.addSubview(view)
        
        self.contentView = visualEffect
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}
