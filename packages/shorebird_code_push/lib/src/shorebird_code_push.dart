import 'dart:isolate';

import 'package:shorebird_code_push/src/updater.dart';

/// {@template shorebird_code_push}
/// Get info about your Shorebird code push app.
/// {@endtemplate}
class ShorebirdCodePush {
  /// {@macro shorebird_code_push}
  ShorebirdCodePush({
    Updater Function()? createUpdater, // for testing
  }) : _createUpdater = createUpdater ?? Updater.new;

  final Updater Function() _createUpdater;

  /// Checks whether a new patch is available for download.
  ///
  /// Runs in a separate isolate to avoid blocking the UI thread.
  Future<bool> checkForUpdate() {
    return _runInIsolate((updater) => updater.checkForUpdate());
  }

  /// The version of the currently-installed patch. Null if no patch is
  /// installed (i.e., the app is running the release version).
  Future<int?> currentPatchNumber() {
    return _runInIsolate((updater) {
      final patchNumber = updater.currentPatchNumber();
      return patchNumber == 0 ? null : patchNumber;
    });
  }

  /// The version of the patch that will be run on the next app launch. If no
  /// new patch has been downloaded, this will be the same as
  /// [currentPatchNumber].
  Future<int?> nextPatchNumber() {
    return _runInIsolate((updater) {
      final patchNumber = updater.nextPatchNumber();
      return patchNumber == 0 ? null : patchNumber;
    });
  }

  /// Creates an [Updater] in a separate isolate and runs the given function.
  Future<T> _runInIsolate<T>(T Function(Updater updater) f) async {
    return Isolate.run(() {
      // Create a new Updater in the new isolate.
      return f(_createUpdater());
    });
  }
}
