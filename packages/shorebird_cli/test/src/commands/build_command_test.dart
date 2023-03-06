import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ProcessResult {}

void main() {
  group('build', () {
    const session = Session(
      apiKey: 'test-api-key',
      projectId: 'test-project-id',
    );

    late Auth auth;
    late Logger logger;
    late ProcessResult processResult;
    late BuildCommand buildCommand;

    setUp(() {
      auth = _MockAuth();
      logger = _MockLogger();
      processResult = _MockProcessResult();
      buildCommand = BuildCommand(
        auth: auth,
        logger: logger,
        runProcess: (executable, arguments, {bool runInShell = false}) async {
          return processResult;
        },
      );

      when(() => logger.progress(any())).thenReturn(_MockProgress());
    });

    test('exits with no user when not logged in', () async {
      when(() => auth.currentSession).thenReturn(null);

      final result = await buildCommand.run();
      expect(result, equals(ExitCode.noUser.code));

      verify(() => logger.err('You must be logged in to build.')).called(1);
      verify(
        () => logger.err("Run 'shorebird login' to log in and try again."),
      ).called(1);
    });

    test('exits with code 70 when engine is not found', () async {
      when(() => auth.currentSession).thenReturn(session);

      final result = await buildCommand.run();
      expect(result, equals(ExitCode.software.code));

      verify(
        () => logger.err(
          'Shorebird engine not found. Run `shorebird run` to download it.',
        ),
      ).called(1);
    });

    test('exits with code 70 when building fails', () async {
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn('oops');
      final tempDir = Directory.systemTemp.createTempSync();
      Directory('${tempDir.path}/.shorebird/engine')
          .createSync(recursive: true);
      when(() => auth.currentSession).thenReturn(session);

      final result = await IOOverrides.runZoned(
        () async => buildCommand.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.software.code));
    });

    test('exits with code 0 when building succeeds', () async {
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      Directory('${tempDir.path}/.shorebird/engine')
          .createSync(recursive: true);
      when(() => auth.currentSession).thenReturn(session);

      final result = await IOOverrides.runZoned(
        () async => buildCommand.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));
    });
  });
}
