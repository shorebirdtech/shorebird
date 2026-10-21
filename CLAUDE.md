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
# Resolve the pub workspace first. Analysis fails without it: the workspace
# packages do not see each other and shorebird_cli alone reports ~240
# unresolved-import errors.
dart pub get

# Run all tests (must run from packages/ directory to avoid cache conflicts)
cd packages && very_good test -r

# Run tests for a single package (can use -r failures-only to reduce output)
dart test packages/shorebird_cli
```

**Analyze inside the package, never from the repo root.** `dart analyze` at the
root sweeps the vendored Flutter under `third_party/` and the packages outside
the workspace, and reports hundreds of errors on untouched `main`:

```bash
cd packages/shorebird_cli && dart analyze .
```

Note `dart analyze` exits 3 when it finds info-level issues, so a non-zero exit
is not by itself a failure. CI uses `--fatal-warnings`.

## Testing a CLI change

The gate for a change under `packages/shorebird_cli`:

```bash
dart pub get
cd packages/shorebird_cli && dart analyze . && dart test -r failures-only
```

Beyond that, three things this repo has shipped bugs in:

- **A control wired to nothing.** Any new flag or option needs a test that
  exercises it, not only one asserting it parses.
- **Help text that names a flag the command does not have.**
  `test/src/help_examples_test.dart` parses every `shorebird ...` line in every
  command's description, so a renamed flag fails there. **Validate an example
  by parsing it, never by running it:** `apps delete` and `patches promote`
  both appear in help and both mutate real state.
- **Output written while a progress is live.** `mason_logger`'s `Progress`
  repaints its line every 80ms, so a `logger.info` during one scribbles over
  it. Close the progress first, then write, then open a new one if the command
  is still working.

Do not hard-wrap a `description` or a `help` string. Nothing in the CLI wraps
its own help, the terminal does it, and a hard-wrapped string renders ragged at
every other width. `args` lists a subcommand by `description.split('\n').first`,
so a multi-line description keeps its summary on the first line and everything
else below it.

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
