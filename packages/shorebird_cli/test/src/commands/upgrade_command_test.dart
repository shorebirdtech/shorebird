import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('upgrade', () {
    late Logger logger;
    late ShorebirdVersion shorebirdVersion;
    late UpgradeCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          shorebirdVersionRef.overrideWith(() => shorebirdVersion),
        },
      );
    }

    setUp(() {
      final progress = MockProgress();
      final progressLogs = <String>[];

      logger = MockLogger();
      shorebirdVersion = MockShorebirdVersion();
      command = runWithOverrides(UpgradeCommand.new);

      when(
        shorebirdVersion.fetchCurrentGitHash,
      ).thenAnswer((_) async => currentShorebirdRevision);
      when(
        shorebirdVersion.fetchLatestGitHash,
      ).thenAnswer((_) async => newerShorebirdRevision);
      when(
        () => shorebirdVersion.attemptReset(revision: any(named: 'revision')),
      ).thenAnswer((_) async => {});

      when(() => progress.complete(any())).thenAnswer((_) {
        final message = _.positionalArguments.elementAt(0) as String?;
        if (message != null) progressLogs.add(message);
      });
      when(() => logger.progress(any())).thenReturn(progress);
    });

    test('can be instantiated', () {
      final command = UpgradeCommand();
      expect(command, isNotNull);
    });

    test(
      'handles errors when determining the current version',
      () async {
        const errorMessage = 'oops';
        when(shorebirdVersion.fetchCurrentGitHash).thenThrow(
          const ProcessException(
            'git',
            ['rev-parse'],
            errorMessage,
          ),
        );

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.software.code));
        verify(() => logger.progress('Checking for updates')).called(1);
        verify(
          () => logger.err('Fetching current version failed: $errorMessage'),
        ).called(1);
      },
    );

    test(
      'handles errors when determining the latest version',
      () async {
        const errorMessage = 'oops';
        when(shorebirdVersion.fetchLatestGitHash).thenThrow(
          const ProcessException(
            'git',
            ['rev-parse'],
            errorMessage,
          ),
        );

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.software.code));
        verify(() => logger.progress('Checking for updates')).called(1);
        verify(() => logger.err('Checking for updates failed: oops')).called(1);
      },
    );

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

    test(
      'updates when newer version exists',
      () async {
        when(() => logger.progress(any())).thenReturn(MockProgress());

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(() => logger.progress('Checking for updates')).called(1);
        verify(() => logger.progress('Updating')).called(1);
      },
    );

    test(
      'does not update when already on latest version',
      () async {
        when(shorebirdVersion.fetchLatestGitHash)
            .thenAnswer((_) async => currentShorebirdRevision);
        when(() => logger.progress(any())).thenReturn(MockProgress());

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info('Shorebird is already at the latest version.'),
        ).called(1);
      },
    );
  });
}
