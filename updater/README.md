# Updater library

This is the C/Rust side of the Shorebird code push system.  This is built
in Rust with a C API for easy calling from other languages, most notably
for linking into libflutter.so.

# Parts
* cli: Test the updater library via the Rust API (for development).
* dart_cli: Test ffi wrapping of updater library.
* library: The rust library that does the actual update work.

# TODO:
* Remove all non-MVP code.
* Add an async API.
* Add support for "channels" (e.g. beta, stable, etc).
* Write tests for state management.
* Make state management/filesystem management atomic (and tested).
* Move updater values out of the params into post body?
* Support hashing values and check them?
* Add "validate" command to validate state.
* Write a mode that runs the updater first and then launches whatever is downloaded?
* Use cbindgen to generate the C api header file.
  https://github.com/eqrion/cbindgen/blob/master/docs.md


# Rust
We use normal rust idioms (e.g. Result) inside the library and then bridge those
to C via an explicit stable C API (explicit enums, null pointers for optional
arguments, etc).  The reason for this is that it lets the Rust code feel natural
and also gives us maximum flexibility in the future for exposing more in the C
API without having to refactor the internals of the library.

## Notes
* https://github.com/RubberDuckEng/safe_wren has an example of building a rust library and exposing it with a C api.

## Other update systems
* https://theupdateframework.io/
* https://fuchsia.dev/fuchsia-src/concepts/packages/software_update_system
