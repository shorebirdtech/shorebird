import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/pubspec_editor.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import 'mocks.dart';

class _FakeDirectory extends Fake implements Directory {}

void main() {
  group(PubspecEditor, () {
    late ShorebirdEnv shorebirdEnv;
    late PubspecEditor pubspecEditor;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(_FakeDirectory());
    });

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      pubspecEditor = PubspecEditor();
    });

    group('addShorebirdYamlToPubspecAssets', () {
      group('when shorebird.yaml is part of the pubspec.yaml assets', () {
        setUp(() {
          when(
            () => shorebirdEnv.pubspecContainsShorebirdYaml,
          ).thenReturn(true);
        });

        test('does nothing', () {
          expect(
            () => runWithOverrides(
              pubspecEditor.addShorebirdYamlToPubspecAssets,
            ),
            returnsNormally,
          );
          verifyNever(() => shorebirdEnv.getFlutterProjectRoot());
        });
      });

      group('when shorebird.yaml is not part of the pubspec.yaml assets', () {
        setUp(() {
          when(
            () => shorebirdEnv.pubspecContainsShorebirdYaml,
          ).thenReturn(false);
        });

        group('when a flutter project root cannot be found', () {
          setUp(() {
            when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(null);
          });

          test('does nothing', () {
            expect(
              () => runWithOverrides(
                pubspecEditor.addShorebirdYamlToPubspecAssets,
              ),
              returnsNormally,
            );
            verify(() => shorebirdEnv.getFlutterProjectRoot()).called(1);
          });
        });

        group('when a flutter project root can be found', () {
          const basePubspecContents = '''
name: test
version: 1.0.0
environment:
 sdk: ">=2.19.0 <3.0.0"''';
          late Directory tempDir;
          late File pubspecFile;

          setUp(() {
            tempDir = Directory.systemTemp.createTempSync();
            pubspecFile = File(p.join(tempDir.path, 'pubspec.yaml'));
            when(
              () => shorebirdEnv.getFlutterProjectRoot(),
            ).thenReturn(tempDir);
            when(
              () => shorebirdEnv.getPubspecYamlFile(cwd: any(named: 'cwd')),
            ).thenReturn(pubspecFile);
          });

          test('creates flutter.assets and adds shorebird.yaml', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync(basePubspecContents);
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addShorebirdYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            expect(
              pubspecFile.readAsStringSync(),
              equals('''
$basePubspecContents
flutter:
 assets:
   - shorebird.yaml
'''),
            );
          });

          test('creates assets and adds shorebird.yaml (empty flutter)', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter:
''');
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addShorebirdYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            expect(
              pubspecFile.readAsStringSync(),
              equals(
                '''
$basePubspecContents
flutter:
 assets:
   - shorebird.yaml
''',
              ),
            );
          });
          test('creates assets and adds shorebird.yaml (non-empty flutter)',
              () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter:
 uses-material-design: true
''');
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addShorebirdYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            expect(
              pubspecFile.readAsStringSync(),
              equals('''
$basePubspecContents
flutter:
 assets:
  - shorebird.yaml
 uses-material-design: true
'''),
            );
          });
          test('adds shorebird.yaml to assets (existing assets)', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter:
 assets:
  - some/asset.txt
''');
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addShorebirdYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            expect(
              pubspecFile.readAsStringSync(),
              equals('''
$basePubspecContents
flutter:
 assets:
  - some/asset.txt
  - shorebird.yaml
'''),
            );
          });
        });
      });
    });
  });
}
