# Shorebird Release Playbook

Attempting to write down all the steps to releasing a new version of
`shorebird`.

See also https://github.com/shorebirdtech/shorebird/blob/main/FORKING_FLUTTER.md
which lists some of these steps from the vantage point of updating our forks.


When you have the code all ready you need to build the engine artifacts:

1. https://github.com/shorebirdtech/build_engine/blob/main/build_engine/build_and_upload.sh
   is the combined script.  Before you run it you want to make sure your local
   gcloud is already authorized.

You run it like:
```
./build_engine/build_engine/build_and_upload.sh \
  /Users/eseidel/Documents/GitHub/engine \
  e6a2a5a43973430d9f038cd81cb1779b6b404909
```

If it fails for any reason, there are separate scripts `build.sh` and
`upload.sh` which you can use to run only parts of the process.  The whole
process should be repeatable without error (`ninja` null builds are quick,
`gsutil cp` will recognize identical objects, etc.)

The process must currently be run from an arm64 Mac as we depend on that for
uploading the `patch` artifact.  We build patch artifacts from GitHub Actions
for other platforms.

1. You can test the artifacts you built by modifying `bin/internal/flutter.version`
   and commiting that to `codepush` branch in `shorebirdtech/flutter`.

1.  Once `codepush` flutter is pushed, we also need to update shorebird_cli
    to pull the correct `flutter` revision.  `bin/internal/flutter.version`.

1.  We also need to bump the `shorebird_cli` version in the `pubspec.yaml` and
    run `dart pub run build_runner build --delete-conflicting-outputs` to update
    the `version.dart`
    https://github.com/shorebirdtech/shorebird/blob/05fd2f9ef0bcc1fd16e431029278f02001d5dbc9/packages/shorebird_cli/lib/src/version.dart#L2

e.g.  https://github.com/shorebirdtech/shorebird/pull/287

1.  To deploy the backend to production, navigate to the GitHub Actions at https://github.com/shorebirdtech/_shorebird/actions and select the Prod Deploy action (https://github.com/shorebirdtech/_shorebird/actions/workflows/deploy_prod.yaml). Click "Run workflow" and select the branch from the drop-down (we have been promoting from main but should probably switch to a release branch or tags?).

1. Once all these changes are done, we push a new version of the CLI by pushing
to the `stable` branch on `shorebird`.

```
git push origin main:stable
```
