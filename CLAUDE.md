# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Notice when you're working around something, and fix it

We want our processes, both the ones customers use and the ones we use, to be as normal and as agent-friendly as possible. So notice when you're working around something instead of quietly getting past it. Examples: a `shorebird` command that waits with no output, a command or flag whose default surprised you, an error that doesn't say what to do, a test that fails for reasons unrelated to your change, a local Dart or Flutter toolchain that doesn't match CI.

Your own wrong guesses count too. If you reached for a command, flag, path, or convention that didn't exist or didn't do what you expected, that's a place the tool didn't meet you where you were, and usually the tool should change rather than the docs.

For each one:

- If the fix is small, make the PR without waiting to be asked, and link it in your final report.
- If it isn't, describe it in your final report (what you did, what you expected, what happened, and the fix you'd propose) and ask before starting it.

## Build Commands

```bash
# Install dependencies (once, at the repo root: packages share one pub
# workspace, and without it analyze reports thousands of bogus issues)
dart pub get

# Run all tests (must run from packages/ directory to avoid cache conflicts)
cd packages && very_good test -r

# Before pushing, from each package you changed, run what CI checks there
dart format --set-exit-if-changed .
dart analyze --fatal-warnings .
dart test -j 4

# and spell check the files you changed (CI checks the whole repo)
npx cspell <changed files>
```

## Architecture

Dart monorepo. Main package is `shorebird_cli`.

**Platform-specific operations** use the Releaser/Patcher pattern:
- `commands/release/` - `Releaser` base class with platform implementations
- `commands/patch/` - `Patcher` base class with platform implementations

**Dependency injection** uses `scoped_deps` with zone-based refs (see any `*Ref` variable).

**Two files are named `shorebird.yaml`**: the checked-in project config at the app's root, and the generated one the Flutter fork bundles into `flutter_assets`, which has keys the checked-in one doesn't (such as `patch_public_key`). In code that touches the bundled file, and in comments, PRs and issues about either one, say "checked-in shorebird.yaml" or "generated (bundled) shorebird.yaml", so a change aimed at one doesn't hit the other. Messages customers read keep saying `shorebird.yaml`: to them it is the checked-in file.

## Code Style

- PR titles must follow semantic commit format (enforced in CI)
- CSpell: use inline `// cspell:words` for 1-2 files; add to global config for more. For an invalid-input test fixture, prefer a real word that's wrong in context (such as `web` for an unsupported platform) over a misspelling.
- Prefer new commits over amending in PRs - history gets squashed anyway
- Dart style rules beyond the lints are in `style_guides/dart.md`
- Name anything a customer reads (env vars, flags, doc headings, error messages) after what they see, such as the host, not our internal service names: customers configure mirrors and allowlists by hostname. The setting for `download.shorebird.dev` is `SHOREBIRD_DOWNLOAD_URL`, named for the host. Internal names are fine in code internals.

## Landing a PR

A PR can land when all of these hold at its current head commit:

- The review bot used on Shorebird's private repos doesn't run here, so an agent-authored PR gets that same review run locally: a separate agent, not the one that wrote the change, reviews the full diff adversarially, looking for reasons it should not land, and its findings are posted as their own PR comment. Blockers are fixed or answered before asking for an LGTM.
- A maintainer has LGTM'd: a `lgtm` comment, an approving review, or the maintainer opening the PR themselves. A PR an agent opened needs a maintainer's LGTM. Agents never post `lgtm` or approve, even when they act under a maintainer's account, so an `lgtm` is always a human's. An LGTM approves the direction, so small follow-up fixes, rebases and merges from `main` keep it. Ask again when the scope or approach changes.
- Required checks pass on the head commit, with nothing pending (`gh pr checks <N> --required`), and review threads are resolved. Check again right before merging; `--admin` skips GitHub's own gates, so this check is the gate.

Then squash-merge, pinned to the head you checked:

```sh
gh pr merge <N> --admin --squash --match-head-commit <full sha>
```
