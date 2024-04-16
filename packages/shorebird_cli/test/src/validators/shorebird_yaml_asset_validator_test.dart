import 'dart:io';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';
import '../mocks.dart';

void main() {
  const pubspecWithShorebirdAsset = '''
flutter:
  assets:
    - shorebird.yaml
''';

  const pubspecWithoutShorebirdAsset = '''
flutter:
  assets:
    - assets/image.png
''';

  const pubspecWithoutFlutterSection = '''
name: shorebird_cli
description: Command-line tool to interact with Shorebird's services.
version: 1.0.0
''';

  group(ShorebirdYAMLAssetValidator, () {
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
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);
    });

    test('has a non-empty description', () {
      expect(ShorebirdYAMLAssetValidator().description, isNotEmpty);
    });

    group('canRunInContext', () {
      test('returns false if no pubspec.yaml file exists', () {
        final result = runWithOverrides(
          () => ShorebirdYAMLAssetValidator().canRunInCurrentContext(),
        );
        expect(result, isFalse);
      });

      test('returns true if a pubspec.yaml file exists', () {
        writePubspecToPath(pubspecWithShorebirdAsset, projectRoot.path);
        final result = runWithOverrides(
          () => ShorebirdYAMLAssetValidator().canRunInCurrentContext(),
        );
        expect(result, isTrue);
      });
    });

    test(
      'returns successful result if pubspec.yaml has shorebird.yaml in assets',
      () async {
        writePubspecToPath(pubspecWithShorebirdAsset, projectRoot.path);
        final results = await runWithOverrides(
          ShorebirdYAMLAssetValidator().validate,
        );
        expect(results.map((res) => res.severity), isEmpty);
      },
    );

    test('returns an error if pubspec.yaml file does not exist', () async {
      final results = await runWithOverrides(
        ShorebirdYAMLAssetValidator().validate,
      );
      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(
        results.first.message,
        startsWith('No pubspec.yaml file found at'),
      );
      expect(results.first.fix, isNull);
    });

    group('when shorebird.yaml is missing from assets', () {
      test('returns error', () async {
        writePubspecToPath(pubspecWithoutShorebirdAsset, projectRoot.path);
        final results = await runWithOverrides(
          ShorebirdYAMLAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            const ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message:
                  'No shorebird.yaml found in pubspec.yaml assets',
            ),
          ),
        );
      });
    });

    group('when flutter section is missing', () {
      test('returns error', () async {
        writePubspecToPath(pubspecWithoutFlutterSection, projectRoot.path);
        final results = await runWithOverrides(
          ShorebirdYAMLAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            const ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message:
                  'No shorebird.yaml found in pubspec.yaml assets',
            ),
          ),
        );
      });
    });

    group('fix', () {
      test('adds shorebird.yaml to assets in pubspec.yaml', () async {
        writePubspecToPath(pubspecWithoutShorebirdAsset, projectRoot.path);
        var results = await runWithOverrides(
          ShorebirdYAMLAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(results.first.fix, isNotNull);
        await runWithOverrides(() => results.first.fix!());
        results = await runWithOverrides(
          ShorebirdYAMLAssetValidator().validate,
        );
        expect(results, isEmpty);
      });

      test('adds flutter section and assets if missing', () async {
        writePubspecToPath(pubspecWithoutFlutterSection, projectRoot.path);
        var results = await runWithOverrides(
          ShorebirdYAMLAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(results.first.fix, isNotNull);
        await runWithOverrides(() => results.first.fix!());
        results = await runWithOverrides(
          ShorebirdYAMLAssetValidator().validate,
        );
        expect(results, isEmpty);
      });
    });
  });
}
