import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/commands/init_command.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group('init', () {
    const version = '1.2.3';
    const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"''';
    const appId = 'test-app-id';

    late Logger logger;
    late Progress progress;
    late InitCommand command;

    setUp(() {
      logger = _MockLogger();
      progress = _MockProgress();
      command = InitCommand(logger: logger, buildUuid: () => appId);

      when(() => logger.progress(any())).thenReturn(progress);
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
          any(that: contains('Error creating "shorebird.yaml".')),
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('detects existing shorebird.yaml', () async {
      const existingAppId = 'existing-app-id';
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $existingAppId');
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(
        File(p.join(tempDir.path, 'shorebird.yaml')).readAsStringSync(),
        contains('app_id: $existingAppId'),
      );
      verify(() => progress.update('"shorebird.yaml" already exists.'));
    });

    test('creates shorebird.yaml', () async {
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
      verify(
        () => progress.update(
          '"shorebird.yaml" already in "pubspec.yaml" assets.',
        ),
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
