import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('ShorebirdTools', () {
    late File dartBinaryFile;
    late Directory flutterDirectory;
    late Directory tempDir;
    late ShorebirdTools shorebirdTools;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess process;
    late ShorebirdProcessResult processResult;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          processRef.overrideWith(() => process),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();

      flutterDirectory = Directory(p.join(tempDir.path, 'flutter'))
        ..createSync();

      dartBinaryFile = File(p.join(tempDir.path, 'dart'))..createSync();

      shorebirdTools = ShorebirdTools();
      processResult = MockProcessResult();
      when(() => processResult.exitCode).thenReturn(0);
      when(() => processResult.stdout).thenReturn('');
      when(() => processResult.stderr).thenReturn('');

      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => shorebirdEnv.dartBinaryFile).thenReturn(dartBinaryFile);

      process = MockShorebirdProcess();
      when(
        () => process.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => processResult);

      logger = MockShorebirdLogger();
    });

    test('have access a reference to shorebird tool', () {
      expect(
        runScoped(() => shorebirdTools, values: {shorebirdToolsRef}),
        isA<ShorebirdTools>(),
      );
    });

    test('makes the correct cli call', () async {
      await runWithOverrides(
        () => shorebirdTools.package(
          patchPath: 'patchPath',
          outputPath: 'outputPath',
        ),
      );

      verify(
        () => process.run(
          dartBinaryFile.path,
          any(
            that: containsAllInOrder(
              [
                'run',
                'shorebird_tools',
                'package',
                '-p',
                'patchPath',
                '-o',
                'outputPath',
              ],
            ),
          ),
          workingDirectory: p.join(
            flutterDirectory.path,
            'packages',
            'shorebird_tools',
          ),
        ),
      ).called(1);
    });

    group('when the command fails for some reason', () {
      setUp(() {
        when(() => processResult.exitCode).thenReturn(1);
        when(() => processResult.stdout).thenReturn('stdout');
        when(() => processResult.stderr).thenReturn('stderr');
      });

      test('throws a PackageFailedException', () {
        expect(
          () => runWithOverrides(
            () => shorebirdTools.package(
              patchPath: 'patchPath',
              outputPath: 'outputPath',
            ),
          ),
          throwsA(
            isA<PackageFailedException>().having(
              (e) => e.message,
              'message',
              '''
Failed to create package (exit code ${processResult.exitCode}).
  stdout: ${processResult.stdout}
  stderr: ${processResult.stderr}''',
            ),
          ),
        );
      });
    });

    group('when the shorebird tools directory exists', () {
      test('isSupported return true', () {
        Directory(p.join(flutterDirectory.path, 'packages', 'shorebird_tools'))
            .createSync(recursive: true);
        final isSupported = runWithOverrides(
          () => shorebirdTools.isSupported(),
        );
        expect(isSupported, isTrue);
      });
    });

    group('when the shorebird tools directory doest not exists', () {
      test('isSupported return true', () {
        final isSupported = runWithOverrides(
          () => shorebirdTools.isSupported(),
        );
        expect(isSupported, isFalse);
      });
    });
  });
}