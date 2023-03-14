# Updater library

This is the C/Rust side of the Shorebird code push system.  This is built
in Rust with a C API for easy calling from other languages, most notably
for linking into libflutter.so.

## Parts
* cli: Test the updater library via the Rust API (for development).
* dart_cli: Test ffi wrapping of updater library.
* library: The rust library that does the actual update work.

## Imagined Architecture (not all implemented)

### Update State Machine
* Server is authoritative, regarding current update/patch state.  Client can
  cache state in memory.  Not written to disk.
* Client keeps on disk:
  * cache of patches in "slots"
  * cache of in-progress download state.
  * Last booted patch (may not have been successful).
  * Last successful patch (never rolled back from unless becomes invalid).

### Slot State Machine
* Patches are cached on disk in "slots".
* There is a currently active slot (the one that is booted).
* Patches are identified by base revision + patch number.
* A given slot is:
  * `empty`: No update is installed.
  * `pending`: An update is installed but has not been validated.
  * `valid`: An update is installed and has been validated.
* Validation is a temporary state.  Patches/slots are revalidated on boot.

### Download State Machine
* Patches are downloaded to a temporary location on disk.
* A given download is:
  * `queued`: No download has been attempted.
  * `downloading`: Download is in progress.
  * `success`: Download is complete.
  * `failure`: Download failed.

### Trust model
* Network and Disk are untrusted.
* Running software (including apk service) is trusted.
* Patch contents are signed, public key is included in the APK.

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

## TODO:
* Add an async API.
* Write tests for state management.
* Make state management/filesystem management atomic (and tested).
* Support validating patches/slots (hashes, signatures, etc).

## Later-stage update system design docs
* https://theupdateframework.io/
* https://fuchsia.dev/fuchsia-src/concepts/packages/software_update_system
