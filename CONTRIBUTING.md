# Contributing

Claude Sessions is a local-first macOS app for people who live inside Claude Code. Contributions should protect that premise.

## The path

- Open an issue for bugs, sharp ideas, or uncertain behavior.
- Fork the repo.
- Open a pull request against `main`.
- Keep PRs small enough to judge. One feature, one fix, one theme pass.

No private transcript data in issues, screenshots, fixtures, or logs. Redact paths, names, prompts, and outputs.

## Local development

```bash
git clone https://github.com/SignedAdam/ClaudeSessions.git
cd ClaudeSessions
swift build -c release
swift run ClaudeSessions
```

To test packaging locally:

```bash
CURRENT_ARCH_ONLY=1 ./scripts/make_dmg.sh dev
```

Do not commit `build/`, `.build/`, DMGs, ZIPs, or personal Claude data.

## PR standard

A good PR says:

- what changed;
- why it exists;
- how it was tested;
- what can go wrong with user data.

For UI changes, add a screenshot or short screen recording. For file-writing changes, describe the failure mode. This app touches conversation history; caution wins.

## Design rules

- Local-first. No surprise network calls.
- No telemetry.
- No database unless the win is overwhelming.
- Zero dependencies unless the alternative is worse.
- Preserve originals. Prefer fork, archive, trash, backup.
- Keep the UI native, fast, and quiet.

## Releases

Maintainers cut releases. Normal pushes run CI only. Versioned tags (`vX.Y.Z`) publish macOS assets.

The maintainer ritual lives in [`docs/RELEASING.md`](docs/RELEASING.md). Contributors do not need it to open a good PR.
