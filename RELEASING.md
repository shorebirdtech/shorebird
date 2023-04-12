# Shorebird Release Playbook

Attempting to write down all the steps to releasing a new version of `shorebird`.

See also https://github.com/shorebirdtech/shorebird/blob/main/FORKING_FLUTTER.md
which lists some of these steps from the vantage point of updating our forks.


When you have the code all ready you need to build the engine artifacts:

1. https://github.com/shorebirdtech/build_engine/blob/main/build_engine/build_and_upload.sh
   is the combined script.  Before you run it you want to make sure your local gcloud
   is already authorized.

You run it like:
```
./build_engine/build_engine/build_and_upload.sh /Users/eseidel/Documents/GitHub/engine e6a2a5a43973430d9f038cd81cb1779b6b404909
```

If it fails for any reason, there are separate scripts `build.sh` and `upload.sh`
which you can use to run only parts of the process.  The whole process should be
repeatable without error (ninja null builds are quick, gcloud upload will recognize
identical objects, etc.)

The process must currently be run from an arm64 Mac as we depend on that for
uploading the `patch` artifact.  We build patch artifacts from GitHub Actions
for other platforms.

(Should we change the script to upload to both dev and prod?  Just dev?  Just prod,
e.g not bother with a separate dev for artifacts?  Should we
have a separate script that promotes from dev to prod?)

2. Once the artifacts for the shorebird engine are uploaded, we now need to teach
artifact_proxy that they exist:
https://github.com/shorebirdtech/shorebird/blob/main/packages/artifact_proxy/lib/config.dart

Once that's made and commited, it should automatically push to dev via GitHub actions:
https://github.com/shorebirdtech/shorebird/actions/workflows/deploy_artifact_proxy_dev.yaml

Currently the dev artifact proxy is:
https://artifact-proxy-kmdbqkx7rq-uc.a.run.app/
(We should change that to be downloads-dev.shorebird.dev?)

3. Once the dev proxy is live it's now possible to test your change locally.
We don't currently have an easy way to point shorebird_cli at the dev proxy
but you can modify your shorebird_cli to do so:
https://github.com/shorebirdtech/shorebird/blob/5f435a9f0fad1a3ed308b21e5be0a9e87408d6e4/packages/shorebird_cli/lib/src/shorebird_process.dart#L89

4. To test your changes you also need to modify `flutter`.
(See also FORKING_FLUTTER.md).

I recommend testing the change (and the previous changes), by changing your local
shorebird/bin/cache/flutter/bin/internal/engine.version to your engine version.

At this point, assuming `shorebird` in your path points to your development checkout
you should be able to test your changes with `shorebird release` and `shorebird patch`?

5. Once you believe your changes are working you can commit the change to `flutter`.
  We *should* update `shorebird_cli` dependencies to reflect this change,
but that's not wired up yet.  Currently we instead push to the stable channel on
`shorebirdtech/flutter`.  https://github.com/shorebirdtech/shorebird/issues/282.
We probably want to do that as the last step?

6.  Once our forked flutter is pushed, we also need to update shorebird_cli to match
  the correct engine revision (this will go away when https://github.com/shorebirdtech/shorebird/issues/282
  is fixed).

7.  We also need to update the version of `shorebird` somewhere?
8.  Do we need to push a new version of the backend?


Anything else?
