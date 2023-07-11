import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/bundle_tool.dart';
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
            '-jar ${p.join(workingDirectory.path, 'bundletool.jar')} dump manifest --bundle $appBundlePath --xpath /manifest/@android:versionName'
                .split(' '),
            environment: {},
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
            '-jar ${p.join(workingDirectory.path, 'bundletool.jar')} dump manifest --bundle $appBundlePath --xpath /manifest/@android:versionCode'
                .split(' '),
            environment: {},
          ),
        ).called(1);
      });
    });
  });
}
