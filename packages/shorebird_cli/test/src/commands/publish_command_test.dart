import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/commands/publish_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockCodePushClient extends Mock implements CodePushClient {}

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
    const version = '1.2.3';
    const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"''';

    late ArgResults argResults;
    late Auth auth;
    late Logger logger;
    late CodePushClient codePushClient;
    late PublishCommand command;

    setUp(() {
      argResults = _MockArgResults();
      auth = _MockAuth();
      logger = _MockLogger();
      codePushClient = _MockCodePushClient();
      command = PublishCommand(
        auth: auth,
        buildCodePushClient: ({required String apiKey}) => codePushClient,
        logger: logger,
      )
        ..testArgResults = argResults
        ..testCommandRunner = _FakeCommandRunner();

      when(() => argResults.rest).thenReturn([]);
      when(() => auth.currentSession).thenReturn(session);
      when(() => logger.progress(any())).thenReturn(_MockProgress());
      when(
        () => codePushClient.createPatch(
          baseVersion: any(named: 'baseVersion'),
          artifactPath: any(named: 'artifactPath'),
          channel: any(named: 'channel'),
          productId: any(named: 'productId'),
        ),
      ).thenAnswer((_) async {});
    });

    test('throws no user error when session does not exist', () async {
      when(() => auth.currentSession).thenReturn(null);
      final exitCode = await command.run();
      expect(exitCode, equals(ExitCode.noUser.code));
    });

    test('throws usage error when multiple args are passed.', () async {
      when(() => argResults.rest).thenReturn(['arg1', 'arg2']);
      await expectLater(command.run, throwsA(isA<UsageException>()));
    });

    test('throws no input error when pubspec.yaml is not found.', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.err('Could not find a "pubspec.yaml".')).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws software error when pubspec.yaml is malformed.', () async {
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
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
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

    test('throws no input error when artifact is not found (default).',
        () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('product_id: $productId');
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(any(that: contains('Artifact not found:'))),
      ).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws no input error when artifact is not found (custom).',
        () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'));
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('product_id: $productId');
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(
          any(
            that: contains('Artifact not found: "${artifact.path}"'),
          ),
        ),
      ).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws error when publish fails.', () async {
      const error = 'something went wrong';
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
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
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
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'))..createSync();
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('product_id: $productId');
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('Successfully deployed.')).called(1);
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
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'))..createSync();
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('Successfully deployed.')).called(1);
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

    test('creates flutter.assets and adds shorebird.yaml', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'))..createSync();
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
        equals('''
$pubspecYamlContent
flutter:
  assets:
    - shorebird.yaml
'''),
      );
    });

    test('creates assets and adds shorebird.yaml', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'))..createSync();
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
$pubspecYamlContent
flutter:
  uses-material-design: true
''');
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
        equals('''
$pubspecYamlContent
flutter:
  assets:
    - shorebird.yaml
  uses-material-design: true
'''),
      );
    });

    test('adds shorebird.yaml to assets', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final artifact = File(p.join(tempDir.path, 'patch.txt'))..createSync();
      when(() => argResults.rest).thenReturn([artifact.path]);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
$pubspecYamlContent
flutter:
  assets: 
    - some/asset.txt
''');
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
        equals('''
$pubspecYamlContent
flutter:
  assets: 
    - some/asset.txt
    - shorebird.yaml
'''),
      );
    });
  });
}
