import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/init_command.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

class _MockProcess extends Mock implements ShorebirdProcess {}

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockPlatform extends Mock implements Platform {}

void main() {
  group('init', () {
    const version = '1.2.3';
    const appId = 'test_app_id';
    const appName = 'test_app_name';
    const app = App(id: appId, displayName: appName);
    const appMetadata = AppMetadata(appId: appId, displayName: appName);
    const pubspecYamlContent = '''
name: $appName
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"''';

    late http.Client httpClient;
    late ArgResults argResults;
    late Auth auth;
    late ShorebirdProcess process;
    late ProcessResult result;
    late CodePushClient codePushClient;
    late Logger logger;
    late InitCommand command;

    setUp(() {
      httpClient = _MockHttpClient();
      argResults = _MockArgResults();
      auth = _MockAuth();
      process = _MockProcess();
      result = _MockProcessResult();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      command = InitCommand(
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          return codePushClient;
        },
        logger: logger,
      )
        ..testProcess = process
        ..testArgResults = argResults;

      // when(() => argResults['force']).thenReturn(false);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(
        () => codePushClient.createApp(displayName: any(named: 'displayName')),
      ).thenAnswer((_) async => app);
      when(
        () => codePushClient.getApps(),
      ).thenAnswer((_) async => [appMetadata]);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(appName);
      when(
        () => process.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => result);

      when(() => result.exitCode).thenReturn(ExitCode.success.code);
      when(() => result.stdout).thenReturn('');
    });

    group('extractProductFlavors', () {
      test('uses correct executable on windows', () async {
        final platform = _MockPlatform();
        when(() => platform.isWindows).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isLinux).thenReturn(false);
        final tempDir = Directory.systemTemp.createTempSync();
        when(() => platform.environment).thenReturn({
          'PROGRAMFILES': tempDir.path,
          'PROGRAMFILES(X86)': tempDir.path,
        });
        final androidStudioDir = Directory(
          p.join(tempDir.path, 'Android', 'Android Studio'),
        )..createSync(recursive: true);
        final jbrDir = Directory(p.join(androidStudioDir.path, 'jbr'))
          ..createSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await expectLater(
          command.extractProductFlavors(tempDir.path, platform: platform),
          completes,
        );
        verify(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew.bat'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': jbrDir.path},
          ),
        ).called(1);
      });

      test('uses correct executable on MacOS', () async {
        final platform = _MockPlatform();
        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.isMacOS).thenReturn(true);
        when(() => platform.isLinux).thenReturn(false);
        final tempDir = Directory.systemTemp.createTempSync();
        when(() => platform.environment).thenReturn({'HOME': tempDir.path});
        final androidStudioDir = Directory(
          p.join(
            tempDir.path,
            'Applications',
            'Android Studio.app',
            'Contents',
          ),
        )..createSync(recursive: true);
        final jbrDir = Directory(
          p.join(androidStudioDir.path, 'jbr', 'Contents', 'Home'),
        )..createSync(recursive: true);
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await expectLater(
          command.extractProductFlavors(tempDir.path, platform: platform),
          completes,
        );
        verify(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': jbrDir.path},
          ),
        ).called(1);
      });

      test('uses correct executable on Linux', () async {
        final platform = _MockPlatform();
        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isLinux).thenReturn(true);
        final tempDir = Directory.systemTemp.createTempSync();
        when(() => platform.environment).thenReturn({'HOME': tempDir.path});
        final androidStudioDir = Directory(
          p.join(tempDir.path, '.AndroidStudio'),
        )..createSync(recursive: true);
        final jbrDir = Directory(p.join(androidStudioDir.path, 'jbr'))
          ..createSync(recursive: true);
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync(pubspecYamlContent);
        await expectLater(
          command.extractProductFlavors(tempDir.path, platform: platform),
          completes,
        );
        verify(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': jbrDir.path},
          ),
        ).called(1);
      });
    });

    test('returns no user error when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final result = await command.run();
      expect(result, ExitCode.noUser.code);
    });

    test('throws no input error when pubspec.yaml is not found.', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(
          '''
Could not find a "pubspec.yaml".
Please make sure you are running "shorebird init" from the root of your Flutter project.
''',
        ),
      ).called(1);
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
        () => logger.err(
          any(that: contains('Error parsing "pubspec.yaml":')),
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws software error when shorebird.yaml already exists', () async {
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
          '''
A "shorebird.yaml" already exists.
If you want to reinitialize Shorebird, please delete the "shorebird.yaml" file and run "shorebird init" again.''',
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('--force overwrites existing shorebird.yaml', () async {
      when(() => argResults['force']).thenReturn(true);
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(p.join(tempDir.path, 'shorebird.yaml')).createSync();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verifyNever(
        () => logger.err(
          '''
A "shorebird.yaml" already exists.
If you want to reinitialize Shorebird, please run "shorebird init --force".''',
        ),
      );
      expect(exitCode, ExitCode.success.code);
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('app_id: $appId'),
      );
    });

    test('throws when extracting flavors throws', () async {
      when(() => result.exitCode).thenReturn(1);
      when(() => result.stdout).thenReturn('error');
      when(() => result.stderr).thenReturn('oops');
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.err('Exception: error\noops')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws software error when error occurs creating app.', () async {
      final error = Exception('oops');
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      when(
        () => codePushClient.createApp(displayName: any(named: 'displayName')),
      ).thenThrow(error);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).called(1);
      verify(() => logger.err('$error')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('creates shorebird.yaml for an app without flavors', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('app_id: $appId'),
      );
    });

    test('creates shorebird.yaml for an app with flavors', () async {
      final appIds = ['test-appId-1', 'test-appId-2', 'test-appId-3'];
      var index = 0;
      when(
        () => codePushClient.createApp(displayName: any(named: 'displayName')),
      ).thenAnswer((invocation) async {
        final displayName = invocation.namedArguments[#displayName] as String;
        return App(id: appIds[index++], displayName: displayName);
      });
      when(() => result.stdout).thenReturn(
        File(
          p.join('test', 'fixtures', 'gradle_app_tasks.txt'),
        ).readAsStringSync(),
      );
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('''
app_id:
  development: ${appIds[0]}
  production: ${appIds[1]}
  staging: ${appIds[2]}'''),
      );

      verifyInOrder([
        () => codePushClient.createApp(displayName: '$appName (development)'),
        () => codePushClient.createApp(displayName: '$appName (production)'),
        () => codePushClient.createApp(displayName: '$appName (staging)'),
      ]);
    });

    test('detects existing shorebird.yaml in pubspec.yaml assets', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync('''
$pubspecYamlContent
flutter:
  assets:
    - shorebird.yaml
''');
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('app_id: $appId'),
      );
    });

    test('creates flutter.assets and adds shorebird.yaml', () async {
      final tempDir = Directory.systemTemp.createTempSync();
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
