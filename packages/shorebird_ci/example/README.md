# Example

`shorebird_ci.yaml` is the workflow `shorebird_ci generate` produces for
a minimal Dart workspace with two packages — `app` (depends on `core`)
and `core`:

```
my_repo/
  pubspec.yaml          # workspace root
  packages/
    app/pubspec.yaml    # depends on core
    core/pubspec.yaml
```

Reproduce it with:

```sh
dart pub global activate shorebird_ci
shorebird_ci generate --repo-root . --dry-run --no-update-actions
```

(`--no-update-actions` keeps the action pins built into shorebird_ci;
without it they move to each action's latest release.)

The workflow has three jobs. `setup` activates `shorebird_ci` on the
runner, calls `verify` to fail fast if CI coverage has drifted from the
dep graph, then calls `affected_packages` to emit the JSON matrix.
`dart_ci` fans out across that matrix, running format / analyze / test
for each affected package — including transitive dependents (a change
to `core` runs `app` too). `zizmor` lints every workflow in
`.github/workflows/` with a pinned zizmor release, checked against its SHA-256.

For Flutter packages a parallel `flutter_ci` job is added, with
`flutter_version` resolved from the pubspec when pinned. With codecov
configured, coverage upload steps are added. With a cspell config
present, a `cspell` job is added. None of those apply to this minimal
example.

See the package README for the static (`--style static`) variant and
other options.
