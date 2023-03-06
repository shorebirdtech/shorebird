To replicate the updater demo, you'll need a copy of the Flutter Engine.

These are _not_ how Shorebird will work, but this is what I hacked together
for the demo video. Writing these down so others can replicate if desired.

# Building the updater library for Android

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
cargo +beta ndk --target aarch64-linux-android build --release
```

# Setting up to build the Flutter Engine:

https://github.com/flutter/flutter/wiki/Setting-up-the-Engine-development-environment
https://github.com/flutter/flutter/wiki/Compiling-the-engine

I would consider building a clean engine first and testing that you have
that working before trying Shorebird's modified engine.

The hacked up version of the engine used for my demo can be found here:
https://github.com/shorebirdtech/engine/tree/codepush

# Symlink in the Rust binaries

I symlinked the results of the rust build into the engine/src directory:

```
cd flutter
mkdir updater
cd updater
ln -s $HOME/Documents/GitHub/shorebird_private/shorebird/updater/library/include/updater.h
mkdir android_aarch64
cd android_aarch64
ln -s $HOME/Documents/GitHub/shorebird_private/shorebird/updater/target/aarch64-linux-android/release/libupdater.a
```

# Building Flutter Engine

```
./flutter/tools/gn --android --android-cpu arm64 --runtime-mode=release
ninja -C out/android_release_arm64
```

The linking step for android_release_arm64 is _much_ longer than other platforms
we may need to use unopt or debug builds for faster iteration.

I also add `&& say "done"` to the end of the ninja command so I know when it's
done (because it takes minutes).

# Running the updater

From updater_demo:

```
flutter run --local-engine-src-path $HOME/Documents/GitHub/engine/src --local-engine=android_release_arm64 --release
```

Only need to do that once, once it's installed on the phone then you don't
need `flutter run` anymore.

# Building the replacement libraries

For the demo I used "android.a" and "android.b" which were just copies of
libapp.so files which Flutter had built for me.

Once you've built the Flutter app in the way you want it:

```
cp build/app/intermediates/stripped_native_libs/release/out/lib/arm64-v8a/libapp.so android.a
```

You could dig them out of the apk, but that intermediate directory should be
the correct file and is much easier.

`flutter build apk -t lib/main_b.dart` should build the app in the way I used
in my demo (I built it with `flutter run` and modifying main.dart directly, but
that command should work too).

# shorebird command line

I hadn't yet modified `shorebird` to include the `publisher` functionality,
so I had this in my path:

```
#!/bin/bash
dart run $HOME/Documents/Github/shorebird_private/shorebird/updater/publisher/bin/publisher.dart publish $2
```

The right solution is to remove the old shorebird functionality and integrate publisher.

# Ports

Because updater_server as running locally I also had to forward ports from my
host into the emulator:

```
adb reverse tcp:8080 tcp:8080
```

# Running the updater_server

In a separate terminal:

```
cd shorebird/updater/updater_server
dart run
```

# The demo

The demo was then just launching the app on the emulator (manually)
and then using the `shorebird` command line to publish the new libraries
to change what code the app ran:

```
shorebird publish android.a
shorebird publish android.b
```
