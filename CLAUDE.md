# CLAUDE.md

When you work around something (a silent command, a surprising default, an unhelpful error, an unrelated failing test, a toolchain mismatch with CI, a command or flag you guessed that didn't exist), fix the tool: open a small PR unprompted and link it in your report; for a bigger fix, describe it and ask first.

## Commands

```bash
dart pub get              # once, at the repo root (one pub workspace)
tool/agent-verify.sh      # format, analyze, test every package as CI does; --force skips the cache
npx cspell <changed files>
```

`agent-verify.sh` caches passes per package. A test reading a file outside its package must list it under `verify_cache: inputs:` in its pubspec. It skips coverage, the version check and `redis_client`'s tests.

## Conventions

- Say "checked-in shorebird.yaml" or "generated (bundled) shorebird.yaml" in code, comments, PRs and issues; customer messages say `shorebird.yaml`.
- Name anything customers read (env vars, flags, errors, doc headings) after the host they see: `SHOREBIRD_DOWNLOAD_URL` for `download.shorebird.dev`.
- CSpell: inline `// cspell:words` for 1-2 files, else the global config. Invalid-input fixtures use a real word wrong in context, such as `web` for a platform.
- Add commits to a PR; don't amend.
- Dart style: `style_guides/dart.md`.

## Landing a PR

All must hold at the head commit:

- A separate agent reviewed the full diff adversarially and posted findings as a PR comment; blockers fixed or answered.
- A maintainer LGTM'd (`lgtm` comment, approving review, or opened it). Agents never post `lgtm` or approve. Rebases and small fixes keep it; scope changes need a new one.
- `gh pr checks <N> --required` all pass, nothing pending; threads resolved. Recheck right before merging.

```sh
gh pr merge <N> --admin --squash --match-head-commit <full sha>
```
