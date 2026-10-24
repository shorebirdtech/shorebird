import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(ShorebirdWebConsole, () {
    late ShorebirdEnv shorebirdEnv;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
    }

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.hostedUri).thenReturn(null);
    });

    test('uri returns the correct uri with the received path', () {
      expect(
        runWithOverrides(() => ShorebirdWebConsole.uri('path')),
        Uri.parse('https://console.shorebird.dev/path'),
      );
    });

    test('appReleaseUri returns the correct uri to an app release', () {
      expect(
        runWithOverrides(() => ShorebirdWebConsole.appReleaseUri('appId', 123)),
        Uri.parse('https://console.shorebird.dev/apps/appId/releases/123'),
      );
    });

    group('baseUri', () {
      test('is the production console by default', () {
        expect(
          runWithOverrides(() => ShorebirdWebConsole.baseUri),
          Uri.parse(defaultConsoleUrl),
        );
      });

      test('is the production console for another code push server', () {
        when(
          () => shorebirdEnv.hostedUri,
        ).thenReturn(Uri.parse('http://localhost:8080'));
        expect(
          runWithOverrides(() => ShorebirdWebConsole.baseUri),
          Uri.parse(defaultConsoleUrl),
        );
      });

      test('is the dev console for the dev code push server', () {
        when(() => shorebirdEnv.hostedUri).thenReturn(Uri.parse(devHostedUrl));
        expect(
          runWithOverrides(() => ShorebirdWebConsole.baseUri),
          Uri.parse(devConsoleUrl),
        );
        expect(
          runWithOverrides(() => ShorebirdWebConsole.uri('account')),
          Uri.parse('https://console-dev.shorebird.dev/account'),
        );
      });
    });
  });
}
