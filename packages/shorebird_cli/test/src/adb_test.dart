import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/adb.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

class _MockAndroidSdk extends Mock implements AndroidSdk {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

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
          () => runWithOverrides(() => adb.startApp(package)),
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
          () => runWithOverrides(() => adb.startApp(package)),
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
          runWithOverrides(() => adb.startApp(package)),
          completes,
        );
        verify(
          () => process.run(adbPath, 'shell monkey -p $package 1'.split(' ')),
        ).called(1);
      });
    });
  });
}
