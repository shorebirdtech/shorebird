import 'package:shorebird_cli/src/shorebird_env.dart';

/// The Shorebird Web Console for the production code push server.
const defaultConsoleUrl = 'https://console.shorebird.dev';

/// The Shorebird Web Console for [devHostedUrl].
const devConsoleUrl = 'https://console-dev.shorebird.dev';

/// Shorebird Web Console URLs.
class ShorebirdWebConsole {
  /// The console for the code push server the CLI talks to:
  /// [devConsoleUrl] when [ShorebirdEnv.hostedUri] is [devHostedUrl],
  /// otherwise [defaultConsoleUrl].
  static Uri get baseUri {
    final isDev = shorebirdEnv.hostedUri?.host == Uri.parse(devHostedUrl).host;
    return Uri.parse(isDev ? devConsoleUrl : defaultConsoleUrl);
  }

  /// Returns a [Uri] for the Shorebird Web Console.
  static Uri uri(String path) => baseUri.resolve(path);

  /// Returns a [Uri] for the Shorebird Web Console login page.
  static Uri appReleaseUri(String appId, int releaseId) {
    return ShorebirdWebConsole.uri('apps/$appId/releases/$releaseId');
  }
}
