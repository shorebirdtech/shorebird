import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ProcessResult {}

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group('doctor', () {
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

    test('prints "no issues" when everything is OK', () async {
      await command.run();
      verify(
        () => logger.info(captureAny(that: contains('No issues detected'))),
      ).called(1);
    });

    test('prints that an upgrade is available', () async {
      when(
        () => fetchLatestVersionResult.stdout,
      ).thenReturn(newerShorebirdRevision);

      await command.run();
      verify(
        () => logger.info(
          captureAny(
            that: contains('A new version of shorebird is available!'),
          ),
        ),
      ).called(1);
    });
  });
}
