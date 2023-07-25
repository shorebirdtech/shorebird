import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/ios_deploy.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(IOSDeploy, () {
    late Logger logger;
    late Platform platform;
    late Progress progress;
    late ShorebirdProcess process;
    late IOSDeploy iosDeploy;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      logger = _MockLogger();
      platform = _MockPlatform();
      process = _MockShorebirdProcess();
      progress = _MockProgress();
      iosDeploy = IOSDeploy();

      final tempDir = Directory.systemTemp.createTempSync();

      final shorebirdScriptFile = File(
        p.join(tempDir.path, 'bin', 'cache', 'shorebird.snapshot'),
      )..create(recursive: true);
      when(() => platform.script).thenReturn(shorebirdScriptFile.uri);

      when(() => logger.progress(any())).thenReturn(progress);
    });

    group('installAndLaunchApp', () {
      test('executes correct command when deviceId is provided', () async {
        const processResult = ShorebirdProcessResult(
          exitCode: 0,
          stdout: '',
          stderr: '',
        );
        when(
          () => process.run(any(), any()),
        ).thenAnswer((_) async => processResult);
        const deviceId = 'test-device-id';
        const bundlePath = 'test-bundle-path';
        final result = await runWithOverrides(
          () => iosDeploy.installAndLaunchApp(
            deviceId: deviceId,
            bundlePath: bundlePath,
          ),
        );
        expect(result, equals(processResult.exitCode));
        verify(
          () => process.run(any(that: endsWith('ios-deploy')), [
            '--debug',
            '--id',
            deviceId,
            '--bundle',
            bundlePath,
          ]),
        ).called(1);
      });

      test('executes correct command when deviceId is not provided', () async {
        const processResult = ShorebirdProcessResult(
          exitCode: 0,
          stdout: '',
          stderr: '',
        );
        when(
          () => process.run(any(), any()),
        ).thenAnswer((_) async => processResult);
        const bundlePath = 'test-bundle-path';
        final result = await runWithOverrides(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: bundlePath,
          ),
        );
        expect(result, equals(processResult.exitCode));
        verify(
          () => process.run(any(that: endsWith('ios-deploy')), [
            '--debug',
            '--bundle',
            bundlePath,
          ]),
        ).called(1);
      });
    });

    group('installIfNeeded', () {
      test('does nothing if ios-deploy is already installed', () async {
        runWithOverrides(
          () => IOSDeploy.iosDeployExecutable.createSync(recursive: true),
        );
        await expectLater(
          runWithOverrides(() async => iosDeploy.installIfNeeded()),
          completes,
        );

        verifyNever(() => process.run(any(), any()));
      });

      test('throws ProcessException if flutter precache fails', () async {
        when(() => process.run(any(), any())).thenAnswer(
          (_) async => ShorebirdProcessResult(
            exitCode: ExitCode.software.code,
            stdout: null,
            stderr: 'oh no',
          ),
        );

        await expectLater(
          runWithOverrides(iosDeploy.installIfNeeded),
          throwsA(
            isA<ProcessException>(),
          ),
        );
      });

      test(
        '''throws Exception if ios-deploy is not installed after running flutter precache''',
        () async {
          when(() => process.run(any(), any())).thenAnswer(
            (_) async => ShorebirdProcessResult(
              exitCode: ExitCode.success.code,
              stdout: null,
              stderr: null,
            ),
          );
          await expectLater(
            runWithOverrides(iosDeploy.installIfNeeded),
            throwsA(
              isA<Exception>(),
            ),
          );
        },
      );

      test(
          '''completes successfully if ios-deploy is installed after running flutter precache''',
          () async {
        when(() => process.run(any(), any())).thenAnswer(
          (_) async {
            runWithOverrides(
              () => IOSDeploy.iosDeployExecutable.createSync(recursive: true),
            );
            return ShorebirdProcessResult(
              exitCode: ExitCode.success.code,
              stdout: null,
              stderr: null,
            );
          },
        );
        await expectLater(
          runWithOverrides(() async => iosDeploy.installIfNeeded()),
          completes,
        );

        verify(() => process.run('flutter', ['precache', '--ios'])).called(1);
        verify(progress.complete).called(1);
      });
    });
  });
}
