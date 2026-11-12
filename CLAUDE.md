# CLAUDE.md

When you work around something (a silent command, a surprising default, an unhelpful error, an unrelated failing test, a toolchain mismatch with CI, a command or flag you guessed that didn't exist), fix the tool: open a small PR unprompted and link it in your report; for a bigger fix, describe it and ask first.

## Commands

```bash
scripts/bootstrap.sh      # once, resolves the workspace
tool/agent-verify.sh      # format, analyze, test every package as CI does; --force skips the cache
npx cspell <changed files>
```

`agent-verify.sh` caches passes per package. A test reading a file outside its package must list it under `verify_cache: inputs:` in its pubspec. It skips coverage, the version check and `redis_client`'s tests.

It runs a Dart of the version CI runs (current stable, which `setup-dart` installs): what `dart format` does depends on the Dart version and `analysis_options.yaml`, not on where Dart is installed, so a Flutter checkout's Dart of that version counts. A machine with no Dart of that version gets a `3` rather than a pass, with the versions it found. Both scripts above pick it, so run them rather than a bare `dart`. `DART_BIN` names one explicitly and skips the check.

## Conventions

- Two files are named `shorebird.yaml`: the checked-in one, and the one generated into `flutter_assets` with extra keys such as `patch_public_key`. In code touching the bundled one, and in comments, PRs and issues, say "checked-in shorebird.yaml" or "generated (bundled) shorebird.yaml". Customer messages say `shorebird.yaml`.
- Name anything customers read (env vars, flags, errors, doc headings) after what they see, such as the host: `SHOREBIRD_DOWNLOAD_URL` for `download.shorebird.dev`.
- CSpell: inline `// cspell:words` for 1-2 files, else the global config. Invalid-input fixtures use a real word wrong in context, such as `web` for an unsupported platform.
- Keep PRs reviewable. A small PR can carry a little cleanup next to its change; once a PR gets large, split it along its seams: a refactor with no behavior change, general improvements (fixes, cleanups, tests of existing code, simplifications), and each separate behavior change. Improvements land first: we always want them, and may not want the feature. A change keeps its own tests and fixture updates in its PR; a feature that needs an improvement builds on that PR's branch.
- Prefer new commits over amending.
- Dart style: `style_guides/dart.md`.

## Landing a PR

All must hold at the head commit:

- A separate agent reviewed the full diff adversarially and posted findings as a PR comment; blockers fixed or answered before asking for an LGTM.
- A maintainer LGTM'd: a `lgtm` comment, an approving review, or opening it themselves. A PR an agent opened, even under a maintainer's account, needs an explicit LGTM. Agents never post `lgtm` or approve. Small fixes, rebases and merges from `main` keep it; a new scope or approach needs a new one.
- `gh pr checks <N> --required` all pass, nothing pending; threads resolved. Recheck right before merging.

```sh
gh pr merge <N> --admin --squash --match-head-commit <full sha>
```
