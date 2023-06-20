import 'dart:ffi' as ffi;

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
  int currentPatchNumber() {
    try {
      return bindings.shorebird_current_boot_patch_number();
    } catch (e) {
      return 0;
    }
  }

  /// Whether a new patch is available.
  bool checkForUpdate() {
    try {
      return bindings.shorebird_check_for_update();
    } catch (e) {
      return false;
    }
  }

  /// The next patch number that will be loaded. Will be the same as
  /// currentPatchNumber if no new patch is available.
  int nextPatchNumber() {
    try {
      return bindings.shorebird_next_boot_patch_number();
    } catch (e) {
      return 0;
    }
  }
}
