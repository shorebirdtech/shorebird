import 'dart:isolate';

import 'package:shorebird_code_push/src/shorebird_code_push_base.dart';
import 'package:shorebird_code_push/src/updater.dart';

/// {@template shorebird_code_push}
/// Get info about your Shorebird code push app.
/// {@endtemplate}
class ShorebirdCodePushFfi implements ShorebirdCodePushBase {
  /// {@macro shorebird_code_push}
  ShorebirdCodePushFfi({Updater? updater})
      : _updater = updater ?? const Updater();

  final Updater _updater;

  @override
  Future<bool> isNewPatchAvailableForDownload() {
    return Isolate.run(_updater.checkForUpdate);
  }

  @override
  Future<int?> currentPatchNumber() {
    return Isolate.run(() {
      final currentPatchNumber = _updater.currentPatchNumber();
      // 0 means no patch is installed so we return null.
      return currentPatchNumber == 0 ? null : currentPatchNumber;
    });
  }

  @override
  Future<int?> nextPatchNumber() {
    return Isolate.run(
      () {
        final patchNumber = _updater.nextPatchNumber();
        // 0 means no patch is next so we return null.
        return patchNumber == 0 ? null : patchNumber;
      },
    );
  }

  @override
  Future<void> downloadUpdateIfAvailable() async {
    await Isolate.run(_updater.downloadUpdate);
  }

  @override
  Future<bool> isNewPatchReadyToInstall() async {
    final patchNumbers = await Future.wait([
      currentPatchNumber(),
      nextPatchNumber(),
    ]);
    final currentPatch = patchNumbers[0];
    final nextPatch = patchNumbers[1];

    return nextPatch != null && currentPatch != nextPatch;
  }

  @override
  bool isShorebirdAvailable() => true;
}
