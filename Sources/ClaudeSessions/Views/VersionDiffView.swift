import SwiftUI

/// Render a per-uuid set-diff between two JSONL versions of the same
/// session. Removed entries (in the left/older version, missing from the
/// right/newer) are red; added entries are green. Each entry shows its
/// type + role + a one-line preview.
struct VersionDiffView: View {
    let left: VersionHistoryService.Version
    let right: VersionHistoryService.Version
    @Binding var isPresented: Bool

    @State private var result: VersionDiffService.Result?
    @State private var loading: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 760, height: 560)
        .background(Theme.surface)
        .onAppear { compute() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right.square")
                    .foregroundStyle(Theme.accent)
                Text("Version diff")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark").foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Text("older")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.errorTint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.errorTint.opacity(0.12))
                    .clipShape(Capsule())
                Text(left.kind.label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(formatTimestamp(left.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
                Text("newer")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.successTint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.successTint.opacity(0.12))
                    .clipShape(Capsule())
                Text(right.kind.label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(formatTimestamp(right.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let r = result {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summaryBar(r)
                    Divider().opacity(0.3).padding(.vertical, 8)
                    if r.removed.isEmpty && r.added.isEmpty {
                        identical
                    } else {
                        section(title: "Removed (only in older)",
                                tint: Theme.errorTint,
                                hunks: r.removed)
                        if !r.removed.isEmpty && !r.added.isEmpty {
                            Divider().opacity(0.3).padding(.vertical, 8)
                        }
                        section(title: "Added (only in newer)",
                                tint: Theme.successTint,
                                hunks: r.added)
                    }
                }
                .padding(16)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Comparing by entry uuid — JSONL is append-only, so a uuid that's missing from one side wasn't there at that point in time.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Close") { isPresented = false }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Pieces

    private func summaryBar(_ r: VersionDiffService.Result) -> some View {
        HStack(spacing: 10) {
            statChip(label: "older", count: r.leftCount, tint: Theme.errorTint)
            statChip(label: "newer", count: r.rightCount, tint: Theme.successTint)
            statChip(label: "shared", count: r.commonCount, tint: Theme.textSecondary)
            Spacer()
            statChip(label: "removed", count: r.removed.count, tint: Theme.errorTint)
            statChip(label: "added", count: r.added.count, tint: Theme.successTint)
        }
    }

    private func statChip(label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(tint)
            Text("\(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(tint.opacity(0.08))
        .clipShape(Capsule())
    }

    private var identical: some View {
        VStack(spacing: 6) {
            Image(systemName: "equal.circle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.successTint)
            Text("Identical")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
            Text("Both versions contain the same set of entries (matching by uuid).")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func section(title: String, tint: Color, hunks: [VersionDiffService.Hunk]) -> some View {
        if !hunks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                    Text("(\(hunks.count))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(hunks) { hunk in
                    hunkRow(hunk: hunk, tint: tint)
                }
            }
        }
    }

    private func hunkRow(hunk: VersionDiffService.Hunk, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(hunk.role.isEmpty ? hunk.entryType : hunk.role)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .frame(width: 64, alignment: .leading)
            Text(hunk.preview.isEmpty ? "<no preview>" : hunk.preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Compute

    private func compute() {
        loading = true
        Task.detached(priority: .userInitiated) {
            // Order: left = older, right = newer. The caller passes them
            // in selection order, but we want the time-ordered view here.
            let (oldVersion, newVersion) = orderedByTime(a: left, b: right)
            let r = VersionDiffService.diff(left: oldVersion.filePath,
                                            right: newVersion.filePath)
            await MainActor.run {
                result = r
                loading = false
            }
        }
    }

    private func orderedByTime(a: VersionHistoryService.Version,
                               b: VersionHistoryService.Version)
        -> (VersionHistoryService.Version, VersionHistoryService.Version) {
        if a.timestamp <= b.timestamp { return (a, b) }
        return (b, a)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: date)
    }
}
