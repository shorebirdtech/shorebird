/// Shorebird Web Console URLs.
class ShorebirdWebConsole {
  /// Returns a [Uri] for the Shorebird Web Console.
  static Uri uri(String path) {
    return Uri.parse('https://console.shorebird.dev/$path');
  }

  /// Returns a [Uri] for the Shorebird Web Console login page.
  static Uri appReleaseUri(
    String appId,
    int releaseId,
  ) {
    return ShorebirdWebConsole.uri(
      'apps/$appId/releases/$releaseId',
    );
  }
}
