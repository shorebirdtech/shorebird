import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('upgrade', () {
    late ShorebirdLogger logger;
    late TestNativePlatform platform;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess process;
    late ShorebirdVersion shorebirdVersion;
    late String newShorebird;
    late UpgradeCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdVersionRef.overrideWith(() => shorebirdVersion),
        },
      );
    }

    setUp(() {
      final progress = MockProgress();
      final progressLogs = <String>[];

      logger = MockShorebirdLogger();
      platform = TestNativePlatform(
        environment: {},
        operatingSystem: NativePlatform.macOS,
      );
      process = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdVersion = MockShorebirdVersion();
      command = runWithOverrides(UpgradeCommand.new);

      when(
        shorebirdVersion.fetchCurrentGitHash,
      ).thenAnswer((_) async => currentShorebirdRevision);
      when(shorebirdVersion.hasUpstream).thenAnswer((_) async => true);
      when(
        shorebirdVersion.fetchLatestGitHash,
      ).thenAnswer((_) async => newerShorebirdRevision);
      when(
        () => shorebirdVersion.attemptReset(revision: any(named: 'revision')),
      ).thenAnswer((_) async => {});
      final shorebirdRoot = Directory(
        p.join(Directory.current.path, 'shorebird_root'),
      );
      newShorebird = p.join(shorebirdRoot.path, 'bin', 'shorebird');
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(() => process.stream(any(), any())).thenAnswer((_) async => 0);

      when(() => progress.complete(any())).thenAnswer((invocation) {
        final message = invocation.positionalArguments.elementAt(0) as String?;
        if (message != null) progressLogs.add(message);
      });
      when(() => logger.progress(any())).thenReturn(progress);
    });

    test('can be instantiated', () {
      final command = UpgradeCommand();
      expect(command, isNotNull);
    });

    test('handles errors when determining the current version', () async {
      const errorMessage = 'oops';
      when(
        shorebirdVersion.fetchCurrentGitHash,
      ).thenThrow(const ProcessException('git', ['rev-parse'], errorMessage));

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(
        () => logger.err('Fetching current version failed: $errorMessage'),
      ).called(1);
    });

    test('handles errors when determining the latest version', () async {
      const errorMessage = 'oops';
      when(
        shorebirdVersion.fetchLatestGitHash,
      ).thenThrow(const ProcessException('git', ['rev-parse'], errorMessage));

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.err('Checking for updates failed: oops')).called(1);
    });

    test('explains how to get updates when there is no upstream', () async {
      const message = 'Shorebird is not on a branch that receives updates.';
      when(shorebirdVersion.hasUpstream).thenAnswer((_) async => false);
      when(() => shorebirdVersion.noUpstreamMessage).thenReturn(message);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.err(message)).called(1);
      verifyNever(shorebirdVersion.fetchLatestGitHash);
      verifyNever(
        () => shorebirdVersion.attemptReset(revision: any(named: 'revision')),
      );
    });

    test('handles errors when updating', () async {
      const errorMessage = 'oops';
      when(
        () => shorebirdVersion.attemptReset(revision: any(named: 'revision')),
      ).thenThrow(const ProcessException('git', ['reset'], errorMessage));

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.err('Updating failed: oops')).called(1);
    });

    test('updates when newer version exists', () async {
      when(() => logger.progress(any())).thenReturn(MockProgress());

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.progress('Updating')).called(1);
      verify(() => process.stream(newShorebird, ['--version'])).called(1);
    });

    test('fails when setting up the new version fails', () async {
      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => process.stream(any(), any())).thenAnswer((_) async => 70);

      final result = await runWithOverrides(command.run);

      expect(result, equals(70));
      verify(
        () => logger.err(
          'Setting up the new version failed (exit code 70). '
          'The next shorebird command will try again.',
        ),
      ).called(1);
    });

    test('runs bin/shorebird.bat on Windows', () async {
      platform = platform.copyWith(operatingSystem: NativePlatform.windows);
      when(() => logger.progress(any())).thenReturn(MockProgress());

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => process.stream(
          p.join(p.dirname(newShorebird), 'shorebird.bat'),
          ['--version'],
        ),
      ).called(1);
    });

    test('does not update when already on latest version', () async {
      when(
        shorebirdVersion.fetchLatestGitHash,
      ).thenAnswer((_) async => currentShorebirdRevision);
      when(() => logger.progress(any())).thenReturn(MockProgress());

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info('Shorebird is already at the latest version.'),
      ).called(1);
      verifyNever(() => process.stream(any(), any()));
    });
  });
}
