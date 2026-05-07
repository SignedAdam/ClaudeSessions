import SwiftUI

/// A single row in the sidebar's session list.
///
/// Kept deliberately dumb: takes its state as plain props instead of
/// observing environment objects, so a ForEach of hundreds of rows doesn't
/// cascade re-renders across every row whenever any store publishes.
struct SessionRow: View {
    let session: SessionInfo
    let isSelected: Bool
    let isDirty: Bool
    let isHidden: Bool
    let isFavorite: Bool
    /// When true, render a subtle project-name hint above the title so a row
    /// pulled into the Favorites section stays identifiable without opening it.
    var showProjectHint: String? = nil
    let onSelect: () -> Void
    let onToggleHidden: () -> Void
    let onToggleFavorite: () -> Void
    let onArchive: () -> Void
    let onMoveToProject: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? Theme.accent : Color.clear)
                    .frame(width: 2, height: 24)
                    .padding(.trailing, 10)

                VStack(alignment: .leading, spacing: 2) {
                    if let hint = showProjectHint {
                        Text(hint)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                    }

                    HStack(spacing: 5) {
                        if isHidden {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.textFaint)
                        }
                        if session.isSubagent {
                            Image(systemName: "sparkle")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.toolTint)
                                .help("Subagent that ran under this session")
                        }
                        Text(session.title)
                            .font(.system(size: session.isSubagent ? 11 : 12,
                                          weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
                            .italic(isHidden)
                            .lineLimit(2)
                    }

                    HStack(spacing: 5) {
                        if isDirty {
                            Circle().fill(Theme.warnTint).frame(width: 4, height: 4)
                        }
                        Text(DateFormatting.dateString(session.modified))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 8)

                // Star — visible when favorited OR on hover. Click toggles
                // favorite without selecting the session.
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isFavorite ? Theme.warnTint : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .opacity(isFavorite ? 1 : (hovered ? 0.7 : 0))
                .help(isFavorite ? "Unstar" : "Star session")
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(isSelected ? Theme.sidebarActive : Color.clear)
            .opacity(isHidden ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(isFavorite ? "Unstar" : "Star", action: onToggleFavorite)
            Button(isHidden ? "Unhide" : "Hide", action: onToggleHidden)
            Button("Archive", action: onArchive)
            Button("Copy to Project…", action: onMoveToProject)

            Divider()

            Button("Move to Trash…", role: .destructive, action: onDelete)

            Divider()

            Button("Open in Finder") {
                let dir = (session.filePath as NSString).deletingLastPathComponent
                NSWorkspace.shared.selectFile(session.filePath, inFileViewerRootedAtPath: dir)
            }
            Button("Copy Session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.filePath, forType: .string)
            }
        }
    }
}
