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

- The author has posted a self-review comment: the full diff read as a reviewer, with any blockers fixed or called out.
- A maintainer has LGTM'd: a `lgtm` comment or an approving review. The PR author opening the PR does not count. An LGTM approves the direction, so small follow-up fixes, rebases and merges from `main` keep it. Ask again when the scope or approach changes.
- CI is green. Check it again right before merging.

Then squash-merge, pinned to the head you checked:

```sh
gh pr merge <N> --admin --squash --match-head-commit <full sha>
```
