class ShorebirdWebConsole {
  static Uri buildLink(String path) {
    return Uri.parse('https://console.shorebird.dev/$path');
  }

  static Uri buildAppReleaseLink(
    String appId,
    int releaseId,
  ) {
    return buildLink(
      'apps/$appId/releases/$releaseId',
    );
  }
}
