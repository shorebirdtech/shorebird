import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/init_command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_flavor_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockDoctor extends Mock implements Doctor {}

class _MockJava extends Mock implements Java {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcess extends Mock implements ShorebirdProcess {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockPlatform extends Mock implements Platform {}

void main() {
  group(InitCommand, () {
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
    const javaHome = 'test_java_home';

    late http.Client httpClient;
    late ArgResults argResults;
    late Auth auth;
    late Doctor doctor;
    late Java java;
    late Platform platform;
    late ShorebirdProcess process;
    late ShorebirdProcessResult result;
    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late InitCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          doctorRef.overrideWith(() => doctor),
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
        },
      );
    }

    Directory setUpAppTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, 'android')).createSync(recursive: true);
      return tempDir;
    }

    Directory setUpModuleTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, '.android')).createSync(recursive: true);
      return tempDir;
    }

    setUp(() {
      httpClient = _MockHttpClient();
      argResults = _MockArgResults();
      auth = _MockAuth();
      doctor = _MockDoctor();
      java = _MockJava();
      platform = _MockPlatform();
      process = _MockProcess();
      result = _MockProcessResult();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      progress = _MockProgress();

      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(
        () => codePushClient.createApp(displayName: any(named: 'displayName')),
      ).thenAnswer((_) async => app);
      when(
        () => codePushClient.getApps(),
      ).thenAnswer((_) async => [appMetadata]);
      when(
        () => doctor.runValidators(any(), applyFixes: any(named: 'applyFixes')),
      ).thenAnswer((_) async => {});
      when(() => doctor.allValidators).thenReturn([]);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(appName);
      when(() => logger.progress(any())).thenReturn(progress);
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

      when(() => java.home).thenReturn(javaHome);
      when(() => platform.isWindows).thenReturn(false);

      command = runWithOverrides(
        () => InitCommand(
          buildCodePushClient: ({
            required http.Client httpClient,
            Uri? hostedUri,
          }) {
            return codePushClient;
          },
        ),
      )..testArgResults = argResults;
    });

    group('extractProductFlavors', () {
      test(
          'throws MissingGradleWrapperException '
          'when gradlew does not exist', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpAppTempDir();
        await expectLater(
          command.extractProductFlavors(tempDir.path),
          throwsA(isA<MissingGradleWrapperException>()),
        );
        verifyNever(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        );
      });

      test('uses existing JAVA_HOME when set', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'android', 'gradlew'),
        ).createSync(recursive: true);
        await expectLater(
          runWithOverrides(() => command.extractProductFlavors(tempDir.path)),
          completes,
        );
        verify(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        ).called(1);
      });

      test(
          'throws Exception '
          'when process exits with non-zero code', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'android', 'gradlew'),
        ).createSync(recursive: true);
        when(() => result.exitCode).thenReturn(1);
        when(() => result.stderr).thenReturn('test error');
        await expectLater(
          runWithOverrides(() => command.extractProductFlavors(tempDir.path)),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('test error'),
            ),
          ),
        );
        verify(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        ).called(1);
      });

      test('extracts flavors from module directory structure', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpModuleTempDir();
        File(
          p.join(tempDir.path, '.android', 'gradlew'),
        ).createSync(recursive: true);
        const javaHome = 'test_java_home';
        when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});
        await expectLater(
          runWithOverrides(() => command.extractProductFlavors(tempDir.path)),
          completes,
        );
        verify(
          () => process.run(
            p.join(tempDir.path, '.android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, '.android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        ).called(1);
      });
    });

    test('returns no user error when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.noUser.code);
    });

    test('throws no input error when pubspec.yaml is not found.', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
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
        () => runWithOverrides(command.run),
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
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(
          '''
A "shorebird.yaml" already exists.
If you want to reinitialize Shorebird, please run "shorebird init --force".''',
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
        () => runWithOverrides(command.run),
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

    test('fails when an error occurs while extracting flavors', () async {
      when(() => result.exitCode).thenReturn(1);
      when(() => result.stdout).thenReturn('error');
      when(() => result.stderr).thenReturn('oops');
      final tempDir = setUpAppTempDir();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.progress('Detecting product flavors')).called(1);
      verify(
        () => logger.err(
          any(that: contains('Unable to extract product flavors.')),
        ),
      ).called(1);
      verify(() => progress.fail()).called(1);
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
        () => runWithOverrides(command.run),
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
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('app_id: $appId'),
      );
    });

    test('creates shorebird.yaml for an app with flavors', () async {
      final appIds = [
        'test-appId-1',
        'test-appId-2',
        'test-appId-3',
        'test-appId-4',
        'test-appId-5',
        'test-appId-6'
      ];
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
      final tempDir = setUpAppTempDir();
      File(p.join(tempDir.path, 'android', 'gradlew')).createSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[0]}
  developmentInternal: ${appIds[1]}
  production: ${appIds[2]}
  productionInternal: ${appIds[3]}
  staging: ${appIds[4]}
  stagingInternal: ${appIds[5]}'''),
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
        () => runWithOverrides(command.run),
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
        () => runWithOverrides(command.run),
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
        () => runWithOverrides(command.run),
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
        () => runWithOverrides(command.run),
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

    test('fixes fixable validation errors', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(() => doctor.runValidators(any(), applyFixes: true)).called(1);
    });
  });
}
