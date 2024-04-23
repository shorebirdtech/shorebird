import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/executables/executables.dart';

/// Mixin on [ShorebirdCommand] which exposes methods
/// to extract the release version from an app bundle.
mixin ShorebirdReleaseVersionMixin on ShorebirdCommand {
  /// Extract the release version from an appbundle.
  Future<String> extractReleaseVersionFromAppBundle(
    String appBundlePath,
  ) async {
    final results = await Future.wait([
      bundletool.getVersionName(appBundlePath),
      bundletool.getVersionCode(appBundlePath),
    ]);

    final versionName = results[0];
    final versionCode = results[1];
    return '$versionName+$versionCode';
  }
}
