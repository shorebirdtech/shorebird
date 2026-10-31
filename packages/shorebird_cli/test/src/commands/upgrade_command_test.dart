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
      platform = TestNativePlatform(operatingSystem: NativePlatform.macOS);
      shorebirdEnv = MockShorebirdEnv();
      process = MockShorebirdProcess();
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
      verifyNever(() => process.stream(any(), any()));
    });

    group('on Windows', () {
      final shorebirdRoot = Directory('shorebird');
      final launcher = p.join(shorebirdRoot.path, 'bin', 'shorebird.bat');

      setUp(() {
        platform = TestNativePlatform(operatingSystem: NativePlatform.windows);
        when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      });

      test('sets up the new version after updating', () async {
        when(
          () => process.stream(launcher, ['--version']),
        ).thenAnswer((_) async => ExitCode.success.code);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verifyInOrder([
          () => shorebirdVersion.attemptReset(revision: newerShorebirdRevision),
          () => process.stream(launcher, ['--version']),
        ]);
      });

      test('fails when setting up the new version fails', () async {
        when(
          () => process.stream(launcher, ['--version']),
        ).thenAnswer((_) async => 1);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.software.code));
        verify(
          () => logger.err(
            'Setting up the new version failed (exit code 1). '
            'Run `shorebird --version` to try again.',
          ),
        ).called(1);
      });

      test('does not set up anything when already up to date', () async {
        when(
          shorebirdVersion.fetchLatestGitHash,
        ).thenAnswer((_) async => currentShorebirdRevision);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verifyNever(() => process.stream(any(), any()));
      });
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
    });
  });
}
