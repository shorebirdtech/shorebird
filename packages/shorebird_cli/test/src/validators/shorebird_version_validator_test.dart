import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/doctor_command.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('ShorebirdVersionValidator', () {
    late ShorebirdVersionValidator validator;
    late Logger logger;
    late DoctorCommand command;
    late ProcessResult fetchCurrentVersionResult;
    late ProcessResult fetchLatestVersionResult;
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      logger = _MockLogger();
      fetchCurrentVersionResult = _MockProcessResult();
      fetchLatestVersionResult = _MockProcessResult();
      shorebirdProcess = _MockShorebirdProcess();

      command = DoctorCommand(
        logger: logger,
        process: shorebirdProcess,
      );

      validator = ShorebirdVersionValidator(
        isShorebirdVersionCurrent: command.isShorebirdVersionCurrent,
      );

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
          ['rev-parse', '--verify', '@{upstream}'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => fetchLatestVersionResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['fetch', '--tags'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => _MockProcessResult());

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
        () => fetchLatestVersionResult.stdout,
      ).thenReturn(currentShorebirdRevision);
    });

    test('returns no issues when shorebird is up-to-date', () async {
      final results = await validator.validate();
      expect(results, isEmpty);
    });

    test('returns a warning when a newer shorebird is available', () async {
      when(
        () => fetchLatestVersionResult.stdout,
      ).thenReturn(newerShorebirdRevision);

      final results = await validator.validate();
      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(
        results.first.message,
        contains('A new version of shorebird is available!'),
      );
    });

    test(
      'returns an error on failure to retrieve shorebird version',
      () async {
        when(
          () => fetchLatestVersionResult.stdout,
        ).thenThrow(
          const ProcessException(
            'git',
            ['--rev'],
            'Some error',
          ),
        );

        final results = await validator.validate();

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.error);
        expect(
          results.first.message,
          'Failed to get shorebird version. Error: Some error',
        );
      },
    );
  });
}
