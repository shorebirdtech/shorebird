import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/pubspec_editor.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(ShorebirdYamlAssetValidator, () {
    late ShorebirdEnv shorebirdEnv;
    late PubspecEditor pubspecEditor;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          pubspecEditorRef.overrideWith(() => pubspecEditor),
        },
      );
    }

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      pubspecEditor = MockPubspecEditor();
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

    group('validate', () {
      test(
        'returns successful result '
        'if pubspec.yaml has shorebird.yaml in assets',
        () async {
          when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
          when(
            () => shorebirdEnv.pubspecContainsShorebirdYaml,
          ).thenReturn(true);
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

      test('returns error if shorebird.yaml is missing from assets', () async {
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
      test('adds shorebird.yaml to pubspec.yaml', () async {
        when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
        when(() => shorebirdEnv.pubspecContainsShorebirdYaml).thenReturn(false);
        when(
          () => pubspecEditor.addShorebirdYamlToPubspecAssets(),
        ).thenAnswer((_) {});

        final results = await runWithOverrides(
          ShorebirdYamlAssetValidator().validate,
        );

        expect(results, hasLength(1));
        expect(results.first.fix, isNotNull);
        await runWithOverrides(() => results.first.fix!());
        verify(pubspecEditor.addShorebirdYamlToPubspecAssets).called(1);
      });
    });
  });
}
