<!-- cspell:words toplevel -->

# 0.3.1

- `generate` reads repository-wide `shorebird_ci:` configuration from the repository root's `pubspec.yaml` (`required`, `fatal_infos`, `codecov_token_secret`), each mirroring the flag of the same name, with the flag winning where both are set. (#4446)
- `verify` rebuilds every workflow carrying the `--style static` marker from the repository and fails when the checked-in copy differs, naming the line and the file, including where a dynamic workflow covers the repository's packages alongside it. Only the `uses:` refs are exempt, since `generate`'s own update step and then Dependabot move every action pin past the ones built into shorebird_ci. The coverage checks only ask whether each filter covers its package's dep graph, so a hand-added input, a job generation no longer writes, or a declaration nobody made all passed them and then vanished at the next `generate` run. (#4446)
- The filter `verify` suggests for a package missing from CI coverage now names the orchestrator and the reusable workflow it calls, matching what `generate --style static` writes. Pasting the old suggestion gave back a filter the next `generate` run rewrote. (#4446)
- `generate` (`--style static` and `--filters-only`) now includes the orchestrator workflow's own path in every package's `dorny/paths-filter` block, so a commit editing only the orchestrator still triggers each package's job. (#4444)
- Generated `Run Tests` steps (static reusable workflows and dynamic jobs with coverage) now wrap `dart test` and `flutter test` in a `retry_test` helper that retries a batch once when a suite fails to load because its VM service connection closed before the full header was received. (#4420)
- Bump `test` dev dependency constraint to `^1.33.0` (#4360), declare `shorebird_ci` runners and coverage floor in `pubspec.yaml` (#4439), and align repository CI workflows onto `_shorebird_ci_dart.yaml` (#4331) with fatal lint infos (#4430).

# 0.3.0

- `DependencyResolver` now parses `.gitmodules` and collapses any dependency inside a submodule to the submodule's mount point, since `git diff` reports submodule updates at the mount point rather than paths beneath it.
- `DependencyResolver` now reads extra input globs from `shorebird_ci: inputs:` and `verify_cache: inputs:` in `pubspec.yaml`, and static package filters include the reusable workflow file (`.github/workflows/_shorebird_ci_{dart,flutter}.yaml`).
- New `--filters-only` flag on `generate` updates `dorny/paths-filter` `filters: |` blocks in place without overwriting surrounding jobs, services, or matrix strategies.
- `generate --style static` reads declarative per-package `shorebird_ci:` configuration from `pubspec.yaml` (`min_coverage`, `runners`, `needs_redis`, `report_on`, `coverage_excludes`, `total_shards`).
- Static reusable workflows (`_shorebird_ci_dart.yaml` and `_shorebird_ci_flutter.yaml`) now run an OS matrix (`ubuntu-latest` on pull requests, `inputs.runners` on `main` and `merge_group`), batch test files 50 at a time under `set -f` with optional `total_shards`/`shard_index` partitioning, use an absolute `COVERAGE_DIR` so tests that change `Directory.current` do not lose coverage, auto-detect `routes/` and `routes/.well-known`, scope `.dart_tool/package_config_scoped.json` to the active package before `coverage:format_coverage --check-ignore`, and gate `min_coverage` with `shorebird_ci check_coverage`.
- New `--fatal-infos` flag on `generate` passes `--fatal-infos` to `dart analyze` and `flutter analyze`.
- Generated workflows now emit `base: ${{ github.event.merge_group.base_ref || '' }}` on `dorny/paths-filter` and emit `submodules: recursive` on `actions/checkout` only when `.gitmodules` is present.

# 0.2.8

- Generated workflows now declare least-privilege `permissions:`, so regenerating no longer drops them from a repo that added them by hand, and a repo whose default `GITHUB_TOKEN` can write doesn't hand that to `pub get` and test steps. The dynamic workflow and the static main and reusable workflows set `contents: read` at the top level. The static `changes` job adds `pull-requests: read`, which `dorny/paths-filter` needs to list a pull request's files. A step you add to a generated workflow that needs more must be granted it on its job and, in a reusable workflow, on the job calling it too.

# 0.2.7

- Generated workflows no longer use `felangel/setup-bloc-tools` or `streetsidesoftware/cspell-action`. Bloc lint installs `bloc_tools` 0.1.0-dev.25 with `dart pub global activate`, and the `cspell` job runs `npx cspell@10.4.0`, each at the version that generated the workflow (their own dependencies still resolve fresh on each run). The `cspell` job runs with a read-only token that checkout doesn't persist. Flutter jobs with bloc lint now run `dart format` on Flutter's own Dart: `setup-bloc-tools` also ran `dart-lang/setup-dart@v1` on a tag inside it, which a SHA pin on the outer action doesn't cover.

# 0.2.6

- New `check_coverage` command: fails when line coverage in lcov tracefiles is below `--min` (default 100), leaving out sources matching `--exclude` globs. Several tracefiles are merged by summing hits per line, as test shards need. It replaces `VeryGoodOpenSource/very_good_coverage`, whose repository is archived, with the same rule: lines hit over lines found, and an empty or missing tracefile fails.
- `generate` pins every action to a commit SHA, with its release tag in a trailing comment (`actions/checkout@<sha> # v7.0.1`), the form GitHub's hardening guide recommends and Dependabot keeps updating. Before, generated workflows used major tags (`@v6`), which whoever controls the action's repo can move to new code that then runs with the job's token and secrets. `--no-update-actions` writes the pins built into this version of shorebird_ci; otherwise `generate` pins each action's latest release.
- `update_actions` pins `owner/repo@vN` refs to the action's latest release by SHA, and moves `owner/repo@<sha> # vN.N.N` pins to a newer release when there is one. It doesn't follow a tag that was moved under the same version, never moves a pin to an older release, and leaves SHA pins without a version comment alone. Breaking for library users: `LatestMajorResolver` is now `LatestReleaseResolver`, returning an `ActionRelease` (tag and SHA), and the `resolveLatestMajor:` parameters are `resolveLatestRelease:`.

- `verify` fails when the workflow pins a shorebird_ci other than the one running, naming both and the `activate` line that would match it. Before, `verify` off `PATH` was whatever had been globally activated, while CI activated the pinned version, so a local pass was not a CI pass: an older `verify` skipped the static-filter check 0.2.5 added and passed on a repo CI then failed. A workflow naming no exact version, a constraint among them, is reported on stdout rather than failed, since what CI resolves it to is not knowable locally.
- `generate` pins `dart pub global activate shorebird_ci` to the version that generated the workflow. Before, generated workflows activated whatever shorebird_ci was newest, so each release changed every user's CI the moment it was published, and a new `verify` check could fail a merge queue that hadn't changed. To move to a new shorebird_ci, run `generate` again (or bump the version in the workflow).

- `generate` adds a `concurrency` block to the main workflow, so a new push to a pull request cancels that PR's run still going on the older head. The group is the PR number, with `github.run_id` as the fallback, so push-to-main and merge-queue runs each get their own group and are never cancelled or queued. The `required` aggregator now runs on `!cancelled()` instead of `always()`, so a cancelled superseded run shows as cancelled rather than reporting `required` red on the old commit.

# 0.2.5

- The dependency graph behind `generate`'s static filters and `verify`'s suggestions now follows Dart workspace members referenced by name alone. In a workspace, `foo: ^1.0.0` resolves to the member named `foo`, but only `path:` dependencies were followed, so a package's filter left out such a member and a change to it skipped the package's job.
- Workspace members now depend on their workspace root's `pubspec.yaml` and `pubspec.lock`. A member has no lockfile of its own, so a dependency bump changes only the root's lockfile, and that ran no package jobs. `generate` adds both files to each member's static filter, `verify` expects them there, and `affected_packages` counts a change to either as affecting every member.
- `verify` now checks every static filter named for a package against that package's dependencies, in each workflow on its own, and fails listing the `<dir>/**` lines to add. Before, it only checked that the filter existed, so the `Run shorebird_ci verify to check for dep graph drift` line in generated workflows promised a check that never ran.
- `generate` emits bloc lint only for repos that use it. The `has_bloc_lint` input, the `felangel/setup-bloc-tools` step and the `bloc lint` step now appear only in the workflows (dynamic job or static reusable) whose SDK has a package with a `bloc_lint` dev dependency, and the static main workflow passes `has_bloc_lint: true` only to those packages. Repos without bloc no longer depend on a third-party action they never run.
- `verify` fails on a dynamic workflow that never runs `bloc lint` while some package has a `bloc_lint` dev dependency, so a package that adopts bloc_lint after `generate` ran is caught in the `setup` job rather than silently skipping lint.
- Generated workflows now trigger on `merge_group`, in both `--style static` and `--style dynamic`. Without it, a repo that turns on GitHub's merge queue produces no check runs on the queue's temp branch, the `required` context never reports, and the queue ejects every PR at the timeout.
- Static action pin bumped to `dorny/paths-filter@v4`. v3 has no `merge_group` case and falls back to diffing the default branch by merge-base rather than the queue's base commit. Merge-queue support landed in v4.0.1. Only reachable via `--no-update-actions`, since `generate` resolves pins at write time by default.

# 0.2.4

- `verify` now enforces the `--required` aggregator's `needs:` list. Name-based detection: if a workflow has a top-level job named `required`, every other top-level job must appear in its `needs:`, and every entry in `needs:` must match a real top-level job in the same file. A `required:` key w/ no map body is also reported as malformed. Closes three silent-failure modes: a hand-edited workflow could leave a job out of `required.needs` and have its status silently ignored by the merge gate, a typo'd `needs:` entry could go unnoticed until GHA rejected it at runtime, or a bodiless `required:` could pass verify while doing nothing at runtime.
- `generate --required` reserves the `required` job name and refuses to generate when a package slug would collide. Prevents a duplicate YAML key from silently overwriting the aggregator job. Only fires for `--style static` (dynamic mode keys jobs by `setup`/`dart_ci`/`flutter_ci`/`cspell`, so a package named `required` can't collide there). Skip the flag and any package slug is fine.
- Bad CLI args now print a usage message and exit 64 instead of dumping a Dart stack trace. Same as the convention used by other args-based tools.
- `verify` command description and `--required` flag help text updated to cover the new aggregator-consistency checks and the reserved-name contract. `--required` help also rewraps cleanly at the col-30 boundary.

# 0.2.3

- New `--required` flag on `generate`. When set, the generated workflow gets an aggregator `required` job that depends on every other job and uses `if: ${{ always() }}` so it runs even when sub-jobs are skipped. The job fails only if any dependency reports `failure` or `cancelled`, so it's safe to use as the single required check in branch protection: per-package jobs that get skipped because no paths-filter output matched are treated as a pass. Wired into both `--style static` and `--style dynamic`. Skipped by default, so existing generated workflows are unaffected.

# 0.2.2

- Generated Dart workflows now emit `dart analyze --fatal-warnings .` explicitly. The SDK already defaults `--fatal-warnings` to on, so this is behavior-preserving today, but the explicit form documents intent and survives any future flip in the SDK default. Flutter workflows are unchanged: `flutter analyze` defaults `--fatal-warnings` to on with no CLI flag.
- New `--codecov-token-secret <NAME>` option on `generate`. When set, the static orchestrator emits `secrets: inherit` on each reusable workflow call, and the codecov-action step in the reusable workflows receives `token: ${{ secrets.<NAME> }}`. The dynamic style threads the same `token:` into its single codecov-action step. When unset (the default), no token plumbing is emitted, matching prior behavior. Private repos that need a token to upload coverage should pass `--codecov-token-secret CODECOV_TOKEN` (or the secret name of their choice).

# 0.2.1

- Static main workflow YAML map keys default to each package's `name:` and fall back to `<parent_dir>_<package_name>` only when two or more packages share a name. Avoids prefixing in the common case while still handling duplicate-`name:` repos. The `package_name:` input passed to the reusable workflow keeps the actual package name for codecov flag display.
- Static reusable workflows now gate the test and codecov-upload steps on a new `has_unit_tests` input. Packages without a `test/` directory no longer attempt to run `dart test` / `flutter test` or upload coverage. The input defaults to `true` for back-compat with workflows that don't pass it.

# 0.2.0

- Generated dynamic workflow now pins `fetch-depth: 0` on the setup-job checkout. Without it, `affected_packages` fails on every PR because the default shallow checkout doesn't include `origin/main`. The static main workflow gets the same fix so dorny/paths-filter can diff on push events.
- Generated workflow now includes a `workflow_dispatch:` trigger and bypasses the affected-packages diff when triggered manually, so first-push (no diff base) and "force a full re-check" scenarios actually run CI against all packages instead of producing a green-but-empty run.
- Generated workflow emits a GitHub notice when the diff yields no affected packages, pointing users at the manual **Run workflow** button so a skipped matrix isn't mistaken for a full pass.
- Bumped static action pins to `actions/checkout@v6` so `--no-update-actions` doesn't ship a Node.js 20 deprecation warning.
- `shorebird_ci generate` now bumps action versions to current latest automatically after writing the workflow files. Pass `--no-update-actions` to skip the network call.
- `shorebird_ci affected_packages` prints a friendly error instead of a Dart stack trace when run outside a git repository or against an unreachable base ref.
- `--repo-root` defaults to `git rev-parse --show-toplevel` when not specified, matching git's own behavior. Pass `--repo-root` explicitly to override.
- README: remove stale "not yet on pub.dev" note; document why subpackages are covered both as standalone matrix jobs and inside the root Flutter job.
- Add `executables:` declaration so `dart pub global activate shorebird_ci` creates a `shorebird_ci` shim on `PATH`. Previously users had to invoke via `dart pub global run shorebird_ci:shorebird_ci`. (rolled in from the unreleased 0.1.1)

# 0.1.1

- Add `executables:` declaration so `dart pub global activate shorebird_ci` creates a `shorebird_ci` shim on `PATH`. Previously users had to invoke via `dart pub global run shorebird_ci:shorebird_ci`.

# 0.1.0

- Initial release.
