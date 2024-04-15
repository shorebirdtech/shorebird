class ShorebirdWebConsole {
  static String linkTo(String path) {
    return 'https://console.shorebird.dev/$path';
  }

  static String linkToAppRelease(String appId, int releaseId) {
    return linkTo('apps/$appId/releases/$releaseId');
  }
}
