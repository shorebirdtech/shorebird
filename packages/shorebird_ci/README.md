# shorebird_ci

CI tooling for Dart and Flutter monorepos. Discovers packages, builds
the dep graph, and generates a GitHub Actions workflow that runs the
right CI on the right packages. `verify` keeps the workflow honest as
the repo evolves.

## Installation

```sh
dart pub global activate shorebird_ci
```

## Quick Start

```sh
shorebird_ci generate --dry-run            # review what it would write
shorebird_ci generate --required           # write + add a single aggregator check
```

Commit the result, push, and in branch protection require the single
check named `required`. That one check passes when every per-package
job either succeeds or was skipped (because nothing in its paths
changed) and fails on any real failure. No need to update branch
protection when packages come or go.

## Commands

You run these locally:

| Command | Purpose |
|---|---|
| `generate` | Write `.github/workflows/shorebird_ci.yaml` (plus reusable workflows in `--style static`) |
| `verify` | Check that every package has CI coverage, and that any `required` aggregator stays in sync with the rest of the workflow |
| `update_actions` | Rewrite `uses:` pins in workflow files to current latest majors. `generate` already calls this after writing; run it standalone to bump pins in hand-maintained workflows |

CI runs these inside the generated workflow. You don't usually invoke
them by hand:

| Command | Purpose |
|---|---|
| `affected_packages` | Emit a JSON matrix of packages touched by the PR, including transitive dependents via the Dart dep graph |
| `flutter_version` | Resolve an exact Flutter version from a pubspec's `environment.flutter` constraint, which `subosito/flutter-action` requires |

## How the generated workflow works

Two stages. A `setup` job checks out the repo with full history (needed
for the diff against `origin/main`), installs Dart, `pub global
activate`s `shorebird_ci`, runs `verify` as a sanity check, then runs
`affected_packages` to compute which packages the PR touches. A matrix
job fans out over only those packages, running per entry: checkout,
SDK setup, `pub get` (plus any nested subpackages), format, analyze,
bloc lint (if `bloc_lint` is a dependency), tests (with coverage if
Codecov is configured), integration tests (if Flutter and an
`integration_test/` directory exists), Codecov upload.

A `cspell` job is added if a cspell config file is present at the repo
root.

Auto-detected: Dart vs. Flutter, Dart workspaces, Codecov, cspell,
nested subpackages, `bloc_lint`, integration tests, pinned Flutter
versions. Adding or removing packages requires no workflow changes;
the setup job discovers them at runtime.

`generate` also writes `.github/dependabot.yml` (if missing) so action
versions stay current over time.

### Manual runs and the empty-diff case

The workflow includes a `workflow_dispatch:` trigger so you can launch
a run from the **Run workflow** button in the Actions tab. Manual runs
bypass the affected-packages diff and execute CI against every
package, which is what you want when:

- You just pushed an initial commit to `main` and the diff vs.
  `origin/main` is empty.
- You want to force a full re-check after editing CI configuration.
- Something looks off and you want a baseline green run.

For normal `push: main` events where the diff is empty, setup emits a
GitHub notice pointing at the manual button so a green-but-skipped run
isn't confused for a full pass.

### Subpackage double-coverage

Subpackages of a Flutter root get CI'd twice: once in their own matrix
job, once inside the root's job. Intentional. The root needs them for
`pub get`, and the standalone job gives focused per-package pass/fail.
Cost is a duplicate analyze/test on affected PRs.

## Options

### `--required`

Adds an aggregator job named `required` that depends on every other
job in the workflow and uses `if: ${{ always() }}` so it runs even
when sub-jobs are skipped. The aggregator fails when any dependency
reports `failure` or `cancelled` and passes when dependencies succeed
or were skipped.

Use it as the single required check in branch protection. Per-package
jobs only run on touched paths, so most PRs leave most jobs skipped.
Treating skipped as pass is what makes a single static check viable
without re-listing every job in branch protection every time the
package set changes.

`verify` enforces consistency: if a workflow file has a top-level
`required` job, every other top-level job in that file must appear in
its `needs:`, and every entry in `needs:` must match a real job. Drift
in either direction silently breaks the gate, so `verify` fails loudly
when it finds it.

In `--style static`, the `required` job key is reserved when this flag
is set: generation fails if any package's slug resolves to `required`
(rename the package). Dynamic mode keys jobs by `setup`, `dart_ci`,
`flutter_ci`, and `cspell`, so the collision can't happen there.

### `--codecov-token-secret <NAME>`

Pass the name of the GitHub Actions secret holding your Codecov upload
token. The codecov-action step gets `token: ${{ secrets.<NAME> }}` in
both `--style static` and `--style dynamic` (the default). In static,
`secrets: inherit` is also emitted on each reusable workflow call so
the secret is reachable from inside the reusable workflow.

```sh
shorebird_ci generate --codecov-token-secret CODECOV_TOKEN
```

When unset, no token plumbing is emitted. Whether you need one is a
Codecov question; refer to their docs for whether your repo requires
it.

### `--no-update-actions`

By default, `generate` queries GitHub for current latest majors and
bumps action pins after writing the workflow. `--no-update-actions`
skips the network call and leaves the static pins in the template
as-is. Use it in offline environments. Once you push, Dependabot picks
up bumps on its weekly schedule.

### `--style static`

Emits a full main workflow plus one or two reusable workflows (one for
Dart, one for Flutter, depending on what the repo contains). The main
workflow uses `dorny/paths-filter` to pick which packages are affected
on each push or PR, and a thin per-package job calls into the matching
reusable workflow.

The choice between styles is a maintenance-vs-CI-minutes trade-off:

- **Dynamic (default).** Less to maintain, more CI minutes. The dep
  graph is computed at runtime, so adding a package, renaming one, or
  changing a `path:` dependency just works. Pays ~15-30s of setup per
  PR for checkout, Dart SDK, `pub global activate`, and
  `affected_packages`.
- **Static.** More to maintain, fewer CI minutes. The dep graph is
  baked into YAML at generate time, so any change to packages or
  `path:` dependencies needs a re-run of `generate` or a hand-patch
  of the filters. `verify` catches drift the next time it runs in CI.
  In exchange the workflow can skip entirely at the trigger level
  when no paths-filter group matches.

### `verify --ignore`

For packages that intentionally have no CI (for example, `e2e` test
packages):

```sh
shorebird_ci verify --ignore e2e,other_package
```

## Customization

The generated file is a normal YAML file, not a locked artifact. Edit
freely. The tool's ongoing role is `verify`, not regeneration. Common
edits the tool doesn't make for you:

- **Branch name.** The workflow triggers on `pull_request` and `push`
  against `main` only. Repos using `master`, `trunk`, etc. need to
  swap the branch in both triggers.
- **Runner.** Every job is `ubuntu-latest`. Self-hosted, ARM, or macOS
  runners need a manual change to `runs-on:`.
- **Non-Codecov secrets.** Only the Codecov token has first-class flag
  support. Anything else (private pub registries, integration-test
  credentials) needs to be plumbed through by hand.

## For AI agents

This tool handles the deterministic parts (package discovery, dep
graph, workflow generation). You handle the judgment calls: merging
with existing workflows, naming, resolving conflicts.

If the repo already has `.github/workflows/*.yaml`, read them before
generating. Look for existing Dart CI that would be superseded,
duplicate job names, overlapping path filters. Ask the user whether to
replace existing CI or run alongside.

When `verify` reports missing packages (only possible in repos using
`--style static`), it outputs the exact dorny entry with transitive
deps computed. You decide which workflow file and which filter group
to add it to; read the existing structure and make the call.

