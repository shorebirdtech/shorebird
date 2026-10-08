import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/pubspec_editor.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'mocks.dart';

class _FakeDirectory extends Fake implements Directory {}

void main() {
  group(PubspecEditor, () {
    late ShorebirdEnv shorebirdEnv;
    late PubspecEditor pubspecEditor;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
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
            () =>
                runWithOverrides(pubspecEditor.addShorebirdYamlToPubspecAssets),
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
              equals('''
$basePubspecContents
flutter:
 assets:
   - shorebird.yaml
'''),
            );
          });
          test(
            'creates assets and adds shorebird.yaml (non-empty flutter)',
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
 uses-material-design: true
 assets:
  - shorebird.yaml
'''),
              );
            },
          );
          // `flutter create` emits a `flutter` section holding exactly one
          // key with a comment block above it describing that key. Appending
          // is what keeps the two together: inserting before the only key
          // leaves the comment sitting on top of `assets:`, describing
          // something it has nothing to do with.
          test('keeps a comment attached to the key it documents', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
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

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true
  assets:
    - shorebird.yaml

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
'''),
            );
          });

          // A block collection's span runs on past itself to the end of the
          // document, so appending at the last entry's own end put `assets:`
          // underneath a comment belonging to nothing.
          test('appends above a trailing comment, not below it', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter:
  uses-material-design: true
  fonts:
    - family: Foo

# Some unrelated comment
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
  uses-material-design: true
  fonts:
    - family: Foo
  assets:
    - shorebird.yaml

# Some unrelated comment
'''),
            );
          });

          // Neither of these can hit the misplacement the append avoids, and
          // neither has a last entry to append after or a block layout to
          // match, so both stay on `yaml_edit`. Appending to them by hand
          // threw on the first, and produced YAML that no longer parses on
          // the second.
          test('handles an empty flutter map', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter: {}
''');
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addShorebirdYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            final result = pubspecFile.readAsStringSync();
            expect(result, contains('shorebird.yaml'));
            final flutter = (loadYaml(result) as YamlMap)['flutter'] as YamlMap;
            expect(flutter['assets'], equals(['shorebird.yaml']));
          });

          test('handles a flow-style flutter map', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter: {uses-material-design: true}
''');
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addShorebirdYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            // Still parses, still has both entries: the point is that the
            // result is valid YAML rather than any particular formatting.
            final flutter =
                (loadYaml(pubspecFile.readAsStringSync()) as YamlMap)['flutter']
                    as YamlMap;
            expect(flutter['assets'], equals(['shorebird.yaml']));
            expect(flutter['uses-material-design'], isTrue);
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
