import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

class _MockPlatform extends Mock implements Platform {}

void main() {
  group(ShorebirdEnv, () {
    const flutterRevision = 'test-flutter-revision';
    late Platform platform;
    late Directory shorebirdRoot;
    late Uri platformScript;
    late ShorebirdEnv shorebirdEnv;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
        },
      );
    }

    setUp(() {
      shorebirdRoot = Directory.systemTemp.createTempSync();
      platformScript = Uri.file(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'shorebird.snapshot'),
      );
      File(
        p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(flutterRevision, flush: true);
      platform = _MockPlatform();
      shorebirdEnv = runWithOverrides(ShorebirdEnv.new);

      when(() => platform.environment).thenReturn(const {});
      when(() => platform.script).thenReturn(platformScript);
    });

    group('flutterBinaryFile', () {
      test('returns correct path using the default revision', () {
        expect(
          runWithOverrides(() => shorebirdEnv.flutterBinaryFile().path),
          equals(
            p.join(
              shorebirdRoot.path,
              'bin',
              'cache',
              'flutter',
              flutterRevision,
              'bin',
              'flutter',
            ),
          ),
        );
      });

      test('returns correct path using a custom revision', () {
        const customFlutterRevision = 'custom-flutter-revision';
        expect(
          runWithOverrides(
            () => shorebirdEnv
                .flutterBinaryFile(revision: customFlutterRevision)
                .path,
          ),
          equals(
            p.join(
              shorebirdRoot.path,
              'bin',
              'cache',
              'flutter',
              customFlutterRevision,
              'bin',
              'flutter',
            ),
          ),
        );
      });
    });

    group('genSnapshotFile', () {
      test('returns correct path using the default revision', () {
        expect(
          runWithOverrides(() => shorebirdEnv.genSnapshotFile().path),
          equals(
            p.join(
              shorebirdRoot.path,
              'bin',
              'cache',
              'flutter',
              flutterRevision,
              'bin',
              'cache',
              'artifacts',
              'engine',
              'ios-release',
              'gen_snapshot_arm64',
            ),
          ),
        );
      });

      test('returns correct path using a custom revision', () {
        const customFlutterRevision = 'custom-flutter-revision';
        expect(
          runWithOverrides(
            () => shorebirdEnv
                .genSnapshotFile(revision: customFlutterRevision)
                .path,
          ),
          equals(
            p.join(
              shorebirdRoot.path,
              'bin',
              'cache',
              'flutter',
              customFlutterRevision,
              'bin',
              'cache',
              'artifacts',
              'engine',
              'ios-release',
              'gen_snapshot_arm64',
            ),
          ),
        );
      });
    });

    group('getPubspecYamlFile', () {
      test('returns correct file', () {
        final tempDir = Directory('temp');
        expect(
          IOOverrides.runZoned(
            () {
              return runWithOverrides(
                () => shorebirdEnv.getPubspecYamlFile().path,
              );
            },
            getCurrentDirectory: () => tempDir,
          ),
          equals(p.join(tempDir.path, 'pubspec.yaml')),
        );
      });
    });

    group('getPubspecYaml', () {
      test('returns null when pubspec.yaml does not exist', () {
        final tempDir = Directory('temp');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.getPubspecYaml()),
            getCurrentDirectory: () => tempDir,
          ),
          isNull,
        );
      });

      test('returns value when pubspec.yaml exists', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.getPubspecYaml()),
            getCurrentDirectory: () => tempDir,
          ),
          isA<Pubspec>().having((p) => p.name, 'name', 'test'),
        );
      });
    });

    group('hasPubspecYaml', () {
      test('returns false when pubspec.yaml does not exist', () {
        final tempDir = Directory('temp');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.hasPubspecYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test('returns true when pubspec.yaml does exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.hasPubspecYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isTrue,
        );
      });
    });

    group('hasShorebirdYaml', () {
      test('returns false when shorebird.yaml does not exist', () {
        final tempDir = Directory('temp');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.hasShorebirdYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test('returns true when shorebird.yaml does exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'shorebird.yaml'),
        ).writeAsStringSync('app_id: test-app-id');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.hasShorebirdYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isTrue,
        );
      });
    });

    group('pubspecContainsShorebirdYaml', () {
      test(
          'returns false when pubspec.yaml does not '
          'contain shorebird.yaml in assets', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(
              () => shorebirdEnv.pubspecContainsShorebirdYaml,
            ),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test(
          'returns true when pubspec.yaml does '
          'contain shorebird.yaml in assets', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('''
name: test
flutter:
  assets:
    - shorebird.yaml
''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(
              () => shorebirdEnv.pubspecContainsShorebirdYaml,
            ),
            getCurrentDirectory: () => tempDir,
          ),
          isTrue,
        );
      });
    });

    group('androidPackageName', () {
      test('returns null when pubspec.yaml does not contain android module',
          () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.androidPackageName),
            getCurrentDirectory: () => tempDir,
          ),
          isNull,
        );
      });

      test(
          'returns correct package name when '
          'pubspec.yaml contains android module', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('''
name: test
flutter:
  module:
    androidPackage: test-package
''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.androidPackageName),
            getCurrentDirectory: () => tempDir,
          ),
          equals('test-package'),
        );
      });
    });

    group('isShorebirdInitialized', () {
      test('returns false when shorebird.yaml does not exist', () {
        final tempDir = Directory('temp');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.isShorebirdInitialized),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test(
          'returns false when shorebird.yaml exists '
          'but pubspec does not contain shorebird.yaml', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'shorebird.yaml'),
        ).writeAsStringSync('app_id: test-app-id');
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.isShorebirdInitialized),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test(
          'returns false when shorebird.yaml does not exist '
          'but pubspec contains shorebird.yaml', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('''
name: test
flutter:
  assets:
    - shorebird.yaml''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.isShorebirdInitialized),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test(
          'returns true when shorebird.yaml exists '
          'and pubspec contains shorebird.yaml', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'shorebird.yaml'),
        ).writeAsStringSync('app_id: test-app-id');
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('''
name: test
flutter:
  assets:
    - shorebird.yaml''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.isShorebirdInitialized),
            getCurrentDirectory: () => tempDir,
          ),
          isTrue,
        );
      });
    });

    group('flutterRevision', () {
      test('returns correct revision', () {
        const revision = 'test-revision';
        File(p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'))
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);
        expect(
          runWithOverrides(() => shorebirdEnv.flutterRevision),
          equals(revision),
        );
      });

      test('trims revision file content', () {
        const revision = '''

test-revision

\r\n
''';
        File(p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'))
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);

        expect(
          runWithOverrides(() => shorebirdEnv.flutterRevision),
          'test-revision',
        );
      });
    });

    group('shorebirdEngineRevision', () {
      test('returns correct revision using default flutter revision', () {
        const engineRevision = 'test-revision';
        File(
          p.join(
            shorebirdRoot.path,
            'bin',
            'cache',
            'flutter',
            flutterRevision,
            'bin',
            'internal',
            'engine.version',
          ),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync(engineRevision, flush: true);
        expect(
          runWithOverrides(() => shorebirdEnv.shorebirdEngineRevision()),
          equals(engineRevision),
        );
      });

      test('returns correct revision using a custom flutter revision', () {
        const engineRevision = 'test-revision';
        const customFlutterRevision = 'custom-flutter-revision';
        File(
          p.join(
            shorebirdRoot.path,
            'bin',
            'cache',
            'flutter',
            customFlutterRevision,
            'bin',
            'internal',
            'engine.version',
          ),
        )
          ..createSync(recursive: true)
          ..writeAsStringSync(engineRevision, flush: true);
        expect(
          runWithOverrides(
            () => shorebirdEnv.shorebirdEngineRevision(
              flutterRevision: customFlutterRevision,
            ),
          ),
          equals(engineRevision),
        );
      });
    });

    group('hostedUrl', () {
      test('returns hosted url from env if available', () {
        when(() => platform.environment).thenReturn({
          'SHOREBIRD_HOSTED_URL': 'https://example.com',
        });
        expect(
          runWithOverrides(() => shorebirdEnv.hostedUri),
          equals(Uri.parse('https://example.com')),
        );
      });

      test('falls back to shorebird.yaml', () {
        final directory = Directory.systemTemp.createTempSync();
        File(p.join(directory.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: test-id
base_url: https://example.com''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => shorebirdEnv.hostedUri),
            getCurrentDirectory: () => directory,
          ),
          equals(Uri.parse('https://example.com')),
        );
      });

      test('returns null when there is no env override or shorebird.yaml', () {
        expect(runWithOverrides(() => shorebirdEnv.hostedUri), isNull);
      });
    });
  });
}
