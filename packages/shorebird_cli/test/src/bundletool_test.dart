import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/bundletool.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

class _MockCache extends Mock implements Cache {}

class _MockJava extends Mock implements Java {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(Bundletool, () {
    const appBundlePath = 'test-app-bundle.aab';
    const javaHome = 'test-java-home';

    late Directory workingDirectory;
    late Cache cache;
    late Java java;
    late ShorebirdProcess process;
    late Bundletool bundletool;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          javaRef.overrideWith(() => java),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      workingDirectory = Directory.systemTemp.createTempSync();
      cache = _MockCache();
      java = _MockJava();
      process = _MockShorebirdProcess();
      bundletool = Bundletool();

      when(() => cache.updateAll()).thenAnswer((_) async {});
      when(
        () => cache.getArtifactDirectory(any()),
      ).thenReturn(workingDirectory);
      when(() => java.home).thenReturn(javaHome);
    });

    group('buildApks', () {
      late Directory tempDir;
      late String output;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync();
        output = p.join(tempDir.path, 'output.apks');
      });

      test('throws exception if process returns non-zero exit code', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'oops',
          ),
        );
        await expectLater(
          () => runWithOverrides(
            () => bundletool.buildApks(bundle: appBundlePath, output: output),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception',
              'Exception: Failed to build apks: oops',
            ),
          ),
        );
      });

      test('completes when process succeeds', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
          ),
        );
        await expectLater(
          runWithOverrides(
            () => bundletool.buildApks(bundle: appBundlePath, output: output),
          ),
          completes,
        );
        verify(
          () => process.run(
            'java',
            '''-jar ${p.join(workingDirectory.path, 'bundletool.jar')} build-apks --overwrite --bundle=$appBundlePath --output=$output --mode=universal'''
                .split(' '),
            environment: {
              'JAVA_HOME': javaHome,
            },
          ),
        ).called(1);
      });
    });

    group('installApks', () {
      const apks = 'test.apks';

      test('throws exception if process returns non-zero exit code', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'oops',
          ),
        );
        await expectLater(
          () => runWithOverrides(() => bundletool.installApks(apks: apks)),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception',
              'Exception: Failed to install apks: oops',
            ),
          ),
        );
      });

      test('completes when process succeeds', () async {
        const deviceId = '1234';
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
          ),
        );
        await expectLater(
          runWithOverrides(
            () => bundletool.installApks(apks: apks, deviceId: deviceId),
          ),
          completes,
        );
        verify(
          () => process.run(
            'java',
            '''-jar ${p.join(workingDirectory.path, 'bundletool.jar')} install-apks --apks=$apks --allow-downgrade --device-id=$deviceId'''
                .split(' '),
            environment: {
              'JAVA_HOME': javaHome,
            },
          ),
        ).called(1);
      });

      test('forwards deviceId if provided', () async {});
    });

    group('getPackageName', () {
      test('throws exception if process returns non-zero exit code', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'oops',
          ),
        );
        await expectLater(
          () => runWithOverrides(
            () => bundletool.getPackageName(appBundlePath),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception',
              'Exception: Failed to extract package name from app bundle: oops',
            ),
          ),
        );
      });

      test('returns the correct package name', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: 'com.example.app',
            stderr: '',
          ),
        );

        final versionName = await runWithOverrides(
          () => bundletool.getPackageName(appBundlePath),
        );
        expect(versionName, equals('com.example.app'));
        verify(
          () => process.run(
            'java',
            '-jar ${p.join(workingDirectory.path, 'bundletool.jar')} dump manifest --bundle=$appBundlePath --xpath /manifest/@package'
                .split(' '),
            environment: {
              'JAVA_HOME': javaHome,
            },
          ),
        ).called(1);
      });
    });

    group('getVersionName', () {
      test('throws exception if process returns non-zero exit code', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'oops',
          ),
        );
        await expectLater(
          () => runWithOverrides(
            () => bundletool.getVersionName(appBundlePath),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception',
              'Exception: Failed to extract version name from app bundle: oops',
            ),
          ),
        );
      });

      test('returns the correct version name', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: '1.2.3',
            stderr: '',
          ),
        );

        final versionName = await runWithOverrides(
          () => bundletool.getVersionName(appBundlePath),
        );
        expect(versionName, equals('1.2.3'));
        verify(
          () => process.run(
            'java',
            '-jar ${p.join(workingDirectory.path, 'bundletool.jar')} dump manifest --bundle=$appBundlePath --xpath /manifest/@android:versionName'
                .split(' '),
            environment: {
              'JAVA_HOME': javaHome,
            },
          ),
        ).called(1);
      });
    });

    group('getVersionCode', () {
      test('throws exception if process returns non-zero exit code', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'oops',
          ),
        );
        await expectLater(
          () => runWithOverrides(
            () => bundletool.getVersionCode(appBundlePath),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception',
              'Exception: Failed to extract version code from app bundle: oops',
            ),
          ),
        );
      });

      test('returns the correct version code', () async {
        when(
          () => process.run(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: '42',
            stderr: '',
          ),
        );
        final versionCode = await runWithOverrides(
          () => bundletool.getVersionCode(appBundlePath),
        );
        expect(versionCode, equals('42'));
        verify(
          () => process.run(
            'java',
            '-jar ${p.join(workingDirectory.path, 'bundletool.jar')} dump manifest --bundle=$appBundlePath --xpath /manifest/@android:versionCode'
                .split(' '),
            environment: {
              'JAVA_HOME': javaHome,
            },
          ),
        ).called(1);
      });
    });
  });
}
