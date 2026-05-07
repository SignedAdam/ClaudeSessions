# Cycle 03 — Save & Backup

## Focus
Implement ConversationWriter and BackupService. When user clicks Save (Cmd+S), backup the original file then write the modified conversation.

## Key Design: Lossless Round-Tripping
This is the MOST CRITICAL aspect. Unmodified entries must be written back byte-for-byte identical.

## Implementation
1. BackupService — copy original to ~/.claude-sessions-backups/<sessionId>/<timestamp>.jsonl
2. ConversationWriter — iterate rawEntries, write rawJSON for unmodified, re-serialize for modified
3. Wire Save button in toolbar to Cmd+S
4. Toast feedback on save
5. Backup retention (keep last 20)
