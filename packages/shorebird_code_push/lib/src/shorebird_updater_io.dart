import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_code_push/src/generated/updater_bindings.g.dart';
import 'package:shorebird_code_push/src/shorebird_updater.dart';
import 'package:shorebird_code_push/src/updater.dart';

@visibleForTesting

/// Type definition for [Isolate.run].
typedef IsolateRun = Future<R> Function<R>(
  FutureOr<R> Function(), {
  String? debugName,
});

/// {@template shorebird_updater_io}
/// The Shorebird IO Updater.
/// {@endtemplate}
class ShorebirdUpdaterImpl implements ShorebirdUpdater {
  /// {@macro shorebird_updater_io}
  ShorebirdUpdaterImpl({Updater? updater, IsolateRun? run})
      : _updater = updater ?? const Updater(),
        _run = run ?? Isolate.run {
    try {
      // If the Shorebird Engine is not available, this will throw an exception.
      // FIXME: Run this in an isolate or refactor the updater to avoid risking
      // a hang. If another thread is also calling into Shorebird at the same
      // time the underlying Rust code could block getting the config lock.
      _updater.currentPatchNumber();
      _isAvailable = true;
      // We explicitly catch all errors and exceptions to ensure we notify users
      // when the Shorebird Updater is unavailable.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      logShorebirdEngineUnavailableMessage();
      _isAvailable = false;
    }
  }

  late final bool _isAvailable;

  final Updater _updater;

  final IsolateRun _run;

  @override
  bool get isAvailable => _isAvailable;

  @override
  Future<Patch?> readCurrentPatch() => _readPatch(_updater.currentPatchNumber);

  @override
  Future<Patch?> readNextPatch() => _readPatch(_updater.nextPatchNumber);

  Future<Patch?> _readPatch(int Function() fn) async {
    if (!_isAvailable) return null;
    return _run(
      () {
        try {
          final patchNumber = fn();
          return patchNumber > 0 ? Patch(number: patchNumber) : null;
        } catch (error) {
          throw ReadPatchException(message: '$error');
        }
      },
    );
  }

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    if (!_isAvailable) return UpdateStatus.unavailable;

    // First, check to see whether an update is available for download.
    final isUpdateAvailable =
        await _run(() => _updater.checkForDownloadableUpdate(track: track));
    if (isUpdateAvailable) return UpdateStatus.outdated;

    // If no new update is available for download, see if a new patch exists
    // on disk that requires a restart.
    final (current, next) = await (readCurrentPatch(), readNextPatch()).wait;
    return next != null && current?.number != next.number
        ? UpdateStatus.restartRequired
        : UpdateStatus.upToDate;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    if (!_isAvailable) return;

    Pointer<UpdateResult> result = nullptr;

    try {
      result = await _run(() => _updater.update(track: track));
      // Explicitly catch all errors/exceptions to ensure we gracefully fallback.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return _legacyFallback();
    }

    const unknownErrorMessage = 'An unknown error occurred.';

    try {
      if (result == nullptr) {
        throw const UpdateException(
          reason: UpdateFailureReason.unknown,
          message: unknownErrorMessage,
        );
      }

      final status = result.ref.status;

      if (status == SHOREBIRD_UPDATE_INSTALLED) return;

      final reason = status.toFailureReason();
      final message = result.ref.message != nullptr
          ? result.ref.message.cast<Utf8>().toDartString()
          : unknownErrorMessage;
      throw UpdateException(message: message, reason: reason);
    } finally {
      _updater.freeUpdateResult(result);
    }
  }

  // Fallback to downloadUpdate if update is not available.
  Future<void> _legacyFallback() async {
    await _run(_updater.downloadUpdate);
    final (current, next) = await (readCurrentPatch(), readNextPatch()).wait;
    final status = next != null && current?.number != next.number
        ? UpdateStatus.restartRequired
        : UpdateStatus.upToDate;
    if (status == UpdateStatus.restartRequired) return;
    throw const UpdateException(
      message: '''
Downloading update failed but reason is unknown due to legacy updater.
Please upgrade the Shorebird Engine for improved error messages.''',
      reason: UpdateFailureReason.unknown,
    );
  }
}

extension on int {
  UpdateFailureReason toFailureReason() {
    switch (this) {
      case SHOREBIRD_NO_UPDATE:
        return UpdateFailureReason.noUpdate;
      case SHOREBIRD_UPDATE_HAD_ERROR:
        return UpdateFailureReason.downloadFailed;
      case SHOREBIRD_UPDATE_IS_BAD_PATCH:
        return UpdateFailureReason.installFailed;
      case SHOREBIRD_UPDATE_ERROR:
        return UpdateFailureReason.unknown;
      default:
        return UpdateFailureReason.unknown;
    }
  }
}
