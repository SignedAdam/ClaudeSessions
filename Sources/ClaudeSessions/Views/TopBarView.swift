import SwiftUI
import AppKit

/// Thin top strip that just reserves space for the native macOS traffic lights.
/// Theme/settings controls moved to the bottom bar — the titlebar drag region
/// was unfriendly to SwiftUI Buttons.
struct TopBarView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Binding var showThemePicker: Bool   // kept for API compatibility; unused here

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 78)   // reserved for traffic lights
            Spacer()
        }
        .frame(height: 28)
        .background(Theme.sidebarBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1)
        }
    }
}

// MARK: - Small icon button (used in BottomBarView now)

struct TopBarIcon: View {
    let icon: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(hovered ? Theme.text : Theme.textSecondary)
                .frame(width: 26, height: 22)
                .background(hovered ? Theme.surface2 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}
