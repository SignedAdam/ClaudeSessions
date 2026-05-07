import AppKit
import Foundation

/// Runtime Dock-icon variants. The bundled app icon remains `AppIcon.icns`
/// for Finder/Gatekeeper; this controls the icon NSApplication shows while
/// the app is running.
enum DockIconVariant: String, CaseIterable, Identifiable {
    case amber
    case violet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amber: return "Amber"
        case .violet: return "Violet"
        }
    }

    var subtitle: String {
        switch self {
        case .amber: return "Warm gold on midnight navy"
        case .violet: return "Purple glass, blue/pink orbit"
        }
    }

    var resourceName: String {
        switch self {
        case .amber: return "AppIcon"
        case .violet: return "AppIconViolet"
        }
    }

    static let defaultsKey = "dockIconVariant"
    static let fallback: DockIconVariant = .amber

    static func fromDefaults() -> DockIconVariant {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? fallback.rawValue
        return DockIconVariant(rawValue: raw) ?? fallback
    }
}

enum DockIconManager {
    static func applyFromDefaults() {
        apply(DockIconVariant.fromDefaults())
    }

    static func apply(_ variant: DockIconVariant) {
        UserDefaults.standard.set(variant.rawValue, forKey: DockIconVariant.defaultsKey)
        if let image = image(for: variant) {
            NSApp.applicationIconImage = image
        } else {
            NSApp.applicationIconImage = AppIcon.makeImage()
        }
    }

    static func image(for variant: DockIconVariant) -> NSImage? {
        if let image = NSImage(named: variant.resourceName) {
            return image
        }

        if let url = Bundle.main.url(forResource: variant.resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        // SwiftPM development fallback: resources are not automatically
        // bundled into executable targets, but `swift run` is normally run
        // from the repository root.
        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(variant.resourceName).png")
        if let image = NSImage(contentsOf: localURL) {
            return image
        }

        return nil
    }
}
