import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(BuildAarCommand, () {
    const appId = 'test-app-id';
    const buildNumber = '1.0';
    const noModulePubspecYamlContent = '''
name: example
version: 1.0.0
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    const pubspecYamlContent = '''
name: example
version: 1.0.0
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  module:
    androidX: true
    androidPackage: com.example.my_flutter_module
    iosBundleIdentifier: com.example.myFlutterModule
  assets:
    - shorebird.yaml''';

    late ArgResults argResults;
    late Auth auth;
    late http.Client httpClient;
    late Logger logger;
    late Progress progress;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdProcessResult processResult;
    late BuildAarCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger)
        },
      );
    }

    Directory setUpTempDir({bool includeModule = true}) {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(
        includeModule ? pubspecYamlContent : noModulePubspecYamlContent,
      );
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');
      return tempDir;
    }

    setUp(() {
      argResults = _MockArgResults();
      auth = _MockAuth();
      httpClient = _MockHttpClient();
      logger = _MockLogger();
      processResult = _MockProcessResult();
      progress = _MockProgress();
      shorebirdProcess = _MockShorebirdProcess();

      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((invocation) async {
        return processResult;
      });

      command = runWithOverrides(() => BuildAarCommand(validators: {}))
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();
    });

    test('has correct description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits with no user when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.noUser.code));

      verify(
        () => logger.err(any(that: contains('You must be logged in to run'))),
      ).called(1);
    });

    test('exits with 78 if no pubspec.yaml exists', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, ExitCode.config.code);
    });

    test('exits with 78 if no module entry exists in pubspec.yaml', () async {
      final tempDir = setUpTempDir(includeModule: false);
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, ExitCode.config.code);
    });

    test('exits with code 70 when building aar fails', () async {
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn('oops');
      final tempDir = setUpTempDir();

      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=$buildNumber',
          ],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
    });

    test('exits with code 0 when building aar succeeds', () async {
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = setUpTempDir();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=$buildNumber',
          ],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''
📦 Generated an aar at:
${lightCyan.wrap(
            p.join(
              'build',
              'host',
              'outputs',
              'repo',
              'com',
              'example',
              'my_flutter_module',
              'flutter_release',
              buildNumber,
              'flutter_release-$buildNumber.aar',
            ),
          )}''',
        ),
      ).called(1);
    });

    test(
        '''exits with code 0 when building aar succeeds with flavor and custom build number''',
        () async {
      const flavor = 'development';
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['build-number']).thenReturn('2.0');
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = setUpTempDir();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=2.0',
            '--flavor=$flavor',
          ],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''
📦 Generated an aar at:
${lightCyan.wrap(
            p.join(
              'build',
              'host',
              'outputs',
              'repo',
              'com',
              'example',
              'my_flutter_module',
              'flutter_release',
              '2.0',
              'flutter_release-2.0.aar',
            ),
          )}''',
        ),
      ).called(1);
    });
  });
}
