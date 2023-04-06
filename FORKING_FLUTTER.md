# Forking Flutter

Shorebird uses a fork of Flutter.  Shorebird's first product is code push.
Code push requires technical changes to the underlying Flutter engine.  To make
those changes required forking Flutter.

This document summarizes the changes we've made to the various parts of Flutter.

### flutter/engine

The engine is the C++ code that runs on the device.  It is responsible for
rendering the UI, handling input, and communicating with the host.

We forked this code to add the ability to have release versions of the Flutter
engine be able to load new code from Shorebird's servers.

At time of writing, Shorebird's fork is based on Flutter 3.7.8.  You can see
our engine changes here:
https://github.com/flutter/engine/compare/3.7.8...shorebirdtech:engine:stable_codepush

### flutter/flutter

The flutter/flutter repo contains the Dart code that runs on the device as well
as the `flutter` tool that is used to build and run Flutter apps.

We initially did not fork this code.  And still don't really want to fork
this code, but in order to deliver a modified engine w/o affecting other
Flutter installations, we needed to be able to change the *version* of the
engine that the `flutter` tool downloads.

Our one fork is to change bin/internal/engine.version to point to our
engine version.  You can see our changes here:
https://github.com/flutter/flutter/compare/3.7.8...shorebirdtech:flutter:stable_codepush


### flutter/buildroot

The buildroot repo contains the build scripts that are used to build the
Flutter engine for various platforms.  It's separate from flutter/engine in
order to share code and configuration with the Fuchsia build system.

We also didn't want to fork this code.  However we need to for now in order
to integrate our updater code.  Our updater code:
https://github.com/shorebirdtech/updater
is a Rust library which we link into the engine.  The way we do that is via
a C-API on a static library (libupdater.a).  The default flags for linking
for the Flutter engine hide all symbols from linked static libraries.  We
need to be able to expose the shorebird_* symbols from libupdater.a up through
FFI to the Dart code.  We did that my making one change to buildroot and then
a second change to the engine to place the symbols on the allow-list.

Our one change:
https://github.com/shorebirdtech/buildroot/commit/7383548fa2306b5d53979ac5e9d176b35258811b


## Vendoring our fork

When you install Shorebird, it installs Flutter and Dart from our fork.  These
are currently not exposed on the user's path, rather just private copies
that Shorebird will use when building your app.

This was necessary to avoid conflicts with other Flutter installations on the
user's machine.  Specifically, the way that Flutter downloads artifacts is
based on the version of the engine.  If we were to use the same version of the
engine as the user's Flutter installation, then we would overwrite the user's
engine artifacts.

We deliver our artifacts to this fork of Flutter with two ways.  First is we
change the version of the engine in the `flutter` tool.  Second is we pass
FLUTTER_STORAGE_BASE_URL set to download.shorebird.dev (instead of
download.flutter.io) when calling our vended copy of the `flutter` tool.

Currently this means `shorebird` will not work in an environment where the
user needs to use FLUTTER_STORAGE_BASE_URL to download Flutter artifacts 
from a private mirror (e.g. a corporate network or China).
https://github.com/shorebirdtech/shorebird/issues/237

## Keeping our fork up to date

We're writing scripts to do that now.  I'm writing out the process here as
I go through it manually so we can write scripts to automate it.

1. Pick a version of Flutter to update to (e.g. 3.7.10) new_flutter
3.7.10 flutter = https://github.com/flutter/flutter/tree/3.7.10
https://github.com/flutter/flutter/commit/4b12645012342076800eb701bcdfe18f87da21cf

2. Find the engine version for new_flutter (e.g. 3.7.10) new_engine
3.7.10 engine = https://github.com/flutter/flutter/blob/3.7.10/bin/internal/engine.version
ec975089acb540fc60752606a3d3ba809dd1528b

3. Find the buildroot version for new_engine (e.g. 3.7.10) new_buildroot
https://github.com/flutter/engine/tree/3.7.10/
3.7.10 buildroot = https://github.com/flutter/engine/blob/3.7.10/DEPS#L239
8747bce41d0dc6d9dc45c4d1b46d2100bb9ee688

4. Find the version of Flutter we're based on (currently, incorrectly 3.7.9) old_flutter
https://github.com/shorebirdtech/flutter/tree/stable
https://github.com/shorebirdtech/flutter/commit/62bd79521d8d007524e351747471ba66696fc2d4

5. Find the engine version for old_flutter (e.g. 3.7.8) old_engine
https://github.com/shorebirdtech/engine/tree/stable_codepush
is based on 3.7.8 engine =
https://github.com/flutter/engine/tree/3.7.8
https://github.com/shorebirdtech/engine/commit/9aa7816315095c86410527932918c718cb35e7d6

6. Find the buildroot version for old_engine (e.g. 3.7.8) old_buildroot
https://github.com/shorebirdtech/buildroot/commits/stable_codepush
is based on:
https://github.com/shorebirdtech/buildroot/commit/8747bce41d0dc6d9dc45c4d1b46d2100bb9ee688


7. With that data, we now just go through and move the patches we made from
on top of old_* to be on top of new_*.  e.g.
`git rebase --onto new_flutter old_flutter stable_codepush`

In addition to doing the rebasing we also need to go through and update the version
numbers in the various places.  We can do both in a single pass.

8. buildroot: Based on the above, we don't need to do anything for buildroot this time,
but do need to rebase the engine and flutter repos.

9. engine: But we do need to move our engine fork:
`git rebase --onto 3.7.10 3.7.8 stable_codepush`
And save off that hash:
`git rev-parse stable_codepush`
978a56f2d97f9ce24a2b6bc22c9bbceaaba0343c

We do not need to update our engine fork commits at this time since it already
pointed to the (unchanged) forked buildroot in `DEPS`.

10. flutter: Then we need to move our flutter fork.
Our flutter fork currently uses the `stable` channel instead of stable_codepush
we should eventually standardize on across all the repos on something.

If we change this branch we also would need to change the branch in the
shorebird cli which controls updating the flutter version.

Since the only commit on our flutter
fork is one changing engine.version, we can just replace the commit:
```
git fetch upstream
git reset --hard 3.7.10
cat '978a56f2d97f9ce24a2b6bc22c9bbceaaba0343c' > bin/internal/engine.version
git add bin/internal/engine.version
git commit -a -m 'chore: Update engine version to shorebird-3.7.10'
```
Again we should save off our new hash:
`git rev-parse stable`
7712d0d30a6e85eace6c1a886d4ae4f7938c3d6e

11.  Finally we need to update the shorebird cli itself.  Currently located at:
https://github.com/shorebirdtech/shorebird/blob/main/packages/shorebird_cli/lib/src/engine_revision.dart

12. If there were changes to the `patch` binary in the `updater` library we
will need to tigger github actions before we can publish the new version of
the shorebird engine.

13. Before we can publish the new version of Shorebird, we need to build the
engine for all the platforms we support.  We do that by running the
`build_and_upload.sh` script in the build_engine repo.

```
./build_engine/build_engine/build_and_upload.sh ./engine 978a56f2d97f9ce24a2b6bc22c9bbceaaba0343c  
```

That script should be run in the cloud, but right now I've not figured that out
yet, so we run it locally on an arm64 Mac.

13. Once we've built all artifacts we need to teach the artifact_proxy how to
serve them.  We do that by adding entries to:
https://github.com/shorebirdtech/shorebird/blob/main/packages/artifact_proxy/lib/config.dart

Obviously all this needs to be made better/automated.