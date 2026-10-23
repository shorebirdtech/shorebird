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
- In review, every user-visible output change (messages, hints, exit codes,
  JSON shape) is at least should-fix, reported as before/after text. Judge
  whether it's better, not whether it's consistent: the siblings may be the
  drifted ones. In a "no behavior change" PR, any behavior change is
  must-fix: split it out.
- Deduplicate only if it fixes drift, reads easier, or is much shorter.
  Pitch it with the line delta and a before/after call site.
- Only recursively delete a temp dir created in the same function, via
  `deleteTemporarySync()`. A leak beats a wrong delete.
- Tests: call `useTempWorkingDirectory()` first in every test `main` and run
  `dart test -j 4`.
- Never run state-changing commands (`login`, `logout`, `init`, `release`,
  `patch`, `upgrade`, `cache clean`, `apps delete`, ...) against a real
  account or machine, including to verify a change. Use unit tests, or a
  compiled binary pointed at scratch directories with fake credentials.
  Agent briefs for CLI work say so.

## Designing commands

CLIs are mostly used by agents today, so make `shorebird` as normal as
possible:

- Model commands on CLIs agents already know (`gh`, `kubectl`): `gh api`
  style endpoints and flags. Model after, don't port: build what agents
  actually reach for, not every flag of the reference tool.
- Pick one convention, not a mix. For example, pagination is a
  `next_cursor` in the body only, not that plus a `Link` header.
- Name new commands by what an agent guesses first. Ask a model with no
  tools or docs "the CLI is `shorebird`, you want to do X, what command do
  you try first?" and lean toward its answer. One capable model (Sonnet) is
  enough; spend the runs on varied phrasings rather than more models.
- When an agent uses a command wrongly, fix the command, not the docs.
  Accept the input it wrote (flags on either side of a positional, both
  spellings of a name, the obvious synonym for a verb), and prefer a verb
  per question over flags on one verb, so every option shows in one
  listing.
- Correct in-flight: when a run went the wrong way, say what was wanted in
  that run's own output.
- Autofix loudly and durably: print what was missing and what was added,
  and write the fix to the user's checkout so the next run works too.
  Test that the message appears. A silent fix hides the lesson; a check
  that only reports invites a bad fix.
