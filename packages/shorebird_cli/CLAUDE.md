# shorebird_cli

- Errors must be actionable: name the fix (the exact command with real
  values, or the valid choices such as org ids or patch numbers). Never
  print a path that is deleted before the command exits.
- Differences between platforms or sibling commands are drift; fix them
  toward the better behavior everywhere. "Matches the siblings" alone
  doesn't justify a change.
- A `--json` run writes exactly one envelope to stdout; report errors with
  `reportError`. Breaking exit codes or JSON shape is fine if the CLI gets
  better; say so in the PR.
- Refactors don't change user-visible output. Put such changes in their own
  PR with before/after text.
- Deduplicate only if it fixes drift, reads easier, or is much shorter.
- Only recursively delete a temp dir created in the same function, via
  `deleteTemporarySync()`. A leak beats a wrong delete.
- Tests: call `useTempWorkingDirectory()` first in every test `main`, run
  `dart test -j 4`, and never run state-changing commands (`login`,
  `release`, ...) against a real account.
