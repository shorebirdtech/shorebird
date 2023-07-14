import 'dart:ffi' as ffi;

import 'package:meta/meta.dart';
import 'package:shorebird_code_push/src/generated/updater_bindings.g.dart';

/// {@template updater}
/// A wrapper around the generated [UpdaterBindings] that, when necessary,
/// translates ffi types into easier to use Dart types.
/// {@endtemplate}
class Updater {
  /// {@macro updater}
  const Updater();

  /// The ffi bindings to the Updater library.
  @visibleForTesting
  static UpdaterBindings bindings =
      UpdaterBindings(ffi.DynamicLibrary.process());

  /// The currently active patch number.
  int currentPatchNumber() => bindings.shorebird_current_boot_patch_number();

  /// Whether a new patch is available.
  bool checkForUpdate() => bindings.shorebird_check_for_update();

  /// The next patch number that will be loaded. Will be the same as
  /// currentPatchNumber if no new patch is available.
  int nextPatchNumber() => bindings.shorebird_next_boot_patch_number();

  /// Downloads the latest patch, if available.
  void downloadUpdate() => bindings.shorebird_update();
}
