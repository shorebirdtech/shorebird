<!-- cspell:words toplevel -->

# 0.2.1

- Static main workflow now derives its YAML map keys from each package's path as `<parent_dir>_<package_name>` instead of relying on the `name:` field. Packages can share a `name:` across different paths without crashing the generator. The `package_name:` input passed to the reusable workflow keeps the actual package name for codecov flag display.
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
