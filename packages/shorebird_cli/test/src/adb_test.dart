import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/adb.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

class _MockAndroidSdk extends Mock implements AndroidSdk {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockProcess extends Mock implements Process {}

void main() {
  group(Adb, () {
    const adbPath = '/path/to/adb';

    late AndroidSdk androidSdk;
    late ShorebirdProcess process;
    late Adb adb;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          androidSdkRef.overrideWith(() => androidSdk),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(const Stream<List<int>>.empty());
    });

    setUp(() {
      androidSdk = _MockAndroidSdk();
      process = _MockShorebirdProcess();
      adb = Adb();

      when(() => androidSdk.adbPath).thenReturn(adbPath);
      when(
        () => process.run(any(), any()),
      ).thenAnswer(
        (_) async => const ShorebirdProcessResult(
          exitCode: 0,
          stdout: '',
          stderr: '',
        ),
      );
    });

    group('startApp', () {
      const package = 'com.example.app';
      test('throws when unable to locate adb', () async {
        when(() => androidSdk.adbPath).thenReturn(null);
        await expectLater(
          () => runWithOverrides(() => adb.startApp(package: package)),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception()',
              contains('Unable to locate adb'),
            ),
          ),
        );
      });

      test('throws process exits with non-zero exit code', () async {
        when(
          () => process.run(any(), any()),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'oops',
          ),
        );
        await expectLater(
          () => runWithOverrides(() => adb.startApp(package: package)),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception()',
              contains('Unable to start app: oops'),
            ),
          ),
        );
      });

      test('completes when process exits with 0', () async {
        await expectLater(
          runWithOverrides(() => adb.startApp(package: package)),
          completes,
        );
        verify(
          () => process.run(adbPath, 'shell monkey -p $package 1'.split(' ')),
        ).called(1);
      });

      test('forwards deviceId when provided', () async {
        const deviceId = '1234';
        await expectLater(
          runWithOverrides(
            () => adb.startApp(package: package, deviceId: deviceId),
          ),
          completes,
        );
        verify(
          () => process.run(
            adbPath,
            '-s $deviceId shell monkey -p $package 1'.split(' '),
          ),
        ).called(1);
      });
    });

    group('logcat', () {
      test('throws when unable to locate adb', () async {
        when(() => androidSdk.adbPath).thenReturn(null);
        await expectLater(
          () => runWithOverrides(() => adb.logcat()),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception()',
              contains('Unable to locate adb'),
            ),
          ),
        );
      });

      test('returns correct process (unfiltered)', () async {
        final Process logcatProcess = _MockProcess();
        when(() => process.start(any(), any())).thenAnswer((invocation) async {
          final executable = invocation.positionalArguments[0] as String;
          if (executable == adbPath) return logcatProcess;
          fail('Unexpected executable: $executable');
        });
        final result = await runWithOverrides(() => adb.logcat());
        expect(result, equals(logcatProcess));
        verify(() => process.start(adbPath, ['logcat'])).called(1);
      });

      test('returns correct process (filtered)', () async {
        const filter = 'flutter';
        final logcatProcess = _MockProcess();
        const logcatStdout = Stream<List<int>>.empty();

        when(
          () => logcatProcess.stdout,
        ).thenAnswer((_) => logcatStdout);
        when(() => process.start(any(), any())).thenAnswer((invocation) async {
          final executable = invocation.positionalArguments[0] as String;
          if (executable == adbPath) return logcatProcess;
          fail('Unexpected executable: $executable');
        });
        final result = await runWithOverrides(() => adb.logcat(filter: filter));
        expect(result, equals(logcatProcess));
        verify(
          () => process.start(adbPath, ['logcat', '-s', filter]),
        ).called(1);
      });

      test('forwards device-id if provided', () async {
        const deviceId = '1234';
        final Process logcatProcess = _MockProcess();
        when(() => process.start(any(), any())).thenAnswer((invocation) async {
          final executable = invocation.positionalArguments[0] as String;
          if (executable == adbPath) return logcatProcess;
          fail('Unexpected executable: $executable');
        });
        await runWithOverrides(() => adb.logcat(deviceId: deviceId));
        verify(() => process.start(adbPath, ['-s', deviceId, 'logcat']))
            .called(1);
      });
    });
  });
}
