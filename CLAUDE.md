# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Run all tests (must run from packages/ directory to avoid cache conflicts)
cd packages && very_good test -r

# Run tests for a single package (can use -r failures-only to reduce output)
dart test packages/shorebird_cli
```

## Architecture

Dart monorepo. Main package is `shorebird_cli`.

**Platform-specific operations** use the Releaser/Patcher pattern:
- `commands/release/` - `Releaser` base class with platform implementations
- `commands/patch/` - `Patcher` base class with platform implementations

**Dependency injection** uses `scoped_deps` with zone-based refs (see any `*Ref` variable).

## Code Style

- PR titles must follow semantic commit format (enforced in CI)
- CSpell: use inline `// cspell:words` for 1-2 files; add to global config for more
- Prefer new commits over amending in PRs - history gets squashed anyway

## Landing a PR

A PR can land when all of these hold at its current head commit:

- The review bot used on Shorebird's private repos doesn't run here, so an agent-authored PR gets that same review run locally: a separate agent, not the one that wrote the change, reviews the full diff adversarially, looking for reasons it should not land, and its findings are posted as their own PR comment. Blockers are fixed or answered before asking for an LGTM.
- A maintainer has LGTM'd: a `lgtm` comment, an approving review, or the maintainer opening the PR themselves. A PR an agent opened needs a maintainer's LGTM. An LGTM approves the direction, so small follow-up fixes, rebases and merges from `main` keep it. Ask again when the scope or approach changes.
- CI is green. Check it again right before merging.

Then squash-merge, pinned to the head you checked:

```sh
gh pr merge <N> --admin --squash --match-head-commit <full sha>
```
