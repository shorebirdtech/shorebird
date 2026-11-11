<!-- cspell:words oneline -->

# Releasing the Shorebird CLI

Users get a new CLI version through `shorebird upgrade`, which resets their
checkout to the tip of the `stable` branch. A release is a tag, `v<version>`,
on a release branch cut from `main`; `stable` is moved to the tag.

A release runs as `release_cli.yaml` in `shorebirdtech/_build_engine`
(described in its `release_skill/release-workflow.md`). A Flutter release
(`release_flutter.yaml`) releases the CLI the same way, with a new Flutter
pin.

## 1. Pick the commit

- Diff what users have against `main`:
  `git log --oneline --no-merges v<last version>..origin/main`
- Note any change that the gate does not exercise (auth, `--json` output,
  platform specific fixes). Those need a manual check before you approve.
- A Flutter change ships through `release_flutter.yaml`, which releases the
  CLI too.

## 2. Dispatch the release

```sh
gh workflow run release_cli.yaml -R shorebirdtech/_build_engine --ref main -f dry_run=false
```

`cli_version` is optional: by default it is `main`'s version when `main` was
bumped ahead of the last release, else the next patch. `dry_run` (the
default) prints every write and makes none.

The run:

- `branch`: cuts `release/v<version>-rc<n>` from `main` with the
  `chore: prepare for release <version>` commit: a `RELEASE_NOTES.md`
  section drafted from the commits since the last release, and the version
  and pubspec when `main` isn't at the version already.
- `gate`: runs e2e (signing, rollback, boot and the patch matrix across the
  supported Flutter versions), shorebird_e2e Android on an emulator and on
  arm64 and 32-bit phones, macOS, and the iOS check on cloud iPhones, all
  against the branch's head. Every leg must pass.
- `cli_pr`: runs again the iOS cells that didn't pass, then opens the PR
  from the branch into `main` and waits for its required checks.

A failed job says why in the run's summary. Re-run it for a flake. A real
fix lands on `main` first: cancel the run
(`gh run cancel <id> -R shorebirdtech/_build_engine`; a new one waits behind
it) and dispatch again, which cuts the next rc and closes the earlier one's
PR and branch when it promotes. An iOS cell that keeps failing on cloud
iPhones can run on a plugged-in iPhone with the command in the gate job's
summary; then re-run `cli_pr`.

## 3. Review the notes and approve

On the PR, edit `RELEASE_NOTES.md` to user-facing changes only: make each
❓ entry ✨ or 🐛, or delete it, and delete 🔧 entries users wouldn't see.
Edits to `.md` files keep the gate's results; any other change needs a fix
on `main` and a new run, as above.

Check each change from step 1 that the gate does not cover with a checkout
of the PR's head. The gate does not cover signed iOS builds (the iOS runs
use `--no-codesign`, so no `.ipa` export or `shorebird preview`),
interactive `shorebird login`, or `--json` output. On a Mac with an iOS
device, Shorebird staff can run the `release-smoke-test` agent skill in
`shorebirdtech/_shorebird`, which covers all three.

Approve only when a maintainer can watch for problems for the next few
hours, so not late at night or before a weekend, unless the release is
urgent; dispatch early enough that the PR opens while someone can. The
release approval is an approving review of the PR's head by an approver
(today `eseidel`: `approvers` in `_build_engine`'s
`release_flutter/release.yaml`); anyone else's approval satisfies the merge
queue but not the release. `promote` then tags `v<version>` on that head,
moves `stable` to it, and lands the PR on `main` through the merge queue.
It waits 6 hours for the approval. After that, or when it refuses an
approved head (a ❓ left in, a red check on an edited head), approve or fix
and re-run the run's `promote` job. The
tag and `stable` are what users see. If the queue won't take the PR, the
release is out anyway and the run warns: land it by hand.

## 4. Verify

- `shorebird upgrade` on a machine with an older CLI moves it to the new
  version, and `shorebird --version` reports it.

## 5. Announce

`promote` writes a Discord draft into the run's summary. Post it on the
Shorebird Discord after editing it: it is not a changelog. Pick the 2-4
changes users would notice, lead each with a plain-language sentence on its
impact (what was broken, who it hit), and say any action needed (for example
"create a new release"). Only claim an impact stated in the
`RELEASE_NOTES.md` entry or its PR; drop a change whose impact isn't clear.
Everything else is in the linked GitHub release.

```md
@here - <greeting>. Shorebird <version> is out. Run `shorebird upgrade` to pick it up.

## Shorebird <version>

🐦 Flutter <flutter version> / Dart <dart version> support. 🐦

- **<impact, in plain language>.** <who it hits, any action needed>
- **<impact>.** <...>

Full notes: <https://github.com/shorebirdtech/shorebird/releases/tag/v<version>>
```
