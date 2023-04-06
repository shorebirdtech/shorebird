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

We're writing scripts to do that now.  The process is approximately:

1. Pick a version of Flutter to update to (e.g. 3.7.10) new_flutter
2. Find the version of Flutter we're based on (currently 3.7.8) old_flutter
3. Find the engine version for new_flutter (e.g. 3.7.10) new_engine
4. Find the engine version for old_flutter (e.g. 3.7.8) old_engine
5. Find the buildroot version for new_engine (e.g. 3.7.10) new_buildroot
6. Find the buildroot version for old_engine (e.g. 3.7.8) old_buildroot
With that data, we now just go through and move the patches we made from
on top of old_* to be on top of new_*.  e.g.
`git rebase --onto new_flutter old_flutter stable_codepush`

We have to do that for the engine, flutter, and buildroot repos.
Once we've done that, now we need to go through and update the version
numbers in the various places.  e.g. in the engine repo, we need to update
the new forked buildroot version number in `DEPS`, similarly in the flutter
repo we need to update the engine version number in `bin/internal/engine.version`
and finally in the shorebird CLI we need to update the version number in
https://github.com/shorebirdtech/shorebird/blob/main/packages/shorebird_cli/lib/src/engine_revision.dart

Before we can publish the new version of Shorebird, we need to build the
engine for all the platforms we support.  We do that by running the
`build_and_upload.sh` script in the build_engine repo.  That script should
be run in the cloud, but right now I've not figured that out yet, so we run
it locally on an arm64 Mac.

Once we've built all artifacts we need to teach the artifact_proxy how to
serve them.  We do that by adding entries to:
https://github.com/shorebirdtech/shorebird/blob/main/packages/artifact_proxy/lib/config.dart

Additionally, that script currently depends on the `updater` repo already
having published the new version of the `patch` binaries as it will download
those from GitHub releases.

Obviously all this needs to be made better/automated.