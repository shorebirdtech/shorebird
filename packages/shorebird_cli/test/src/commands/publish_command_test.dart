import 'dart:io';

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
    const productId = 'test-product-id';

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

    test('throws no input error when pubspec.yaml is not found.', () async {
      when(() => auth.currentSession).thenReturn(session);
      when(() => argResults.rest).thenReturn([]);
      final tempDir = Directory.systemTemp.createTempSync();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.err('Could not find a "pubspec.yaml".')).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws software error when pubspec.yaml is malformed.', () async {
      when(() => auth.currentSession).thenReturn(session);
      when(() => argResults.rest).thenReturn([]);
      final tempDir = Directory.systemTemp.createTempSync();
      File(p.join(tempDir.path, 'pubspec.yaml')).createSync();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(any(that: contains('Error parsing "pubspec.yaml":'))),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws software error when shorebird.yaml is malformed.', () async {
      when(() => auth.currentSession).thenReturn(session);
      when(() => argResults.rest).thenReturn([]);
      final tempDir = Directory.systemTemp.createTempSync();
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
version: 0.0.1
environment:
  sdk: ">=2.19.0 <3.0.0"
''');
      File(p.join(tempDir.path, 'shorebird.yaml')).createSync();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(
          any(that: contains('Error parsing "shorebird.yaml":')),
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when publish fails.', () async {
      const error = 'something went wrong';
      when(() => auth.currentSession).thenReturn(session);
      when(
        () => codePushClient.createPatch(
          baseVersion: any(named: 'baseVersion'),
          artifactPath: any(named: 'artifactPath'),
          channel: any(named: 'channel'),
          productId: any(named: 'productId'),
        ),
      ).thenThrow(error);
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'))..createSync();
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
version: 0.0.1
environment:
  sdk: ">=2.19.0 <3.0.0"
''');
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('product_id: $productId');
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.err('Failed to deploy: $error')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('succeeds when publish is successful using existing product id',
        () async {
      when(() => auth.currentSession).thenReturn(session);
      const version = '1.2.3';
      when(
        () => codePushClient.createPatch(
          baseVersion: any(named: 'baseVersion'),
          artifactPath: any(named: 'artifactPath'),
          channel: any(named: 'channel'),
          productId: any(named: 'productId'),
        ),
      ).thenAnswer((_) async {});
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'))..createSync();
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
''');
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('product_id: $productId');
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('Deployed ${artifact.path}!')).called(1);
      verify(
        () => codePushClient.createPatch(
          baseVersion: version,
          productId: productId,
          artifactPath: artifact.path,
          channel: 'stable',
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('succeeds when publish is successful using newly generated product id',
        () async {
      const version = '1.2.3';
      when(() => auth.currentSession).thenReturn(session);
      when(
        () => codePushClient.createPatch(
          baseVersion: any(named: 'baseVersion'),
          artifactPath: any(named: 'artifactPath'),
          channel: any(named: 'channel'),
          productId: any(named: 'productId'),
        ),
      ).thenAnswer((_) async {});
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'))..createSync();
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
''');
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('Deployed ${artifact.path}!')).called(1);
      verify(
        () => codePushClient.createPatch(
          baseVersion: version,
          productId: any(named: 'productId', that: isNotEmpty),
          artifactPath: artifact.path,
          channel: 'stable',
        ),
      ).called(1);
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).existsSync(),
        isTrue,
      );
      expect(exitCode, ExitCode.success.code);
    });
  });
}
