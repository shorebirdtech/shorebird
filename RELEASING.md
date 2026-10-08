<!-- cspell:words oneline -->

# Releasing the Shorebird CLI

Users get a new CLI version through `shorebird upgrade`, which resets their
checkout to the tip of the `stable` branch. A release is a commit on `main`
that `stable` is moved to.

## 1. Pick the commit

- Diff what users have against `main`:
  `git log --oneline --no-merges origin/stable..origin/main`
- Note any change that e2e does not exercise (auth, `--json` output, platform
  specific fixes). Those need a manual check in step 2.
- If the release should ship a new Flutter, update
  `bin/internal/flutter.version` in its own commit
  (`chore: bump Flutter to <short sha>`).

## 2. Smoke test

- Run the e2e workflow on `main` from the Actions tab
  (<https://github.com/shorebirdtech/shorebird/actions/workflows/e2e.yaml>),
  or `gh workflow run e2e.yaml --ref main`. Leave `cli_ref` empty: setting it
  skips the patch matrix.
- Every leg must pass. If the most recent nightly failed, find out why before
  releasing.
- Manually check each change from step 1 that e2e does not cover, using a
  local checkout of the commit being released.

## 3. Prepare the release commit

One commit on `main`, titled `chore: prepare for release <version>`:

- `packages/shorebird_cli/lib/src/version.dart`: `packageVersion`
- `packages/shorebird_cli/pubspec.yaml`: `version`
- `RELEASE_NOTES.md`: a new section at the top,
  `## <version> (<Month D, YYYY>)`, with user-facing changes only:
  - 🐦 Flutter / Dart version, with notable Flutter fixes nested under it
  - ✨ new features
  - 🐛 fixes
  - 🔧 other user-visible changes

  `RELEASE_NOTES.md` is spell checked. Add new words to the `cspell:words`
  comment at the top of the file.

## 4. Publish

```sh
VERSION=x.y.z
SHA=$(git rev-parse origin/main)  # the prepare commit
gh release create "v$VERSION" --target "$SHA" --title "v$VERSION" --generate-notes
git push origin "$SHA:stable"
```

- `stable` must fast-forward. It is protected (linear history, no force
  pushes); pushing directly requires admin.
- The tag and the `stable` push are what users see. Do not move `stable`
  until the smoke test passes.

## 5. Verify

- `shorebird upgrade` on a machine with an older CLI moves it to the new
  version, and `shorebird --version` reports it.

## 6. Announce

Post a summary on the Shorebird Discord, built from the `RELEASE_NOTES.md`
section:

```md
@here - <greeting>. Shorebird <version> is out. Run `shorebird upgrade` to pick it up.

## Shorebird <version>

🐦 Flutter <flutter version> / Dart <dart version> support. 🐦

### New
- <one line per feature>

### Fixes
- <one line per fix>

### From Flutter <flutter version>
- <notable Flutter fixes>

Full notes: <https://github.com/shorebirdtech/shorebird/releases/tag/v<version>>
```

Leave out sections with nothing in them.
