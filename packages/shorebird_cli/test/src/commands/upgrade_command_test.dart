import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('upgrade', () {
    late Logger logger;
    late ShorebirdProcessResult fetchCurrentVersionResult;
    late ShorebirdProcessResult fetchTagsResult;
    late ShorebirdProcessResult fetchLatestVersionResult;
    late ShorebirdProcessResult hardResetResult;
    late ShorebirdProcessResult pruneFlutterOriginResult;
    late ShorebirdProcess shorebirdProcess;
    late UpgradeCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
        },
      );
    }

    setUp(() {
      final progress = _MockProgress();
      final progressLogs = <String>[];

      logger = _MockLogger();
      fetchCurrentVersionResult = _MockProcessResult();
      fetchTagsResult = _MockProcessResult();
      fetchLatestVersionResult = _MockProcessResult();
      hardResetResult = _MockProcessResult();
      pruneFlutterOriginResult = _MockProcessResult();
      shorebirdProcess = _MockShorebirdProcess();
      command = runWithOverrides(UpgradeCommand.new);

      when(
        () => shorebirdProcess.run(
          'git',
          ['rev-parse', '--verify', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => fetchCurrentVersionResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['fetch', '--tags'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => fetchTagsResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['rev-parse', '--verify', '@{upstream}'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => fetchLatestVersionResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['reset', '--hard', newerShorebirdRevision],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => hardResetResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['remote', 'prune', 'origin'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => pruneFlutterOriginResult);

      when(
        () => fetchCurrentVersionResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => fetchCurrentVersionResult.stdout,
      ).thenReturn(currentShorebirdRevision);
      when(
        () => fetchLatestVersionResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => pruneFlutterOriginResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => fetchLatestVersionResult.stdout,
      ).thenReturn(currentShorebirdRevision);
      when(() => hardResetResult.exitCode).thenReturn(ExitCode.success.code);
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
        when(() => fetchCurrentVersionResult.exitCode).thenReturn(1);
        when(() => fetchCurrentVersionResult.stderr).thenReturn(errorMessage);
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
        when(() => fetchLatestVersionResult.exitCode).thenReturn(1);
        when(() => fetchLatestVersionResult.stderr).thenReturn(errorMessage);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => logger.progress('Checking for updates')).called(1);
        verify(() => logger.err('Checking for updates failed: oops')).called(1);
      },
    );

    test(
      'handles errors when updating',
      () async {
        const errorMessage = 'oops';
        when(
          () => fetchLatestVersionResult.stdout,
        ).thenReturn(newerShorebirdRevision);
        when(() => hardResetResult.exitCode).thenReturn(1);
        when(() => hardResetResult.stderr).thenReturn(errorMessage);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => logger.progress('Checking for updates')).called(1);
        verify(() => logger.err('Updating failed: oops')).called(1);
      },
    );

    test('handles errors on failure to prune Flutter branches', () async {
      when(
        () => fetchLatestVersionResult.stdout,
      ).thenReturn(newerShorebirdRevision);
      when(() => pruneFlutterOriginResult.exitCode).thenReturn(1);
      when(() => logger.progress(any())).thenReturn(_MockProgress());

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
    });

    test(
      'updates when newer version exists',
      () async {
        when(
          () => fetchLatestVersionResult.stdout,
        ).thenReturn(newerShorebirdRevision);
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
