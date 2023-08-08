import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_flutter_manager.dart';
import 'package:shorebird_cli/src/shorebird_version_manager.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdFlutterManager extends Mock
    implements ShorebirdFlutterManager {}

class _MockShorebirdVersionManager extends Mock
    implements ShorebirdVersionManager {}

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('upgrade', () {
    late Logger logger;
    late ShorebirdFlutterManager shorebirdFlutterManager;
    late ShorebirdVersionManager shorebirdVersionManager;
    late UpgradeCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          shorebirdFlutterManagerRef.overrideWith(
            () => shorebirdFlutterManager,
          ),
          shorebirdVersionManagerRef.overrideWith(
            () => shorebirdVersionManager,
          ),
        },
      );
    }

    setUp(() {
      final progress = _MockProgress();
      final progressLogs = <String>[];

      logger = _MockLogger();
      shorebirdFlutterManager = _MockShorebirdFlutterManager();
      shorebirdVersionManager = _MockShorebirdVersionManager();
      command = runWithOverrides(UpgradeCommand.new);

      when(
        () => shorebirdFlutterManager.pruneRemoteOrigin(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async {});
      when(
        shorebirdVersionManager.fetchCurrentGitHash,
      ).thenAnswer((_) async => currentShorebirdRevision);
      when(
        shorebirdVersionManager.fetchLatestGitHash,
      ).thenAnswer((_) async => newerShorebirdRevision);
      when(
        () => shorebirdVersionManager.attemptReset(
          newRevision: any(named: 'newRevision'),
        ),
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
        when(shorebirdVersionManager.fetchCurrentGitHash).thenThrow(
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
        when(shorebirdVersionManager.fetchLatestGitHash).thenThrow(
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
        () => shorebirdVersionManager.attemptReset(
          newRevision: any(named: 'newRevision'),
        ),
      ).thenThrow(const ProcessException('git', ['reset'], errorMessage));

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.err('Updating failed: oops')).called(1);
    });

    test('handles errors on failure to prune Flutter branches', () async {
      const exception = ProcessException('git', ['remote', 'prune'], 'oops');
      when(
        () => shorebirdFlutterManager.pruneRemoteOrigin(
          revision: any(named: 'revision'),
        ),
      ).thenThrow(exception);
      when(() => logger.progress(any())).thenReturn(_MockProgress());

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdFlutterManager.pruneRemoteOrigin(
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
        when(shorebirdVersionManager.fetchLatestGitHash)
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
