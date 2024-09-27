/// {@template shorebird_code_push_base}
/// Get info about your Shorebird code push app.
/// {@endtemplate}
abstract class ShorebirdCodePushBase {
  /// Whether the Shorebird Engine is available.
  bool isShorebirdAvailable();

  /// Checks whether a new patch is available for download.
  ///
  /// Returns true when there is a new patch for this app on Shorebird servers
  /// but not yet downloaded to this device.
  ///
  /// Returns false in all other cases, including when a new patch is installed
  /// locally but not yet booted from.
  /// Use [isNewPatchReadyToInstall] to check if a new patch has been downloaded
  /// and is ready to boot from on next restart.
  ///
  /// Runs in a separate isolate to avoid blocking the UI thread.
  Future<bool> isNewPatchAvailableForDownload();

  /// The version of the currently-installed patch. `null` if no patch is
  /// installed (i.e., the app is running the release version).
  ///
  /// This will also return `null` if Shorebird is not available.
  Future<int?> currentPatchNumber();

  /// The version of the patch that will be run on the next app launch. If no
  /// new patch has been downloaded, this will be the same as
  /// [currentPatchNumber].
  Future<int?> nextPatchNumber();

  /// Downloads the latest patch, if available.
  /// Does nothing if there is no new patch available.
  Future<void> downloadUpdateIfAvailable();

  /// Whether a new patch has been downloaded and is ready to install.
  ///
  /// If true, the patch number returned by [nextPatchNumber] will be run on the
  /// next app launch.
  Future<bool> isNewPatchReadyToInstall();
}
