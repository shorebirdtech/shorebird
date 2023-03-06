import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/commands/run_command.dart';
import 'package:shorebird_code_push_api_client/shorebird_code_push_api_client.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcess extends Mock implements Process {}

class _MockShorebirdCodePushApiClient extends Mock
    implements ShorebirdCodePushApiClient {}

void main() {
  group('run', () {
    const session = Session(
      apiKey: 'test-api-key',
      projectId: 'test-project-id',
    );

    late Auth auth;
    late Logger logger;
    late Process process;
    late ShorebirdCodePushApiClient codePushApiClient;
    late RunCommand runCommand;

    setUp(() {
      auth = _MockAuth();
      logger = _MockLogger();
      process = _MockProcess();
      codePushApiClient = _MockShorebirdCodePushApiClient();
      runCommand = RunCommand(
        auth: auth,
        logger: logger,
        codePushApiClientBuilder: ({required String apiKey}) {
          return codePushApiClient;
        },
        startProcess: (executable, arguments, {bool runInShell = false}) async {
          return process;
        },
      );

      when(() => logger.progress(any())).thenReturn(_MockProgress());
    });

    test('exits with no user when not logged in', () async {
      when(() => auth.currentSession).thenReturn(null);

      final result = await runCommand.run();
      expect(result, equals(ExitCode.noUser.code));

      verify(() => logger.err('You must be logged in to run.')).called(1);
      verify(
        () => logger.err("Run 'shorebird login' to log in and try again."),
      ).called(1);
    });

    test('exits with code 70 when downloading engine fails', () async {
      final error = Exception('oops');
      when(() => auth.currentSession).thenReturn(session);
      when(
        () => codePushApiClient.downloadEngine(any()),
      ).thenThrow(error);
      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await runCommand.run();
      expect(result, equals(ExitCode.software.code));

      verify(
        () => progress.fail('Failed to download shorebird engine: $error'),
      ).called(1);
    });

    test('exits with code 70 when building the engine fails', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, '.shorebird', 'cache'))
          .createSync(recursive: true);

      when(() => auth.currentSession).thenReturn(session);
      when(
        () => codePushApiClient.downloadEngine(any()),
      ).thenAnswer((_) async => Uint8List(0));
      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await IOOverrides.runZoned(
        () => runCommand.run(),
        getCurrentDirectory: () => tempDir,
      );
      expect(result, equals(ExitCode.software.code));

      verify(
        () => progress.fail(
          any(that: contains('Failed to build shorebird engine:')),
        ),
      ).called(1);
    });

    test('exits with code when running the app fails', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final engineCacheDir = Directory(
        p.join(tempDir.path, '.shorebird', 'cache'),
      )..createSync(recursive: true);

      ZipFileEncoder()
        ..create(p.join(engineCacheDir.path, 'engine.zip'))
        ..close();

      when(() => auth.currentSession).thenReturn(session);
      when(
        () => codePushApiClient.downloadEngine(any()),
      ).thenAnswer((_) async => Uint8List(0));

      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      const error = 'oops something went wrong';
      const exitCode = 1;

      when(
        () => process.stdout,
      ).thenAnswer((_) => const Stream.empty());
      when(() => process.stderr).thenAnswer(
        (_) => Stream.value(utf8.encode(error)),
      );
      when(() => process.exitCode).thenAnswer((_) async => exitCode);

      final result = await IOOverrides.runZoned(
        () => runCommand.run(),
        getCurrentDirectory: () => tempDir,
      );

      await expectLater(result, equals(exitCode));
      verify(() => logger.err(error)).called(1);
    });

    test('exits with code 0 when running the app succeeds', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, '.shorebird', 'cache'))
          .createSync(recursive: true);
      Directory(p.join(tempDir.path, '.shorebird', 'engine'))
          .createSync(recursive: true);
      when(() => auth.currentSession).thenReturn(session);
      when(
        () => codePushApiClient.downloadEngine(any()),
      ).thenAnswer((_) async => Uint8List(0));

      final progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      const output = 'some output';
      when(
        () => process.stdout,
      ).thenAnswer((_) => Stream.value(utf8.encode(output)));
      when(() => process.stderr).thenAnswer((_) => const Stream.empty());
      when(
        () => process.exitCode,
      ).thenAnswer((_) async => ExitCode.success.code);

      final result = await IOOverrides.runZoned(
        () => runCommand.run(),
        getCurrentDirectory: () => tempDir,
      );

      await expectLater(result, equals(ExitCode.success.code));
      verify(() => logger.info(output)).called(1);
    });
  });
}
