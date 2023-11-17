import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(StorageAccessValidator, () {
    late Platform platform;
    late ShorebirdProcess process;
    late ShorebirdProcessResult pingProcessResult;
    late StorageAccessValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      platform = MockPlatform();
      process = MockShorebirdProcess();
      pingProcessResult = MockShorebirdProcessResult();
      validator = StorageAccessValidator();

      when(() => process.run('ping', any())).thenAnswer(
        (_) async => pingProcessResult,
      );
      when(() => platform.isWindows).thenReturn(false);
    });

    group('validate', () {
      group('when storage url is accessible', () {
        setUp(() {
          when(() => pingProcessResult.exitCode)
              .thenReturn(ExitCode.success.code);
        });

        test('returns empty list of validation issues', () async {
          final results = await runWithOverrides(validator.validate);
          expect(results, isEmpty);
        });
      });

      group('when storage url is inaccessible', () {
        setUp(() {
          when(() => pingProcessResult.exitCode)
              .thenReturn(ExitCode.software.code);
        });

        test('returns validation error', () async {
          final results = await runWithOverrides(validator.validate);
          expect(
            results,
            equals(
              [
                const ValidationIssue(
                  severity: ValidationIssueSeverity.error,
                  message: 'Unable to access storage.googleapis.com',
                ),
              ],
            ),
          );
        });
      });

      group('when run on Windows', () {
        setUp(() {
          when(() => pingProcessResult.exitCode)
              .thenReturn(ExitCode.success.code);
          when(() => platform.isWindows).thenReturn(true);
        });

        test('does not provide count argument', () async {
          await runWithOverrides(validator.validate);
          verify(
            () => process.run(
              'ping',
              ['https://storage.googleapis.com'],
            ),
          ).called(1);
        });
      });

      group('when run on non-Windows OS', () {
        setUp(() {
          when(() => pingProcessResult.exitCode)
              .thenReturn(ExitCode.success.code);
          when(() => platform.isWindows).thenReturn(false);
        });

        test('provides count argument', () async {
          await runWithOverrides(validator.validate);
          verify(
            () => process.run(
              'ping',
              ['-c', '2', 'https://storage.googleapis.com'],
            ),
          ).called(1);
        });
      });
    });
  });
}
