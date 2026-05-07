import SwiftUI
import AppKit

/// Resolve the hosting NSWindow so we can configure native properties
/// (titlebar transparency, full-size content, etc.) from SwiftUI.
struct WindowAccessor: NSViewRepresentable {
    let onResolved: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let win = v.window { onResolved(win) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let win = nsView.window { onResolved(win) }
        }
    }
}

/// A background helper that tells macOS "the window cannot be dragged by
/// clicks in this region." Essential for placing interactive controls
/// inside the titlebar area when `.windowStyle(.hiddenTitleBar)` and
/// `fullSizeContentView` are in effect.
///
/// Use as `.background(NoWindowDrag())` behind buttons that live in the
/// top bar. SwiftUI Buttons alone aren't enough: their underlying NSViews
/// inherit drag-ability from the NSHostingView, so macOS routes the click
/// as a window drag before the Button gets it.
struct NoWindowDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NoDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class NoDragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
