import 'package:mason_logger/mason_logger.dart';

class ShorebirdWebConsole {
  static String linkTo(
    String path, {
    String? message,
  }) {
    return link(
      uri: Uri.parse('https://console.shorebird.dev/$path'),
      message: message,
    );
  }

  static String linkToAppRelease(String appId, int releaseId) {
    return linkTo(
      'apps/$appId/releases/$releaseId',
      message: 'Shorebird release',
    );
  }
}
