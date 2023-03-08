# Building the Shorebird Flutter Engine

Shorebird uses a modified version of the Flutter engine.  Normally
when you use Shorebird, you would use the pre-built engine binaries
that we provide.  However, if you want to build the engine yourself,
this document describes how to do that.

The primary modification Shorebird makes to the stock Flutter engine
is adding support for the updater library.  The updater library is
written in Rust and is used to update the code running in the Flutter
app.  The updater library is built as a static library and is linked
into the Flutter engine during build time.

## Building the Updater Library

### Installing Rust

The updater library is written in Rust.  You can install Rust using
rustup.  See https://rustup.rs/ for details.

## Building for Android

Rust Android tooling *mostly* works out of the box, but needs a bunch
of configuration to get it to work.

The best way I found was to install:
https://github.com/bbqsrc/cargo-ndk

```
rustup install beta
cargo +beta install cargo-ndk
rustup +beta target add \
    aarch64-linux-android \
    armv7-linux-androideabi \
    x86_64-linux-android \
    i686-linux-android
```

If others know of better instructions, please send us a PR!

Once you have cargo-ndk installed, you can build the updater library with the
beta toolchain you installed and the ndk command:

```
cargo +beta ndk --target aarch64-linux-android build --release
```

### Setting up to build the Flutter Engine:

https://github.com/flutter/flutter/wiki/Setting-up-the-Engine-development-environment
https://github.com/flutter/flutter/wiki/Compiling-the-engine

The .gclient file I recommend is:
```
solutions = [
  {
    "managed": False,
    "name": "src/flutter",
    "url": "git@github.com:shorebirdtech/engine.git",
    "custom_deps": {},
    "deps_file": "DEPS",
    "safesync_url": "",
  },
]
```
(We should probably just check that in somewhere.)

Once you have that set up and `gclient sync` has run, you will need
to switch your flutter checkout to the `codepush` branch:

```
cd src/flutter
git checkout codepush
```

And then `gclient sync` again.

### Symlink in the Rust binaries

Currently you need to symlink in the results of the rust build into the engine/src directory:

```
cd flutter
mkdir updater
cd updater
ln -s $SRC/shorebird/updater/library/include/updater.h
mkdir android_aarch64
cd android_aarch64
ln -s $SRC/shorebird/updater/target/aarch64-linux-android/release/libupdater.a
```

## Building Flutter Engine

```
./flutter/tools/gn --android --android-cpu arm64 --runtime-mode=release
ninja -C out/android_release_arm64
```

The linking step for android_release_arm64 is _much_ longer than other platforms
we may need to use unopt or debug builds for faster iteration.

I also add `&& say "done"` to the end of the ninja command so I know when it's
done (because it takes minutes).


## Running with your local engine

The `shorebird` tools don't yet support local engines, so you need to use
`flutter run` directly.
https://github.com/shorebirdtech/shorebird/issues/42

Here is a script:
```
#! /bin/sh -x

LOCAL_ENGINE_SRC_PATH=/path/to/local/flutter/engine
LOCAL_ENGINE=android_release_arm64
flutter build apk --release --no-tree-shake-icons --local-engine-src-path $LOCAL_ENGINE_SRC_PATH --local-engine=$LOCAL_ENGINE
 ```

Only need to build with your custom engine once.  Once the app is installed on
the phone then you can `shorebird publish` to it as normal.
