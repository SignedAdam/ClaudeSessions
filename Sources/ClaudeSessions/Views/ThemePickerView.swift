import SwiftUI

/// Popover-style theme picker shown from the top bar paintpalette icon.
struct ThemePickerView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Palette")
                VStack(spacing: 6) {
                    ForEach(ThemePalette.allPalettes) { palette in
                        PaletteRow(
                            palette: palette,
                            isSelected: palette.id == themeStore.current.id,
                            action: { themeStore.setPalette(palette) }
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Conversation")
                VStack(spacing: 4) {
                    ForEach(ConversationStyle.allCases) { style in
                        ConversationStyleRow(
                            style: style,
                            isSelected: themeStore.conversationStyle == style,
                            action: { themeStore.conversationStyle = style }
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Ambience")
                Toggle(isOn: $themeStore.wavyBackgroundEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ambient field")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("Slow, drifting color wash — nearly still, but alive")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 320)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.border.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
    }

    private var header: some View {
        HStack {
            Text("Appearance")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Conversation style row

private struct ConversationStyleRow: View {
    let style: ConversationStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(style.description)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(hovered || isSelected ? Theme.surface2 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}

// MARK: - Palette row

private struct PaletteRow: View {
    let palette: ThemePalette
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Swatch: background + dotted accents
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(palette.background)
                    HStack(spacing: 2) {
                        Circle().fill(palette.accent).frame(width: 7, height: 7)
                        Circle().fill(palette.humanTint).frame(width: 7, height: 7)
                        Circle().fill(palette.toolTint).frame(width: 7, height: 7)
                    }
                }
                .frame(width: 54, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(palette.border, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(palette.id)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovered || isSelected ? Theme.surface2 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}
