import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/commands/publish_command.dart';
import 'package:shorebird_code_push_api_client/shorebird_code_push_api_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdCodePushApiClient extends Mock
    implements ShorebirdCodePushApiClient {}

class _FakeCommandRunner extends Fake implements CommandRunner<int> {
  @override
  String get executableName => 'shorebird_test';
}

void main() {
  group('publish', () {
    const session = Session(
      projectId: 'test-project-id',
      apiKey: 'test-api-key',
    );

    late ArgResults argResults;
    late Auth auth;
    late Logger logger;
    late _MockShorebirdCodePushApiClient codePushClient;
    late PublishCommand command;

    setUp(() {
      argResults = _MockArgResults();
      auth = _MockAuth();
      logger = _MockLogger();
      codePushClient = _MockShorebirdCodePushApiClient();
      command = PublishCommand(
        auth: auth,
        buildCodePushClient: ({required String apiKey}) => codePushClient,
        logger: logger,
      )
        ..testArgResults = argResults
        ..testCommandRunner = _FakeCommandRunner();

      when(() => logger.progress(any())).thenReturn(_MockProgress());
    });

    test('throws no user error when session does not exist', () async {
      when(() => auth.currentSession).thenReturn(null);
      final exitCode = await command.run();
      expect(exitCode, equals(ExitCode.noUser.code));
    });

    test('throws usage error when multiple args are passed.', () async {
      when(() => auth.currentSession).thenReturn(session);
      when(() => argResults.rest).thenReturn(['arg1', 'arg2']);
      await expectLater(command.run, throwsA(isA<UsageException>()));
    });

    test('throws no input error when file is not found (default).', () async {
      when(() => auth.currentSession).thenReturn(session);
      when(() => argResults.rest).thenReturn([]);
      final exitCode = await command.run();
      verify(
        () => logger.err(any(that: contains('File not found: '))),
      ).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws no input error when file is not found (custom).', () async {
      when(() => auth.currentSession).thenReturn(session);
      when(() => argResults.rest).thenReturn(['missing.txt']);
      final exitCode = await command.run();
      verify(() => logger.err('File not found: missing.txt')).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws error when release fails.', () async {
      when(() => auth.currentSession).thenReturn(session);
      const error = 'something went wrong';
      when(() => codePushClient.createRelease(any())).thenThrow(error);
      final release = p.join('test', 'fixtures', 'release.txt');
      when(() => argResults.rest).thenReturn([release]);
      final exitCode = await command.run();
      verify(() => logger.err('Failed to deploy: $error')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('succeeds when release is successful.', () async {
      when(() => auth.currentSession).thenReturn(session);
      when(() => codePushClient.createRelease(any())).thenAnswer((_) async {});
      final release = p.join('test', 'fixtures', 'release.txt');
      when(() => argResults.rest).thenReturn([release]);
      final exitCode = await command.run();
      verify(() => logger.success('Deployed $release!')).called(1);
      expect(exitCode, ExitCode.success.code);
    });
  });
}
