# Updater library

This is the C/Rust side of the Shorebird code push system.  This is built
in Rust with a C API for easy calling from other languages, most notably
for linking into libflutter.so.

See cli/README.md for more documentation on the library.

## Parts
* cli: Test the updater library via the Rust API (for development).
* dart_cli: Test ffi wrapping of updater library.
* library: The rust library that does the actual update work.
* dart_bindings: The Dart bindings for the updater library.

All of the interesting code is in the `library` directory.  There is also
a README.md in that directory explaining the design.
