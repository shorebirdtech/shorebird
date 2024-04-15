import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:test/test.dart';

void main() {
  group('ShorebirdWebConsole', () {
    test('linkTo returns the expected link to the root of the site', () {
      expect(
        ShorebirdWebConsole.linkTo('path'),
        '\x1B]8;;https://console.shorebird.dev/path\x1B\\https://console.shorebird.dev/path\x1B]8;;\x1B\\',
      );
    });

    test('linkToAppRelease returns the expected link to an app release', () {
      expect(
        ShorebirdWebConsole.linkToAppRelease('appId', 123),
        '\x1B]8;;https://console.shorebird.dev/apps/appId/releases/123\x1B\\Shorebird release\x1B]8;;\x1B\\',
      );
    });
  });
}
