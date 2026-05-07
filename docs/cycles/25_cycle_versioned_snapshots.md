# Cycle 25 — Versioned snapshots in BackupEngine (P1.T05)

**Task:** Detect non-append rewrites of source JSONLs and preserve the prior backup as a versioned snapshot instead of letting the new content overwrite it.

## Background (from T01 findings)

Compaction itself is append-only — the file just grows. So the threats this work needs to defend against are:

1. **`cleanupPeriodDays` deletion + later re-creation at the same path.** Unlikely in practice (sessionId is a UUID), but theoretically possible.
2. **Future Claude Code behavior** that rewrites a session file in place. Not a behavior today, but defensive.
3. **Manual edits from outside the app** — e.g. if the user runs a script that rewrites JSONL files.

The existing engine already handled three cases:
- size grew → append delta (Case C)
- size shrank → rotate + full re-copy (Case D)
- size same, mtime moved → in-place full re-copy (Case E)

But Case E **wasn't preserving the prior version**, and there was no protection against a "size grew" event that's actually a brand-new file with different content.

## What I changed

Added a `firstLineSignature: String?` field to `BackupManifest.FileState`. It's the first line of the source JSONL, capped at 1 KB. JSONL is line-delimited and the first line is usually distinctive (custom-title, last-prompt, or first user message), so a change in this signature is a strong indicator the file was rewritten.

In `BackupEngine.syncFile`:

- Read the current first-line signature once before any branches.
- New branch right after Case B (revived): if the manifest has a recorded signature AND the current signature differs, rotate the existing backup to `<path>.orig-<unixts>` and full-re-copy regardless of size direction. Logs as `rewrite-detected`.
- Case A (initial-copy) and Case B (revived): record the signature.
- Case C (append): record the signature lazily if it was missing (back-compat for old manifests).
- Case D (shrink): record the new signature on the re-copy.
- Case E (in-place rewrite): now also rotates the old backup to `.orig-<ts>` so you keep the prior version. Previously it just overwrote in place.

`firstLineSignature` is `Optional<String>` so older manifests still decode fine. They just acquire a signature on the next sync; no migration step needed.

## What I did *not* do

- I didn't add a tool to *list* or *prune* `.orig-<ts>` files. That's a separate cleanup feature; not needed yet. The mirror grows monotonically, which is correct: never lose data on the backup side.
- I didn't add hashing (e.g. SHA-256 of the prefix). Storing the line itself is simpler and the size overhead is negligible (~500 bytes per tracked file).

## Build status

`swift build` clean.

## Files changed

- `Sources/ContinuousBackup/BackupManifest.swift` (new field)
- `Sources/ContinuousBackup/BackupEngine.swift` (signature read, new branch, Case E rotates, signature recorded everywhere)
- `docs/STAGE_2_ROADMAP.md` — T05 → done
