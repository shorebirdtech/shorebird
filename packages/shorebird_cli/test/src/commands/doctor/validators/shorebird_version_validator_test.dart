import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/doctor_command.dart';
import 'package:shorebird_cli/src/doctor/doctor_validator.dart';
import 'package:shorebird_cli/src/doctor/validators/shorebird_version_validator.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ProcessResult {}

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('ShorebirdVersionValidator', () {
    late ShorebirdVersionValidator validator;
    late Logger logger;
    late DoctorCommand command;
    late ProcessResult fetchCurrentVersionResult;
    late ProcessResult fetchLatestVersionResult;

    setUp(() {
      logger = _MockLogger();
      fetchCurrentVersionResult = _MockProcessResult();
      fetchLatestVersionResult = _MockProcessResult();

      command = DoctorCommand(
        logger: logger,
        runProcess: (
          executable,
          arguments, {
          bool runInShell = false,
          workingDirectory,
          bool resolveExecutables = true,
        }) async {
          if (executable == 'git') {
            const revParseHead = ['rev-parse', '--verify', 'HEAD'];
            if (arguments.every((arg) => revParseHead.contains(arg))) {
              return fetchCurrentVersionResult;
            }

            const revParseUpstream = ['rev-parse', '--verify', '@{upstream}'];
            if (arguments.every((arg) => revParseUpstream.contains(arg))) {
              return fetchLatestVersionResult;
            }
          }
          return _MockProcessResult();
        },
      );

      validator = ShorebirdVersionValidator(
        isShorebirdVersionCurrent: command.isShorebirdVersionCurrent,
      );

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
  });
}
