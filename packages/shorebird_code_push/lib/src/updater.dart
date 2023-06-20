import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_code_push/src/generated/updater_bindings.g.dart';

/// {@template updater}
/// A wrapper around the generated [UpdaterBindings] that translates ffi types
/// into easier to use Dart types.
/// {@endtemplate}
class Updater {
  /// Creates an [Updater] instance using the currently loaded dynamic library.
  Updater() {
    bindings = UpdaterBindings(ffi.DynamicLibrary.process());
  }

  /// The ffi bindings to the Updater library.
  @visibleForTesting
  static late UpdaterBindings bindings;

  /// The currently active patch number.
  // TODO(bryanoltman): this will return the current number + 1 if an update is
  // available. It should instead always return the current patch version.
  int? currentPatchNumber() {
    final patchNumberString = _returnsMaybeString(
      bindings.shorebird_next_boot_patch_number,
    );
    return patchNumberString == null ? null : int.tryParse(patchNumberString);
  }

  /// Whether a new patch is available.
  bool checkForUpdate() => bindings.shorebird_check_for_update();

  /// A wrapper for ffi functions that return [Pointer<Char].
  String? _returnsMaybeString(ffi.Pointer<ffi.Char> Function() f) {
    final cString = f();
    if (cString.address == ffi.nullptr.address) {
      return null;
    }

    final utf8Pointer = cString.cast<Utf8>();

    try {
      return utf8Pointer.toDartString();
    } finally {
      // Using finally for two reasons:
      // 1. it runs after the return (saving us a local)
      // 2. it runs even if toDartString throws (which it shouldn't)
      bindings.shorebird_free_string(cString);
    }
  }
}
