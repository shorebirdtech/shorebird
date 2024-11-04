import 'package:shorebird_code_push/src/shorebird_updater.dart';
import 'package:shorebird_code_push/src/updater.dart';

/// {@template shorebird_updater_web}
/// The Shorebird web updater.
/// {@endtemplate}
class ShorebirdUpdaterImpl implements ShorebirdUpdater {
  /// {@macro shorebird_updater_web}
  ShorebirdUpdaterImpl(this._updater) {
    logShorebirdEngineUnavailableMessage();
  }

  // ignore: unused_field
  final Updater _updater;

  @override
  bool get isAvailable => false;

  @override
  Future<Patch?> readCurrentPatch() async => null;

  @override
  Future<Patch?> readNextPatch() async => null;

  @override
  Future<UpdateStatus> checkForUpdate() async => UpdateStatus.unavailable;

  @override
  Future<void> update() async {}
}
