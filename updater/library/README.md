# Shorebird CodePush Updater

The rust library that does the actual update work.

## Design

The updater library is built in Rust for safety (and modernity).  It's built
as a C-compatible library, so it can be used from any language.

The library is thread-safe, as it needs to be called both from the flutter_main
thread (during initialization) and then later from the Dart/UI thread 
(from application Dart code) in Flutter.

The overarching principle with the Updater is "first, do no harm".  The updater
should "fail open", terms of continuing to work with the currently installed
or active version of the application even when the network is unavailable.

The updater also needs to handle error cases conservatively, such as partial
downloads from a server, or malformed responses (e.g. a proxy interfering)
and not crash the application or leave the application in a broken state.

Every time the updater runs it needs to verify that the currently installed
patch is compatible with the currently installed base version.  If it is not,
it should refuse to return paths to incompatible patches.

The updater also needs to regularly verify that the current state directory
is in a consistent state.  If it is not, it should invalidate any installed
patches and return to a clean state.

Not all of the above is implemented yet, but such is the intent.

## Architecture

The updater is split into separate layers.  The top layer is the C-compatible
API, which is used by all consumers of the updater.  The C-compatible API
is a thin wrapper around the Rust API, which is the main implementation but
only used directly for testing (see the `cli` directory).

Thread safety is handled by a global configuration object that is locked
when accessed.  It's possible I've missed cases where this is not sufficient,
and there could be thread safety issues in the library.

* src/c_api.rs - C-compatible API
* src/lib.rs - Rust API (and crate root)
* src/update.rs - Core updater logic
* src/config.rs - In memory configuration and thread locking
* src/cache.rs - On-disk state management
* src/logging.rs - Logging configuration (for platforms that need it)
* src/network.rs - Logic dealing with network requests and updater server

## Rust
We use normal rust idioms (e.g. Result) inside the library and then bridge those
to C via an explicit stable C API (explicit enums, null pointers for optional
arguments, etc).  The reason for this is that it lets the Rust code feel natural
and also gives us maximum flexibility in the future for exposing more in the C
API without having to refactor the internals of the library.

https://docs.rust-embedded.org/book/interoperability/rust-with-c.html
are docs on how to use Rust from C (what we're doing).

https://github.com/RubberDuckEng/safe_wren has an example of building in Rust
and exposing it with a C api.

## Integration

The updater library is built as a static library, and is linked into the
libflutter.so as part of a custom build of Flutter.  We also link libflutter.so
with the correct flags such that updater symbols are exposed to Dart.

The `dart_bindings` directory contains the Dart bindings for the updater
library.

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

## Development

Uses cbindgen to generate the header file.

It isn't currently wired into the build process, so you'll need to run it manually if you change the API.

```
cargo install cbindgen
cbindgen --config cbindgen.toml --crate updater --output library/include/updater.h
```

## Imagined Architecture (not all implemented)

### Assumptions (not all enforced yet)
* Updater library is never allowed to crash, except on bad parameters from C.
* Network and Disk are untrusted.
* Running code is trusted.
* Store-installed bundle is trusted (e.g. APK).
* Updates are signed by a trusted key.
* Updates must be applied in order.
* Updates are applied in a single transaction.

### Update State Machine
* Server is authoritative, regarding current update/patch state.  Client can
  cache state in memory.  Not written to disk.
* Patches are downloaded to a temporary location on disk.
* Update State Machine:
  * `ready`: Just woke up, ready to check for updates.
  * `checking`: Checking for updates.
  * `update_available`: Update or rollback is available.
  * `no_update_available`: No update is available.
  * `downloading`: Downloading an update.
  * `downloaded`: Downloaded an update.
* Client keeps on disk:
  * cache of patches in "slots"
  * cache of in-progress download state.
  * Last booted patch (may not have been successful).
  * Last successful patch (never rolled back from unless becomes invalid).
* Boot State Machine:
  * `ready`: Just woke up, ready to boot.
  * `booting`: Booting a patch.
  * `booted`: Patch is booted, we will not go back from here.

### Slot State Machine
* Patches are cached on disk in "slots".
* There is a currently active slot (the one that is booted).
* Patches are identified by base revision + patch number.
* A given slot is:
  * `empty`: No update is installed.
  * `pending`: An update is installed but has not been validated.
  * `valid`: An update is installed and has been validated.
* Validation is a temporary state.  Patches/slots are revalidated on boot.

### Trust model
* Network and Disk are untrusted.
* Running software (including apk service) is trusted.
* Patch contents are signed, public key is included in the APK.

## TODO:
* Add an async API.
* Write tests for state management.
* Make state management/filesystem management atomic (and tested).
* Support validating patches/slots (hashes, signatures, etc).

## Later-stage update system design docs
* https://theupdateframework.io/
* https://fuchsia.dev/fuchsia-src/concepts/packages/software_update_system
