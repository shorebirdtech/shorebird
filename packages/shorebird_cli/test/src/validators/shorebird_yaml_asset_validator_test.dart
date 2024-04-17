import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';
import '../mocks.dart';

void main() {
  const pubspecWithoutFlutterSection = '''
name: shorebird_cli
description: Command-line tool to interact with Shorebird's services.
version: 1.0.0
''';

  const pubspecWithoutShorebirdAsset = '''
$pubspecWithoutFlutterSection
flutter:
  assets:
    - assets/image.png
''';

  const pubspecWithShorebirdAsset = '''
$pubspecWithoutFlutterSection
flutter:
  assets:
    - assets/image.png
    - shorebird.yaml
''';

  late File pubspecYamlFile;

  bool pubspecContainsShorebirdYaml() {
    final pubspec = Pubspec.parse(pubspecYamlFile.readAsStringSync());
    if (pubspec.flutter == null) return false;
    if (pubspec.flutter!['assets'] == null) return false;
    final assets = pubspec.flutter!['assets'] as List;
    return assets.contains('shorebird.yaml');
  }

  group(ShorebirdYamlAssetValidator, () {
    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;

    void writePubspecToPath(String pubspecContents, String path) {
      Directory(path).createSync(recursive: true);
      File(p.join(path, 'pubspec.yaml')).writeAsStringSync(pubspecContents);
    }

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync();
      pubspecYamlFile = File(p.join(projectRoot.path, 'pubspec.yaml'));
      shorebirdEnv = MockShorebirdEnv();
      writePubspecToPath(pubspecWithoutShorebirdAsset, projectRoot.path);

      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);
      when(() => shorebirdEnv.getPubspecYamlFile(cwd: any(named: 'cwd')))
          .thenReturn(pubspecYamlFile);
    });

    setUpAll(() {
      registerFallbackValue(MockDirectory());
    });

    test('has a non-empty description', () {
      expect(ShorebirdYamlAssetValidator().description, isNotEmpty);
    });

    group('canRunInContext', () {
      test('returns false if no pubspec.yaml file exists', () {
        when(() => shorebirdEnv.hasPubspecYaml).thenReturn(false);
        final result = runWithOverrides(
          () => ShorebirdYamlAssetValidator().canRunInCurrentContext(),
        );
        expect(result, isFalse);
      });

      test('returns true if a pubspec.yaml file exists', () {
        when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
        final result = runWithOverrides(
          () => ShorebirdYamlAssetValidator().canRunInCurrentContext(),
        );
        expect(result, isTrue);
      });
    });

    test(
      'returns successful result if pubspec.yaml has shorebird.yaml in assets',
      () async {
        when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
        when(() => shorebirdEnv.pubspecContainsShorebirdYaml).thenReturn(true);
        final results = await runWithOverrides(
          ShorebirdYamlAssetValidator().validate,
        );
        expect(results.map((res) => res.severity), isEmpty);
      },
    );

    test('returns an error if pubspec.yaml file does not exist', () async {
      when(() => shorebirdEnv.hasPubspecYaml).thenReturn(false);
      final results = await runWithOverrides(
        ShorebirdYamlAssetValidator().validate,
      );
      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(
        results.first.message,
        startsWith('No pubspec.yaml file found'),
      );
      expect(results.first.fix, isNull);
    });

    group('when shorebird.yaml is missing from assets', () {
      test('returns error', () async {
        when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
        when(() => shorebirdEnv.pubspecContainsShorebirdYaml).thenReturn(false);
        final results = await runWithOverrides(
          ShorebirdYamlAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            const ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message: 'No shorebird.yaml found in pubspec.yaml assets',
            ),
          ),
        );
      });
    });

    group('fix', () {
      test('adds shorebird.yaml to assets in pubspec.yaml', () async {
        writePubspecToPath(pubspecWithoutShorebirdAsset, projectRoot.path);
        when(
          () => shorebirdEnv.getPubspecYaml(),
        ).thenReturn(Pubspec.parse(pubspecYamlFile.readAsStringSync()));
        when(() => shorebirdEnv.getPubspecYamlFile(cwd: any(named: 'cwd')))
            .thenReturn(pubspecYamlFile);
        when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
        final pubspecContainsShorebirdYamlBeforeFix =
            pubspecContainsShorebirdYaml();
        when(() => shorebirdEnv.pubspecContainsShorebirdYaml)
            .thenReturn(pubspecContainsShorebirdYamlBeforeFix);
        when(() => shorebirdEnv.addShorebirdYamlToPubspecAssets)
            .thenAnswer((invocation) {
          writePubspecToPath(pubspecWithShorebirdAsset, projectRoot.path);
        });

        var results = await runWithOverrides(
          ShorebirdYamlAssetValidator().validate,
        );

        expect(results, hasLength(1));
        expect(results.first.fix, isNotNull);
        await runWithOverrides(() => results.first.fix!());
        final pubspecContainsShorebirdYamlAfterFix =
            pubspecContainsShorebirdYaml();
        when(() => shorebirdEnv.pubspecContainsShorebirdYaml)
            .thenReturn(pubspecContainsShorebirdYamlAfterFix);
        results = await runWithOverrides(
          ShorebirdYamlAssetValidator().validate,
        );
        expect(results, isEmpty);
      });

      test('adds flutter section and assets if missing', () async {
        writePubspecToPath(pubspecWithoutFlutterSection, projectRoot.path);
        when(
          () => shorebirdEnv.getPubspecYaml(),
        ).thenReturn(Pubspec.parse(pubspecYamlFile.readAsStringSync()));
        when(() => shorebirdEnv.getPubspecYamlFile(cwd: any(named: 'cwd')))
            .thenReturn(pubspecYamlFile);
        when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
        final pubspecContainsShorebirdYamlBeforeFix =
            pubspecContainsShorebirdYaml();
        when(() => shorebirdEnv.pubspecContainsShorebirdYaml)
            .thenReturn(pubspecContainsShorebirdYamlBeforeFix);
        when(() => shorebirdEnv.addShorebirdYamlToPubspecAssets)
            .thenAnswer((invocation) {
          writePubspecToPath(pubspecWithShorebirdAsset, projectRoot.path);
        });
        
        var results = await runWithOverrides(
          ShorebirdYamlAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(results.first.fix, isNotNull);
        await runWithOverrides(() => results.first.fix!());
        final pubspecContainsShorebirdYamlAfterFix =
            pubspecContainsShorebirdYaml();
        when(() => shorebirdEnv.pubspecContainsShorebirdYaml)
            .thenReturn(pubspecContainsShorebirdYamlAfterFix);
        results = await runWithOverrides(
          ShorebirdYamlAssetValidator().validate,
        );
        expect(results, isEmpty);
      });
    });
  });
}
