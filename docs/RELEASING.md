# Releasing

Audience: maintainers. Users do not need this. Contributors do not need this.

## Rule

`main` is not a release. A tag is a release.

- Push to `main` → CI builds the code.
- Push `vX.Y.Z` → GitHub Actions builds the universal macOS DMG/ZIP and publishes a GitHub Release.

## Cut a release

```bash
git checkout main
git pull --ff-only
swift build -c release
```

Choose the version:

- patch: fix, docs that matter, small polish;
- minor: user-visible feature;
- major: compatibility break or data-model break.

Tag and push:

```bash
git tag -a v0.2.1 -m "v0.2.1"
git push origin v0.2.1
```

Watch it:

```bash
gh run list --repo SignedAdam/ClaudeSessions --limit 5
gh run watch <run-id> --repo SignedAdam/ClaudeSessions --exit-status
```

Then inspect the release:

```bash
gh release view v0.2.1 --repo SignedAdam/ClaudeSessions --web
```

## Release notes

Short. Specific. Human.

Say what changed since the last tag. Say if the build is ad-hoc signed. Do not paste generated fog.

## Local packaging smoke test

Optional, useful before a meaningful tag:

```bash
ALLOW_SINGLE_ARCH_FALLBACK=0 ./scripts/make_dmg.sh 0.2.1
open build/Claude-Sessions-0.2.1.dmg
```

Never commit release artifacts.

## Bad release

If nobody has downloaded it: delete the release and tag, fix, retag.

If people may have it: do not rewrite history. Ship the next version.
