import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdFlutter extends Mock implements ShorebirdFlutter {}

class _MockShorebirdVersion extends Mock implements ShorebirdVersion {}

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('upgrade', () {
    late Logger logger;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdVersion shorebirdVersion;
    late UpgradeCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdVersionRef.overrideWith(() => shorebirdVersion),
        },
      );
    }

    setUp(() {
      final progress = _MockProgress();
      final progressLogs = <String>[];

      logger = _MockLogger();
      shorebirdFlutter = _MockShorebirdFlutter();
      shorebirdVersion = _MockShorebirdVersion();
      command = runWithOverrides(UpgradeCommand.new);

      when(
        () => shorebirdFlutter.pruneRemoteOrigin(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async {});
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

    test('handles errors on failure to prune Flutter branches', () async {
      const exception = ProcessException('git', ['remote', 'prune'], 'oops');
      when(
        () => shorebirdFlutter.pruneRemoteOrigin(
          revision: any(named: 'revision'),
        ),
      ).thenThrow(exception);
      when(() => logger.progress(any())).thenReturn(_MockProgress());

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdFlutter.pruneRemoteOrigin(
          revision: newerShorebirdRevision,
        ),
      ).called(1);
    });

    test(
      'updates when newer version exists',
      () async {
        when(() => logger.progress(any())).thenReturn(_MockProgress());

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
        when(() => logger.progress(any())).thenReturn(_MockProgress());

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info('Shorebird is already at the latest version.'),
        ).called(1);
      },
    );
  });
}
