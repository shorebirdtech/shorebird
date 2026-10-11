# shorebird_cli

Guidance for changing the CLI. The root `CLAUDE.md` covers build commands
and architecture.

## What users see

- **Every error is actionable.** Say what went wrong and what to do next:
  the exact command to run (with real values filled in, e.g.
  `shorebird release ios --flutter-version=3.27.4`), the valid choices
  (the user's organization ids, the release's patch numbers, the project's
  flavors), or the flag that fixes it. A message that only says something
  failed is unfinished.
- **Don't point users at things that won't exist.** Never print a path to a
  temp file or directory that is deleted before the command exits.
- **Every platform behaves the same.** When two Releasers, Patchers or
  commands handle the same situation differently, assume drift, not design,
  and fix it toward the better behavior for all of them.
- **`--json`:** every run with `--json` writes exactly one envelope to
  stdout, and human-readable output goes to stderr. Report failures through
  `reportError` so the human and JSON paths share one message and hint.
  Changing exit codes or JSON shape is fine when it makes the CLI better;
  call it out in the PR description.

## Changing code

- **Cleanups don't change behavior.** If a refactor would change anything a
  user sees (a message, hint, exit code or JSON field), put that change in
  its own PR and show the before and after text in its description.
- **"Matches the sibling commands" is not a reason on its own.** The
  siblings may be the ones that drifted. Pick the better message and use it
  everywhere.
- **Consolidate duplication when it fixes drift, reads easier, or is
  significantly shorter.** Don't centralize values that never drift if it
  makes call sites harder to read.
- **Only delete what you just created.** Delete a temp directory in the same
  function that created it, with `deleteTemporarySync()`. Never recursively
  delete the `.parent` of a path returned from elsewhere, or a path built
  from arguments or project layout. Leaking a temp file is far better than
  deleting the wrong thing. (`Isolate.run` bodies have no `logger`, so
  `deleteTemporarySync()` can't be used there; use a plain `deleteSync` in a
  try/catch.)

## Tests

- Every `*_test.dart` calls `useTempWorkingDirectory()` as the first
  statement of `main`; `test/temp_working_directory_test.dart` enforces it.
  Relative and empty mocked paths (`File('')`, `path/to/x`) then resolve into
  a per-file temp directory instead of the package.
- Run `dart test -j 4`. Full concurrency can make test files fail to load on
  a busy machine.
- Verify changes with tests, not by running the real CLI's state-changing
  commands (`login`, `logout`, `init`, `release`, `patch`, `upgrade`,
  `apps delete`, ...) against your own account.
