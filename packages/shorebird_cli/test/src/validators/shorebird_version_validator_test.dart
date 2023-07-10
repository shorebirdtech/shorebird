import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/doctor_command.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('ShorebirdVersionValidator', () {
    late ShorebirdVersionValidator validator;
    late ShorebirdProcessResult fetchCurrentVersionResult;
    late ShorebirdProcessResult fetchLatestVersionResult;
    late ShorebirdProcess shorebirdProcess;
    late DoctorCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          processRef.overrideWith(() => shorebirdProcess),
        },
      );
    }

    setUp(() {
      fetchCurrentVersionResult = _MockProcessResult();
      fetchLatestVersionResult = _MockProcessResult();
      shorebirdProcess = _MockShorebirdProcess();

      command = runWithOverrides(DoctorCommand.new);

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

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    test('is not project-specific', () {
      expect(validator.scope, ValidatorScope.installation);
    });

    test('returns no issues when shorebird is up-to-date', () async {
      final results = await runWithOverrides(
        () => validator.validate(shorebirdProcess),
      );
      expect(results, isEmpty);
    });

    test('returns a warning when a newer shorebird is available', () async {
      when(
        () => fetchLatestVersionResult.stdout,
      ).thenReturn(newerShorebirdRevision);

      final results = await runWithOverrides(
        () => validator.validate(shorebirdProcess),
      );
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

        final results = await runWithOverrides(
          () => validator.validate(shorebirdProcess),
        );

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
