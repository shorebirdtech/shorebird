<!-- cspell:words toplevel -->

# 0.2.0

- `shorebird_ci generate` now bumps action versions to current latest automatically after writing the workflow files. Pass `--no-update-actions` to skip the network call.
- `shorebird_ci affected_packages` prints a friendly error instead of a Dart stack trace when run outside a git repository or against an unreachable base ref.
- `--repo-root` defaults to `git rev-parse --show-toplevel` when not specified, matching git's own behavior. Pass `--repo-root` explicitly to override.
- README: remove stale "not yet on pub.dev" note; document why subpackages are covered both as standalone matrix jobs and inside the root Flutter job.
- Add `executables:` declaration so `dart pub global activate shorebird_ci` creates a `shorebird_ci` shim on `PATH`. Previously users had to invoke via `dart pub global run shorebird_ci:shorebird_ci`. (rolled in from the unreleased 0.1.1)

# 0.1.1

- Add `executables:` declaration so `dart pub global activate shorebird_ci` creates a `shorebird_ci` shim on `PATH`. Previously users had to invoke via `dart pub global run shorebird_ci:shorebird_ci`.

# 0.1.0

- Initial release.
