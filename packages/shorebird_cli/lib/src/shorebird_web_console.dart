class ShorebirdWebConsole {
  static Uri uri(String path) {
    return Uri.parse('https://console.shorebird.dev/$path');
  }

  static Uri appReleaseUri(
    String appId,
    int releaseId,
  ) {
    return ShorebirdWebConsole.uri(
      'apps/$appId/releases/$releaseId',
    );
  }
}
