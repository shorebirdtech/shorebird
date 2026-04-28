# shorebird_ci

CI tooling for Dart and Flutter monorepos. Scans your repo, generates a
GitHub Actions workflow, and verifies that every package has coverage.
Designed to be used by both humans and AI agents.

## Install

Once published to pub.dev:

```sh
dart pub global activate shorebird_ci
```

From a local checkout (current state — not yet on pub.dev):

```sh
dart pub global activate --source path packages/shorebird_ci
```

## Commands

| Command | Used by | Purpose |
|---|---|---|
| `generate` | human / Claude at setup | Write `.github/workflows/shorebird_ci.yaml` |
| `verify` | human / Claude for health checks | Fail if any package is missing CI coverage |
| `affected_packages` | CI runtime (dynamic workflows) | Emit JSON `[{name, path, ...}]` for affected packages |
| `flutter_version` | CI runtime (Flutter packages) | Resolve Flutter version from pubspec (see note below) |
| `update_actions` | human / Claude for maintenance | Bump `uses:` versions in workflow files to latest major |

## Using it

```sh
shorebird_ci generate --repo-root . --dry-run   # review
shorebird_ci generate --repo-root .             # write
```

The tool auto-detects Dart vs. Flutter, Dart workspaces, codecov,
cspell, nested subpackages, bloc_lint, integration tests, and pinned
Flutter versions. The generated workflow includes `shorebird_ci verify`
in its setup job, so CI coverage is checked on every PR.

`generate` also writes `.github/dependabot.yml` (if missing) so action
versions stay current over time.

## How the generated workflow works

Two-stage structure. A `setup` job checks out the code, runs
`shorebird_ci verify` as a sanity check, then runs
`shorebird_ci affected_packages` to compute which packages the PR
touches (including transitive dependents via the Dart dep graph). A
matrix job fans out over only the affected packages, running per
entry: checkout, SDK setup, pub get (plus nested subpackages), format,
analyze, bloc lint (if bloc_lint is a dep), tests (with coverage if
codecov is configured), integration tests (if Flutter + `integration_test/`
exists), codecov upload.

Plus a CSpell job if a cspell config file exists.

Adding or removing packages requires no workflow changes — the setup
job discovers them at runtime.

### `--style static` (advanced)

`generate --style static` emits a pre-computed dorny `filters:` block,
not a full workflow. You paste it into your own workflow, wire up the
dorny step and per-package jobs yourself, and run `verify` to catch
path drift. This is for people who already have a dorny-based pipeline
and want help keeping the filter paths in sync with the Dart dep
graph — not a drop-in alternative to the default.

The dynamic default pays a small setup cost per PR — roughly 15–30
seconds to check out, install the Dart SDK, `pub global activate`
shorebird_ci, and run `affected_packages`. That cost can probably be
cut a lot in the future (prebuilt snapshot, a composite action), but
it's what you pay today. For most repos it's noise. If you have a
high-volume monorepo where most PRs don't touch Dart, static lets the
workflow skip entirely at the trigger level.

## For AI agents

This tool handles the **deterministic parts** (package discovery, dep
graph, workflow generation). You handle the **judgment calls** —
merging with existing workflows, naming, resolving conflicts.

If the repo already has `.github/workflows/*.yaml`, read them before
generating. Look for existing Dart CI that would be superseded,
duplicate job names, overlapping path filters. Ask the user whether
to replace existing CI or run alongside.

**Watch for:** custom runner requirements (self-hosted, ARM, etc.).
Generated workflow defaults to `ubuntu-latest`.

**When `verify` reports missing packages** (only possible in repos
using static dorny filters): the tool outputs the exact dorny entry
with transitive deps computed. You decide which workflow file and
which filter group to add it to — read the existing structure and
make the call.

**`--ignore`:** for packages that intentionally have no CI (e.g.,
`e2e` test packages): `shorebird_ci verify --ignore e2e`.

**Generated file is safe to edit.** It's a normal YAML file, not a
locked artifact. The tool's ongoing role is `verify`, not
regeneration.

## A note on `flutter_version`

This command exists because `subosito/flutter-action` accepts only
exact version strings — it can't resolve constraints like
`>=3.19.0 <4.0.0` from `environment.flutter`. This arguably belongs
upstream. If `flutter-action` (or the Flutter SDK) ships equivalent
resolution, this command should be deprecated.
