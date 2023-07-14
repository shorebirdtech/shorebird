import 'package:meta/meta.dart';
import 'package:shorebird_code_push/src/shorebird_code_push_base.dart';
import 'package:shorebird_code_push/src/shorebird_code_push_ffi.dart';
import 'package:shorebird_code_push/src/shorebird_code_push_noop.dart';
import 'package:shorebird_code_push/src/updater.dart';

/// {@template shorebird_code_push}
/// Get info about your Shorebird code push app.
/// {@endtemplate}
class ShorebirdCodePush implements ShorebirdCodePushBase {
  /// {@macro shorebird_code_push}
  ShorebirdCodePush() : this._(updater: const Updater());

  /// Constructor used for testing which allows injecting a mock [Updater].
  @visibleForTesting
  ShorebirdCodePush.test({Updater updater = const Updater()})
      : this._(updater: updater);

  ShorebirdCodePush._({required Updater updater}) {
    try {
      // If the Shorebird Engine is not available, this will throw an exception.
      updater.currentPatchNumber();
      _delegate = ShorebirdCodePushFfi(updater: updater);
    } catch (error) {
      // ignore: avoid_print
      print('[ShorebirdCodePush]: Error initializing updater: $error');
      _delegate = ShorebirdCodePushNoop();
    }
  }

  late final ShorebirdCodePushBase _delegate;

  @override
  bool isShorebirdAvailable() => _delegate.isShorebirdAvailable();

  @override
  Future<bool> isNewPatchAvailableForDownload() {
    return _delegate.isNewPatchAvailableForDownload();
  }

  @override
  Future<int?> currentPatchNumber() => _delegate.currentPatchNumber();

  @override
  Future<int?> nextPatchNumber() => _delegate.nextPatchNumber();

  @override
  Future<void> downloadUpdateIfAvailable() {
    return _delegate.downloadUpdateIfAvailable();
  }

  @override
  Future<bool> isNewPatchReadyToInstall() {
    return _delegate.isNewPatchReadyToInstall();
  }
}
