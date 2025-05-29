import 'package:shorebird_code_push/src/shorebird_updater_io.dart'
    if (dart.library.js_interop) './shorebird_updater_web.dart';

/// The reason a call to [ShorebirdUpdater.update] failed.
enum UpdateFailureReason {
  /// No update is available.
  noUpdate,

  /// The update failed because the patch could not be downloaded.
  downloadFailed,

  /// The update failed because the patch failed to install.
  installFailed,

  /// The update failed for an unknown reason.
  unknown,
}

/// {@template read_patch_exception}
/// An exception thrown by [ShorebirdUpdater.readCurrentPatch] and
/// [ShorebirdUpdater.readNextPatch] when the read is unsuccessful.
/// {@endtemplate}
class ReadPatchException implements Exception {
  /// {@macro update_exception}
  const ReadPatchException({required this.message});

  /// The human-readable error message.
  final String message;

  @override
  String toString() => '[ShorebirdUpdater] ReadPatchException: $message';
}

/// {@template update_exception}
/// An exception thrown by [ShorebirdUpdater.update] when the update is
/// unsuccessful.
/// {@endtemplate}
class UpdateException implements Exception {
  /// {@macro update_exception}
  const UpdateException({required this.message, required this.reason});

  /// The human-readable error message.
  final String message;

  /// The reason the update failed.
  final UpdateFailureReason reason;

  @override
  String toString() {
    return '[ShorebirdUpdater] UpdateException: $message (${reason.name})';
  }
}

/// Log message when the Shorebird updater is unavailable in the current
/// environment.
void logShorebirdEngineUnavailableMessage() {
  // Printing to the console is intentional here since we want it to be obvious
  // that the app is running in an environment where the updater is unavailable.
  // ignore: avoid_print
  print('''
-------------------------------------------------------------------------------
The Shorebird Updater is unavailable in the current environment.
-------------------------------------------------------------------------------
This occurs when using pkg:shorebird_code_push in an app that does not
contain the Shorebird Engine. Most commonly this is due to building with
`flutter build` or `flutter run` instead of `shorebird release` or `shorebird preview`.
It can also occur when running on an unsupported platform (e.g. web).
''');
}

/// {@template patch}
/// An object representing a single patch (over-the-air update).
/// {@endtemplate}
class Patch {
  /// {@macro patch}
  const Patch({required this.number});

  /// The patch number.
  final int number;
}

/// The current status of the app in terms of whether its up-to-date.
enum UpdateStatus {
  /// The app is up to date (e.g. running the latest patch.)
  upToDate,

  /// A new update is available for download.
  outdated,

  /// The app is up to date, but a restart is required for the update to take
  /// effect.
  restartRequired,

  /// The update status is unavailable. This occurs when the updater is not
  /// available in the current build.
  /// See also:
  /// * [ShorebirdUpdater.isAvailable] to determine if the updater is
  /// available.
  unavailable,
}

/// {@template shorebird_updater}
/// Manage updates for a Shorebird app.
/// {@endtemplate}
abstract class ShorebirdUpdater {
  /// {@macro shorebird_updater}
  factory ShorebirdUpdater() => ShorebirdUpdaterImpl();

  /// Whether the updater is available on the current platform.
  /// The most common reasons for this returning false are:
  /// 1. The app is running in debug mode (Shorebird only supports release
  ///    mode).
  /// 2. The app was *NOT* built using `shorebird release` and does *NOT*
  ///    contain the Shorebird engine.
  bool get isAvailable;

  /// Returns information about the currently installed patch.
  /// Returns `null` if no patch has been installed.
  /// Returns `null` if the updater is not available.
  /// Throws a [ReadPatchException] if the read is unsuccessful.
  Future<Patch?> readCurrentPatch();

  /// Returns information about the most recently downloaded patch.
  /// Returns the same patch as [readCurrentPatch] if no new patch has been
  /// downloaded.
  /// Returns `null` if the updater is not available.
  /// Throws a [ReadPatchException] if the read is unsuccessful.
  Future<Patch?> readNextPatch();

  /// Checks for an available patch on [track] (or [UpdateTrack.stable] if no
  /// track is specified) and returns the [UpdateStatus].
  /// This method should be used to determine the update status before calling
  /// [update].
  ///
  /// If this detects that the current patch has been rolled back, the current
  /// patch will be uninstalled.
  /// A separate call to `update()` is required to install new patches.
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track});

  /// Updates the app to the latest patch available on the specified track, or
  /// [UpdateTrack.stable] if no track is specified.
  ///
  /// If no update is available or the update fails, this method will throw an
  /// [UpdateException].
  ///
  /// The returned Future will complete once the update is fully downloaded and
  /// ready to be used on the next app start.
  ///
  /// Note: The app must be restarted for the update to take effect.
  /// Note: This method does nothing if the updater is not available.
  ///
  /// See also:
  /// * [isAvailable], which indicates whether the updater is available.
  /// * [checkForUpdate], which should be called to check if an update is
  ///   available before calling this method.
  Future<void> update({UpdateTrack? track});
}

/// A track to check for updates on.
///
/// In addition to the predefined tracks, you can also specify your own track
/// names by creating an instance of `UpdateTrack` with a custom string value.
///
/// For example, if you have a custom track named "my_custom_track", you can
/// create a patch on that track:
///
/// ```sh
///   shorebird patch android --track my_custom_track
/// ```
///
///  And then check for updates on that track in your app:
///
/// ```dart
///  final status = checkForUpdate(track: UpdateTrack('my_custom_track'));
/// ```
extension type const UpdateTrack(String value) {
  /// Used for internal testing.
  static const staging = UpdateTrack('staging');

  /// Used for public testing.
  static const beta = UpdateTrack('beta');

  /// Used for general availability. This is the default track.
  static const stable = UpdateTrack('stable');

  /// The name of the track.
  String get name => value;
}
