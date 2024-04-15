import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdWebConsole, () {
    test('uri returns the correct uri with the received path', () {
      expect(
        ShorebirdWebConsole.uri('path'),
        Uri.parse('https://console.shorebird.dev/path'),
      );
    });

    test('appReleaseUri returns the correct uri to an app release', () {
      expect(
        ShorebirdWebConsole.appReleaseUri('appId', 123),
        Uri.parse('https://console.shorebird.dev/apps/appId/releases/123'),
      );
    });
  });
}
