# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Report anything unexpected, with a proposed fix

When the CLI, packages, tests, docs, or CI behave in a way you didn't expect, say so in your final report, even if you worked around it and finished the task. Examples: a `shorebird` command that waits with no output, a command or flag whose default does something surprising, an error message that doesn't say what to do, a test that fails for reasons unrelated to the change, a local Dart or Flutter toolchain that doesn't match CI.

For each one, give what you did, what you expected, what happened, and a proposed fix: a PR if it's small and you have the context, otherwise an issue-sized description. Don't report your own mistakes as product problems. Do report a problem even when you're not sure it's a bug; the people who own the code would rather hear about it.

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
- A maintainer has LGTM'd: a `lgtm` comment, an approving review, or the maintainer opening the PR themselves. A PR an agent opened needs a maintainer's LGTM. Agents never post `lgtm` or approve, even when they act under a maintainer's account, so an `lgtm` is always a human's. An LGTM approves the direction, so small follow-up fixes, rebases and merges from `main` keep it. Ask again when the scope or approach changes.
- Required checks pass on the head commit, with nothing pending (`gh pr checks <N> --required`), and review threads are resolved. Check again right before merging; `--admin` skips GitHub's own gates, so this check is the gate.

Then squash-merge, pinned to the head you checked:

```sh
gh pr merge <N> --admin --squash --match-head-commit <full sha>
```
