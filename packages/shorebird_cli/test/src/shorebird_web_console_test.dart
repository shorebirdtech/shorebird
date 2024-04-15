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
        '\x1B]8;;https://console.shorebird.dev/apps/appId/releases/123\x1B\\https://console.shorebird.dev/apps/appId/releases/123\x1B]8;;\x1B\\',
      );
    });

    group('when passing a message', () {
      test('linkTo returns the expected link to the root of the site', () {
        expect(
          ShorebirdWebConsole.linkTo('path', message: 'label'),
          '\x1B]8;;https://console.shorebird.dev/path\x1B\\label\x1B]8;;\x1B\\',
        );
      });

      test('linkToAppRelease returns the expected link to an app release', () {
        expect(
          ShorebirdWebConsole.linkToAppRelease('appId', 123, message: 'label'),
          '\x1B]8;;https://console.shorebird.dev/apps/appId/releases/123\x1B\\label\x1B]8;;\x1B\\',
        );
      });
    });
  });
}
