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
- Refactors don't change user-visible output (messages, hints, exit codes,
  JSON shape). Put such changes in their own PR with before/after text. In
  review, ask for before/after text for every user-visible output change,
  and judge whether it's better, not whether it matches the siblings: they
  may be the drifted ones.
- Deduplicate only if it fixes drift, reads easier, or is much shorter.
  Pitch it with the line delta and a before/after call site.
- Only recursively delete a temp dir created in the same function, via
  `deleteTemporarySync()`. A leak beats a wrong delete.
- Tests: call `useTempWorkingDirectory()` first in every test `main`.
- Don't verify a change by running commands that change a real Shorebird
  account or your own install (`login`, `logout`, `init`, `release`,
  `patch`, `upgrade`, `cache clean`, `apps delete`, ...); cover it with unit
  tests. The maintainer steps in `RELEASING.md` are the exception.

## Designing commands

Agents are a primary user of CLIs today, so make `shorebird` behave like
the CLIs they already know:

- Model commands on `gh`: noun then verb (`shorebird apps list`), and
  `gh api` style endpoints and flags for raw API access. Model after, don't
  port: build what users actually reach for, not every flag of `gh`.
- Name new commands by what an agent guesses first. Ask a model with no
  tools or docs "the CLI is `shorebird`, you want to do X, what command do
  you try first?" with several phrasings of X, and lean toward the answer.
- When users get a command wrong in a predictable way, fix the command,
  not the docs: accept flags on either side of a positional, and add the
  obvious synonym or other spelling as a hidden alias of the one canonical
  command. When a run is accepted through an alias, print the canonical
  command once.
- Autofix loudly: when a command fixes a file Shorebird owns (such as the
  checked-in shorebird.yaml) so the next run works too, print what was
  missing and what it changed, and test that the message appears. Never
  autofix under `--json` or in a non-interactive run; report what's wrong
  and the fix instead.
