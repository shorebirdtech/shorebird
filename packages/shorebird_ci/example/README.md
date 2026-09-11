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
shorebird_ci generate --repo-root . --dry-run
```

The workflow has two jobs. `setup` activates `shorebird_ci` on the
runner, calls `verify` to fail fast if CI coverage has drifted from the
dep graph, then calls `affected_packages` to emit the JSON matrix.
`dart_ci` fans out across that matrix, running format / analyze / test
for each affected package — including transitive dependents (a change
to `core` runs `app` too).

For Flutter packages a parallel `flutter_ci` job is added, with
`flutter_version` resolved from the pubspec when pinned. With codecov
configured, coverage upload steps are added. With a cspell config
present, a `cspell` job is added. None of those apply to this minimal
example.

See the package README for the static (`--style static`) variant and
other options.
