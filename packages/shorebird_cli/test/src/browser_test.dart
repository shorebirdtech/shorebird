// cspell:words rundll32 FileProtocolHandler
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(Browser, () {
    final url = Uri.parse('https://auth.shorebird.dev/login?a=1&b=2');

    late ShorebirdLogger logger;
    late NativePlatform platform;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess process;
    late ShorebirdProcessResult result;
    late Browser browser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    NativePlatform platformFor(
      String os, [
      Map<String, String> environment = const {},
    ]) => TestNativePlatform(operatingSystem: os, environment: environment);

    setUp(() {
      logger = MockShorebirdLogger();
      platform = platformFor(NativePlatform.macOS);
      shorebirdEnv = MockShorebirdEnv();
      process = MockShorebirdProcess();
      result = MockShorebirdProcessResult();
      browser = Browser();

      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);
      when(() => result.exitCode).thenReturn(0);
      when(() => process.run(any(), any())).thenAnswer((_) async => result);
    });

    group('canOpen', () {
      test('is true on macOS and Windows', () {
        for (final os in [NativePlatform.macOS, NativePlatform.windows]) {
          platform = platformFor(os);
          expect(runWithOverrides(() => browser.canOpen), isTrue);
        }
      });

      test('is false on CI', () {
        when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);
        expect(runWithOverrides(() => browser.canOpen), isFalse);
      });

      test('is false over SSH', () {
        for (final key in ['SSH_CONNECTION', 'SSH_TTY']) {
          platform = platformFor(NativePlatform.macOS, {key: 'x'});
          expect(runWithOverrides(() => browser.canOpen), isFalse);
        }
      });

      test('on Linux, depends on a display', () {
        platform = platformFor(NativePlatform.linux);
        expect(runWithOverrides(() => browser.canOpen), isFalse);
        for (final key in ['DISPLAY', 'WAYLAND_DISPLAY']) {
          platform = platformFor(NativePlatform.linux, {key: ':0'});
          expect(runWithOverrides(() => browser.canOpen), isTrue);
        }
      });

      test('is false on other platforms', () {
        platform = platformFor(NativePlatform.fuchsia);
        expect(runWithOverrides(() => browser.canOpen), isFalse);
      });
    });

    group('open', () {
      test('uses open on macOS', () async {
        expect(await runWithOverrides(() => browser.open(url)), isTrue);
        verify(() => process.run('open', [url.toString()])).called(1);
      });

      test('uses the URL protocol handler on Windows', () async {
        platform = platformFor(NativePlatform.windows);
        expect(await runWithOverrides(() => browser.open(url)), isTrue);
        verify(
          () => process.run('rundll32', [
            'url.dll,FileProtocolHandler',
            url.toString(),
          ]),
        ).called(1);
      });

      test('uses xdg-open on Linux', () async {
        platform = platformFor(NativePlatform.linux);
        expect(await runWithOverrides(() => browser.open(url)), isTrue);
        verify(() => process.run('xdg-open', [url.toString()])).called(1);
      });

      test('returns false when the opener fails', () async {
        when(() => result.exitCode).thenReturn(1);
        expect(await runWithOverrides(() => browser.open(url)), isFalse);
        verify(() => logger.detail('open exited with code 1')).called(1);
      });

      test('returns false when the opener cannot run', () async {
        when(
          () => process.run(any(), any()),
        ).thenThrow(const ProcessException('open', []));
        expect(await runWithOverrides(() => browser.open(url)), isFalse);
        verify(
          () =>
              logger.detail(any(that: startsWith('Unable to open a browser'))),
        ).called(1);
      });
    });
  });
}
