import SwiftUI

// MARK: - ThemePalette

/// A complete color palette. Swappable at runtime via ThemeStore.
struct ThemePalette: Identifiable, Equatable {
    let id: String
    let name: String

    /// True if this palette has a light background. Some views invert
    /// their chroma logic (hover overlays, code block tints) based on this.
    let isLight: Bool

    // Foundation
    let background: Color
    let surface: Color
    let surface2: Color
    let surfaceRaised: Color
    let border: Color

    // Text hierarchy
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let textFaint: Color

    // Accent (brand)
    let accent: Color
    let accentDim: Color
    let accentBg: Color

    // Functional
    let humanTint: Color
    let toolTint: Color
    let warnTint: Color
    let errorTint: Color
    let successTint: Color

    // Sidebar
    let sidebarBg: Color
    let sidebarHover: Color
    let sidebarActive: Color

    // Interaction
    let selectionGlow: Color
    let hoverGlow: Color

    // Code blocks / monospaced insets (theme-aware replacement for
    // the hardcoded `Color.black.opacity(x)` we used everywhere)
    let codeBackground: Color
    let codeBorder: Color
}

// MARK: - Preset palettes
//
// Five palettes, each built around a distinct *mode of use*. Borders are
// meaningfully lighter than their surfaces so components always have real
// edges. Text is carefully tuned to contrast with the background, never
// pure white/black unless that's intentional.

extension ThemePalette {

    /// STUDIO — everyday default. Warm lavender accent over near-black
    /// with a violet undertone. Cream text, not blue-white.
    static let studio = ThemePalette(
        id: "studio", name: "Studio", isLight: false,
        background:     Color(hex: 0x0e0c14),
        surface:        Color(hex: 0x181522),
        surface2:       Color(hex: 0x221d2e),
        surfaceRaised:  Color(hex: 0x2c263c),
        border:         Color(hex: 0x3a3248),        // stronger than before
        text:           Color(hex: 0xe6dfd0),
        textSecondary:  Color(hex: 0xa09a90),
        textTertiary:   Color(hex: 0x6c6672),
        textFaint:      Color(hex: 0x463f4e),
        accent:         Color(hex: 0xbca0ee),
        accentDim:      Color(hex: 0x7c6ba0),
        accentBg:       Color(hex: 0x1a1428),
        humanTint:      Color(hex: 0x8fb8d0),
        toolTint:       Color(hex: 0x9abca0),
        warnTint:       Color(hex: 0xe0b878),
        errorTint:      Color(hex: 0xd07878),
        successTint:    Color(hex: 0x9abca0),
        sidebarBg:      Color(hex: 0x0a0910),
        sidebarHover:   Color(hex: 0x15121e),
        sidebarActive:  Color(hex: 0x1e1a2c),
        selectionGlow:  Color(hex: 0xbca0ee, alpha: 0.10),
        hoverGlow:      Color(hex: 0xffffff, alpha: 0.035),
        codeBackground: Color(hex: 0x07060a),
        codeBorder:     Color(hex: 0x2a2438)
    )

    /// PAPER — for reading. Leather-bound-book feel. Wenge brown with
    /// aged gold, warm ivory text. Low blue light.
    static let paper = ThemePalette(
        id: "paper", name: "Paper", isLight: false,
        background:     Color(hex: 0x1a1410),
        surface:        Color(hex: 0x241b13),
        surface2:       Color(hex: 0x2e2319),
        surfaceRaised:  Color(hex: 0x382c20),
        border:         Color(hex: 0x4e3e2e),
        text:           Color(hex: 0xede4d0),
        textSecondary:  Color(hex: 0xb09878),
        textTertiary:   Color(hex: 0x806a53),
        textFaint:      Color(hex: 0x554533),
        accent:         Color(hex: 0xd4a853),
        accentDim:      Color(hex: 0x8a6d38),
        accentBg:       Color(hex: 0x241a0e),
        humanTint:      Color(hex: 0xc49878),
        toolTint:       Color(hex: 0x98a878),
        warnTint:       Color(hex: 0xd4a853),
        errorTint:      Color(hex: 0xc07060),
        successTint:    Color(hex: 0x98a878),
        sidebarBg:      Color(hex: 0x130e0a),
        sidebarHover:   Color(hex: 0x1e160f),
        sidebarActive:  Color(hex: 0x271c13),
        selectionGlow:  Color(hex: 0xd4a853, alpha: 0.12),
        hoverGlow:      Color(hex: 0xffeec0, alpha: 0.04),
        codeBackground: Color(hex: 0x110c08),
        codeBorder:     Color(hex: 0x3e3020)
    )

    /// OBSERVATORY — dark-adapted. Deep blue-black with dim amber.
    static let observatory = ThemePalette(
        id: "observatory", name: "Observatory", isLight: false,
        background:     Color(hex: 0x080c14),
        surface:        Color(hex: 0x111724),
        surface2:       Color(hex: 0x1a2132),
        surfaceRaised:  Color(hex: 0x232c40),
        border:         Color(hex: 0x304056),
        text:           Color(hex: 0xd8dce0),
        textSecondary:  Color(hex: 0x8c96a0),
        textTertiary:   Color(hex: 0x5a6472),
        textFaint:      Color(hex: 0x3a4450),
        accent:         Color(hex: 0xe89c58),
        accentDim:      Color(hex: 0x8c623a),
        accentBg:       Color(hex: 0x1a140e),
        humanTint:      Color(hex: 0x7ca0bc),
        toolTint:       Color(hex: 0x88a090),
        warnTint:       Color(hex: 0xe89c58),
        errorTint:      Color(hex: 0xc06870),
        successTint:    Color(hex: 0x88a090),
        sidebarBg:      Color(hex: 0x050810),
        sidebarHover:   Color(hex: 0x0c1220),
        sidebarActive:  Color(hex: 0x141e30),
        selectionGlow:  Color(hex: 0xe89c58, alpha: 0.12),
        hoverGlow:      Color(hex: 0xffffff, alpha: 0.03),
        codeBackground: Color(hex: 0x040710),
        codeBorder:     Color(hex: 0x1e2838)
    )

    /// STELLAR — deep rich navy with bold, iconic accents.
    /// Inspired by NASA's 1970s Space Art posters and illustrated astronomy
    /// books. Not restrained — confident, saturated colors on a deep-space
    /// blue. Warm beige-white text reads like printed ink on a star chart.
    static let stellar = ThemePalette(
        id: "stellar", name: "Stellar", isLight: false,
        background:     Color(hex: 0x0b1838),         // deep rich navy
        surface:        Color(hex: 0x132548),
        surface2:       Color(hex: 0x1c315a),
        surfaceRaised:  Color(hex: 0x253c6c),
        border:         Color(hex: 0x3a5488),         // clearly visible against navy
        text:           Color(hex: 0xf2ecd8),         // warm beige-white, like paper
        textSecondary:  Color(hex: 0xc0b89c),
        textTertiary:   Color(hex: 0x7e7a6a),
        textFaint:      Color(hex: 0x4c4c42),
        accent:         Color(hex: 0xffc857),         // vivid gold — star at magnitude 1
        accentDim:      Color(hex: 0xa98a38),
        accentBg:       Color(hex: 0x2a1f0a),
        humanTint:      Color(hex: 0x6bcee8),         // bright cyan — distant planet
        toolTint:       Color(hex: 0x6fd9a8),         // vivid mint
        warnTint:       Color(hex: 0xffc857),
        errorTint:      Color(hex: 0xf0687f),         // coral nebula pink
        successTint:    Color(hex: 0x6fd9a8),
        sidebarBg:      Color(hex: 0x06102a),
        sidebarHover:   Color(hex: 0x0e1c3e),
        sidebarActive:  Color(hex: 0x182b56),
        selectionGlow:  Color(hex: 0xffc857, alpha: 0.18),
        hoverGlow:      Color(hex: 0xffeec0, alpha: 0.04),
        codeBackground: Color(hex: 0x060f28),
        codeBorder:     Color(hex: 0x2a3f66)
    )

    /// VELLUM — LIGHT theme. Cream parchment with VIVID crimson text, like
    /// fresh red ink on aged vellum. Auxiliary colors echo illuminated
    /// manuscripts: lapis navy (human), forest ink (tools), goldenrod
    /// (warnings). Designed so crimson reads as crimson, not brown blood.
    static let vellum = ThemePalette(
        id: "vellum", name: "Vellum", isLight: true,
        background:     Color(hex: 0xf4ead2),         // cream vellum
        surface:        Color(hex: 0xeadfbe),         // card base
        surface2:       Color(hex: 0xdfd1a8),         // slightly darker card
        surfaceRaised:  Color(hex: 0xd5c598),         // elevated element
        border:         Color(hex: 0xa48a60),         // rich warm brown — visible
        text:           Color(hex: 0xb91c1c),         // vivid crimson
        textSecondary:  Color(hex: 0x8a4a28),         // aged earth brown
        textTertiary:   Color(hex: 0xa06b40),         // dusty ochre
        textFaint:      Color(hex: 0xc0a078),         // faded tan
        accent:         Color(hex: 0xb8841c),         // gold leaf — interactive elements
        accentDim:      Color(hex: 0x8a6215),
        accentBg:       Color(hex: 0xedd9a4),
        humanTint:      Color(hex: 0x1e3a6e),         // deep lapis navy
        toolTint:       Color(hex: 0x2e6a3a),         // forest ink
        warnTint:       Color(hex: 0xb8841c),         // goldenrod
        errorTint:      Color(hex: 0xb91c1c),
        successTint:    Color(hex: 0x2e6a3a),
        sidebarBg:      Color(hex: 0xe6d8b0),         // darker, like book edge
        sidebarHover:   Color(hex: 0xddcea0),
        sidebarActive:  Color(hex: 0xd2bf88),
        selectionGlow:  Color(hex: 0xb8841c, alpha: 0.18),
        hoverGlow:      Color(hex: 0x2a1a08, alpha: 0.05),   // dark on light
        codeBackground: Color(hex: 0xe6d5a8),
        codeBorder:     Color(hex: 0xa48a60)
    )

    static let allPalettes: [ThemePalette] = [
        .studio, .paper, .observatory, .stellar, .vellum
    ]

    static func byId(_ id: String) -> ThemePalette {
        allPalettes.first(where: { $0.id == id }) ?? .studio
    }
}

// MARK: - Conversation style

/// How user/Claude message turns are laid out.
enum ConversationStyle: String, CaseIterable, Identifiable {
    /// Full-width, accent-strip on the leading edge. The default document feel.
    case document
    /// iMessage-style chat bubbles: user right-aligned accent, Claude left-aligned muted.
    case iMessage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .document: return "Document"
        case .iMessage: return "iMessage"
        }
    }

    var description: String {
        switch self {
        case .document: return "Full-width turns with an accent strip — archival feel"
        case .iMessage: return "Chat bubbles — you on the right, Claude on the left"
        }
    }
}

// MARK: - ThemeStore

/// Live, swappable theme. Views observe this to react to palette changes.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var current: ThemePalette

    @Published var wavyBackgroundEnabled: Bool {
        didSet { UserDefaults.standard.set(wavyBackgroundEnabled, forKey: "wavyBackgroundEnabled") }
    }

    @Published var conversationStyle: ConversationStyle {
        didSet { UserDefaults.standard.set(conversationStyle.rawValue, forKey: "conversationStyle") }
    }

    private init() {
        let paletteId = UserDefaults.standard.string(forKey: "themePaletteId") ?? ThemePalette.studio.id
        self.current = ThemePalette.byId(paletteId)
        self.wavyBackgroundEnabled = UserDefaults.standard.object(forKey: "wavyBackgroundEnabled") as? Bool ?? true

        let styleRaw = UserDefaults.standard.string(forKey: "conversationStyle") ?? ConversationStyle.document.rawValue
        self.conversationStyle = ConversationStyle(rawValue: styleRaw) ?? .document
    }

    func setPalette(_ palette: ThemePalette) {
        current = palette
        UserDefaults.standard.set(palette.id, forKey: "themePaletteId")
    }
}

// MARK: - Theme static accessor

enum Theme {
    static var background: Color       { ThemeStore.shared.current.background }
    static var surface: Color          { ThemeStore.shared.current.surface }
    static var surface2: Color         { ThemeStore.shared.current.surface2 }
    static var surfaceRaised: Color    { ThemeStore.shared.current.surfaceRaised }
    static var border: Color           { ThemeStore.shared.current.border }

    static var text: Color             { ThemeStore.shared.current.text }
    static var textSecondary: Color    { ThemeStore.shared.current.textSecondary }
    static var textTertiary: Color     { ThemeStore.shared.current.textTertiary }
    static var textFaint: Color        { ThemeStore.shared.current.textFaint }

    static var accent: Color           { ThemeStore.shared.current.accent }
    static var accentDim: Color        { ThemeStore.shared.current.accentDim }
    static var accentBg: Color         { ThemeStore.shared.current.accentBg }

    static var humanTint: Color        { ThemeStore.shared.current.humanTint }
    static var toolTint: Color         { ThemeStore.shared.current.toolTint }
    static var warnTint: Color         { ThemeStore.shared.current.warnTint }
    static var errorTint: Color        { ThemeStore.shared.current.errorTint }
    static var successTint: Color      { ThemeStore.shared.current.successTint }

    static var sidebarBg: Color        { ThemeStore.shared.current.sidebarBg }
    static var sidebarHover: Color     { ThemeStore.shared.current.sidebarHover }
    static var sidebarActive: Color    { ThemeStore.shared.current.sidebarActive }

    static var selectionGlow: Color    { ThemeStore.shared.current.selectionGlow }
    static var hoverGlow: Color        { ThemeStore.shared.current.hoverGlow }

    static var codeBackground: Color   { ThemeStore.shared.current.codeBackground }
    static var codeBorder: Color       { ThemeStore.shared.current.codeBorder }

    static var isLight: Bool           { ThemeStore.shared.current.isLight }
}

// MARK: - Color hex

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
