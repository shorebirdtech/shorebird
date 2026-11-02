import 'package:shorebird_cli/src/shorebird_env.dart';

/// Shorebird Web Console URLs.
class ShorebirdWebConsole {
  /// The console of the [ShorebirdEnv.hostedEnvironment] the CLI talks to,
  /// otherwise [defaultConsoleUrl].
  static Uri get baseUri => Uri.parse(
    shorebirdEnv.hostedEnvironment?.consoleUrl ?? defaultConsoleUrl,
  );

  /// Returns a [Uri] for the Shorebird Web Console.
  static Uri uri(String path) => baseUri.resolve(path);

  /// Returns a [Uri] for the Shorebird Web Console login page.
  static Uri appReleaseUri(String appId, int releaseId) {
    return ShorebirdWebConsole.uri('apps/$appId/releases/$releaseId');
  }

  /// Returns a [Uri] for an app's settings page, where it is deleted.
  ///
  /// The console's app pages live under the app's organization. Without
  /// one, falls back to the console's home page, which lists every app.
  static Uri appSettingsUri({
    required int? organizationId,
    required String appId,
  }) {
    if (organizationId == null) return baseUri;
    return uri('orgs/$organizationId/apps/$appId/settings');
  }
}
