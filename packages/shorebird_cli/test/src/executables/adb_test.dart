import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
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
      androidSdk = MockAndroidSdk();
      process = MockShorebirdProcess();
      adb = Adb();

      when(() => androidSdk.adbPath).thenReturn(adbPath);
      when(() => process.run(any(), any())).thenAnswer(
        (_) async =>
            const ShorebirdProcessResult(exitCode: 0, stdout: '', stderr: ''),
      );
    });

    group('uninstallApp', () {
      const package = 'com.example.app';
      const listArgs = ['shell', 'pm', 'list', 'packages', package];
      const uninstallArgs = ['uninstall', package];

      void stubList({
        int exitCode = 0,
        String stdout = '',
        String stderr = '',
      }) {
        when(() => process.run(adbPath, listArgs)).thenAnswer(
          (_) async => ShorebirdProcessResult(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
          ),
        );
      }

      test('throws when unable to locate adb', () async {
        when(() => androidSdk.adbPath).thenReturn(null);
        await expectLater(
          () => runWithOverrides(() => adb.uninstallApp(package: package)),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception()',
              contains('Unable to locate adb'),
            ),
          ),
        );
      });

      test('throws when listing packages fails', () async {
        stubList(exitCode: 1, stderr: 'oops');
        await expectLater(
          () => runWithOverrides(() => adb.uninstallApp(package: package)),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception()',
              contains('Unable to list installed packages: oops'),
            ),
          ),
        );
      });

      test('does not uninstall when the package is not installed', () async {
        // `pm list packages` matches substrings.
        stubList(stdout: 'package:$package.other\n');
        await expectLater(
          runWithOverrides(() => adb.uninstallApp(package: package)),
          completes,
        );
        verifyNever(() => process.run(adbPath, uninstallArgs));
      });

      test('uninstalls when the package is installed', () async {
        stubList(stdout: 'package:$package.other\npackage:$package\n');
        await expectLater(
          runWithOverrides(() => adb.uninstallApp(package: package)),
          completes,
        );
        verify(() => process.run(adbPath, uninstallArgs)).called(1);
      });

      test('throws when uninstall exits with non-zero exit code', () async {
        stubList(stdout: 'package:$package\n');
        when(() => process.run(adbPath, uninstallArgs)).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'oops',
          ),
        );
        await expectLater(
          () => runWithOverrides(() => adb.uninstallApp(package: package)),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception()',
              contains('Unable to uninstall app: oops'),
            ),
          ),
        );
      });

      test('throws when uninstall reports failure with exit code 0', () async {
        stubList(stdout: 'package:$package\n');
        when(() => process.run(adbPath, uninstallArgs)).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: 'Failure [DELETE_FAILED_INTERNAL_ERROR]\n',
            stderr: '',
          ),
        );
        await expectLater(
          () => runWithOverrides(() => adb.uninstallApp(package: package)),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception()',
              contains(
                'Unable to uninstall app: Failure [DELETE_FAILED_INTERNAL_ERROR]',
              ),
            ),
          ),
        );
      });

      test('forwards deviceId when provided', () async {
        const deviceId = '1234';
        when(
          () => process.run(adbPath, ['-s', deviceId, ...listArgs]),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: 'package:$package\n',
            stderr: '',
          ),
        );
        await expectLater(
          runWithOverrides(
            () => adb.uninstallApp(package: package, deviceId: deviceId),
          ),
          completes,
        );
        verify(
          () => process.run(adbPath, ['-s', deviceId, ...uninstallArgs]),
        ).called(1);
      });
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
        when(() => process.run(any(), any())).thenAnswer(
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
          () => process.run(
            adbPath,
            'shell monkey --pct-syskeys 0 -p $package 1'.split(' '),
          ),
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
            '-s $deviceId shell monkey --pct-syskeys 0 -p $package 1'.split(
              ' ',
            ),
          ),
        ).called(1);
      });
    });

    group('latestLogTimestamp', () {
      test('throws when unable to locate adb', () async {
        when(() => androidSdk.adbPath).thenReturn(null);
        await expectLater(
          () => runWithOverrides(() => adb.latestLogTimestamp()),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception()',
              contains('Unable to locate adb'),
            ),
          ),
        );
      });

      test('returns null when the log cannot be read', () async {
        when(() => process.run(any(), any())).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'oops',
          ),
        );
        await expectLater(
          runWithOverrides(() => adb.latestLogTimestamp()),
          completion(isNull),
        );
      });

      test('returns the timestamp of the newest entry', () async {
        when(() => process.run(any(), any())).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout:
                '--------- beginning of main\n'
                '10-24 12:56:32.517 I/flutter ( 5830): hello\n',
            stderr: '',
          ),
        );
        await expectLater(
          runWithOverrides(() => adb.latestLogTimestamp()),
          completion(equals('10-24 12:56:32.517')),
        );
        verify(
          () => process.run(adbPath, [
            'logcat',
            '-d',
            '-t',
            '1',
            '-v',
            'time',
          ]),
        ).called(1);
      });

      test('returns null when the log is empty', () async {
        await expectLater(
          runWithOverrides(() => adb.latestLogTimestamp()),
          completion(isNull),
        );
      });

      test('forwards deviceId when provided', () async {
        const deviceId = '1234';
        await runWithOverrides(
          () => adb.latestLogTimestamp(deviceId: deviceId),
        );
        verify(
          () => process.run(adbPath, [
            '-s',
            deviceId,
            'logcat',
            '-d',
            '-t',
            '1',
            '-v',
            'time',
          ]),
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
        final Process logcatProcess = MockProcess();
        when(() => process.start(any(), any())).thenAnswer((invocation) async {
          final executable = invocation.positionalArguments[0] as String;
          if (executable == adbPath) return logcatProcess;
          fail('Unexpected executable: $executable');
        });
        final result = await runWithOverrides(() => adb.logcat());
        expect(result, equals(logcatProcess));
        verify(() => process.start(adbPath, ['logcat', '-T', '1'])).called(1);
      });

      test('returns correct process (filtered)', () async {
        const filter = 'flutter';
        final logcatProcess = MockProcess();
        const logcatStdout = Stream<List<int>>.empty();

        when(() => logcatProcess.stdout).thenAnswer((_) => logcatStdout);
        when(() => process.start(any(), any())).thenAnswer((invocation) async {
          final executable = invocation.positionalArguments[0] as String;
          if (executable == adbPath) return logcatProcess;
          fail('Unexpected executable: $executable');
        });
        final result = await runWithOverrides(() => adb.logcat(filter: filter));
        expect(result, equals(logcatProcess));
        verify(
          () => process.start(adbPath, ['logcat', '-T', '1', '-s', filter]),
        ).called(1);
      });

      test('starts from the given timestamp', () async {
        const since = '10-24 12:56:32.517';
        final Process logcatProcess = MockProcess();
        when(
          () => process.start(any(), any()),
        ).thenAnswer((_) async => logcatProcess);
        await runWithOverrides(
          () => adb.logcat(filter: 'flutter', since: since),
        );
        verify(
          () => process.start(adbPath, [
            'logcat',
            '-T',
            since,
            '-s',
            'flutter',
          ]),
        ).called(1);
      });

      test('forwards device-id if provided', () async {
        const deviceId = '1234';
        final Process logcatProcess = MockProcess();
        when(() => process.start(any(), any())).thenAnswer((invocation) async {
          final executable = invocation.positionalArguments[0] as String;
          if (executable == adbPath) return logcatProcess;
          fail('Unexpected executable: $executable');
        });
        await runWithOverrides(() => adb.logcat(deviceId: deviceId));
        verify(
          () => process.start(adbPath, ['-s', deviceId, 'logcat', '-T', '1']),
        ).called(1);
      });
    });
  });
}
