# shorebird_cli

- Errors name the fix: the exact command with real values, or the valid choices. Never print a path deleted before exit.
- Platform or sibling-command differences are drift: fix toward the better behavior everywhere. Matching the siblings alone justifies nothing.
- `--json` writes exactly one envelope to stdout; errors go through `reportError`. Breaking exit codes or JSON shape is fine if it improves the CLI; say so in the PR.
- Refactors keep user-visible output (messages, hints, exit codes, JSON). Output changes go in their own PR with before/after text; reviewers judge whether it's better.
- Deduplicate only to fix drift, read easier or cut many lines; pitch it with the line delta.
- Recursively delete only a temp dir created in the same function, with `deleteTemporarySync()`.
- Every test `main` calls `useTempWorkingDirectory()` first.
- Never verify by running commands that change a real account or your install (`login`, `logout`, `init`, `release`, `patch`, `upgrade`, `cache clean`, `apps delete`, ...); unit test instead. `RELEASING.md` steps excepted.

## Designing commands

- Model on `gh`: noun then verb, `shorebird api` for raw endpoints. Build only the flags users reach for.
- Name a command what a tool-less model guesses first for several phrasings of the task.
- Fix predictable mistakes in the command: accept flags on either side of a positional; add synonyms as hidden aliases.
- When a command fixes a file Shorebird owns, print what was missing and what changed, and test the message. Never autofix under `--json` or non-interactively; report the problem and fix.
