# Shorebird CodePush Updater

The rust library that does the actual update work.

## Building for Android

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
