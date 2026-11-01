# CLAUDE.md

When you work around something (a silent command, a surprising default, an unhelpful error, an unrelated failing test, a toolchain mismatch with CI, a command or flag you guessed that didn't exist), fix the tool: open a small PR unprompted and link it in your report; for a bigger fix, describe it and ask first.

## Commands

```bash
dart pub get              # once, at the repo root
tool/agent-verify.sh      # format, analyze, test every package as CI does; --force skips the cache
npx cspell <changed files>
```

`agent-verify.sh` caches passes per package. A test reading a file outside its package must list it under `verify_cache: inputs:` in its pubspec. It skips coverage, the version check and `redis_client`'s tests.

It runs the standalone Dart SDK, which is the one CI installs. A Dart bundled with a Flutter checkout is a different SDK that formats this tree differently, so it is skipped even where `PATH` answers with it first, and a machine holding only that one gets a `3` rather than a pass. Run `dart` through the wrapper rather than by hand, or the verdict can come from the other SDK.

## Conventions

- Two files are named `shorebird.yaml`: the checked-in one, and the one generated into `flutter_assets` with extra keys such as `patch_public_key`. In code touching the bundled one, and in comments, PRs and issues, say "checked-in shorebird.yaml" or "generated (bundled) shorebird.yaml". Customer messages say `shorebird.yaml`.
- Name anything customers read (env vars, flags, errors, doc headings) after what they see, such as the host: `SHOREBIRD_DOWNLOAD_URL` for `download.shorebird.dev`.
- CSpell: inline `// cspell:words` for 1-2 files, else the global config. Invalid-input fixtures use a real word wrong in context, such as `web` for an unsupported platform.
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
