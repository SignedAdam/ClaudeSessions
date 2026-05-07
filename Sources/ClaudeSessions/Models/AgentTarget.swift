import SwiftUI

/// External coding agents we can hand a conversation off to.
///
/// Each target has its own export pipeline (native session format where
/// possible, markdown otherwise) and its own brand styling for the UI.
enum AgentTarget: String, CaseIterable, Identifiable, Codable {
    case codex
    case gemini
    case opencode
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:    return "Codex"
        case .gemini:   return "Gemini"
        case .opencode: return "opencode"
        case .cursor:   return "Cursor"
        }
    }

    var tagline: String {
        switch self {
        case .codex:    return "OpenAI's terminal coding agent"
        case .gemini:   return "Google's coding agent"
        case .opencode: return "Open-source TUI agent"
        case .cursor:   return "AI-native editor"
        }
    }

    /// CLI binary name (where applicable). Cursor has no resume-chat CLI.
    var cliBinary: String? {
        switch self {
        case .codex:    return "codex"
        case .gemini:   return "gemini"
        case .opencode: return "opencode"
        case .cursor:   return nil
        }
    }
}

// MARK: - Brand styling

extension AgentTarget {
    /// Wordmark gradient — applied to the rendered display name.
    /// Hand-tuned per brand from real screenshots.
    var brandGradient: LinearGradient {
        switch self {
        case .codex:
            // Codex: purple-blue cloud → soft lavender
            return LinearGradient(
                colors: [Color(hex: 0x7B61FF), Color(hex: 0xA88BFF)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gemini:
            // Gemini: signature blue → purple → magenta horizontal sweep
            return LinearGradient(
                colors: [
                    Color(hex: 0x4285F4),
                    Color(hex: 0x9168C0),
                    Color(hex: 0xE94888),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .opencode:
            // opencode: monochrome with purple lift
            return LinearGradient(
                colors: [Color(hex: 0xC4B5FD), Color(hex: 0x7C3AED)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .cursor:
            // Cursor: slate steel → near black
            return LinearGradient(
                colors: [Color(hex: 0xB8B8B8), Color(hex: 0x2E2E2E)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Solid representative color — used for tinted backgrounds, hover
    /// states, and the dropdown menu icon swatch.
    var brandColor: Color {
        switch self {
        case .codex:    return Color(hex: 0x8B7BFF)
        case .gemini:   return Color(hex: 0x9168C0)
        case .opencode: return Color(hex: 0x7C3AED)
        case .cursor:   return Color(hex: 0x6B6B6B)
        }
    }

    /// Wordmark font — opencode is monospace by convention; the others
    /// use a clean modern sans.
    var wordmarkFont: Font {
        switch self {
        case .opencode:
            return .system(size: 11, weight: .bold, design: .monospaced)
        default:
            return .system(size: 12, weight: .heavy, design: .default)
        }
    }

    /// Whether the displayName should render lowercased (opencode brand
    /// is always lowercase).
    var lowercaseWordmark: Bool { self == .opencode }

    /// SF Symbol used as a left-side glyph alongside the wordmark.
    var glyph: String {
        switch self {
        case .codex:    return "cloud.fill"
        case .gemini:   return "sparkles"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        case .cursor:   return "cursorarrow.rays"
        }
    }
}
