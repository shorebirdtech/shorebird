import 'dart:io' hide Platform;

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(ShorebirdFlutterValidator, () {
    const flutterRevision = '45fc514f1a9c347a3af76b02baf980a4d88b7879';
    const flutterVersion = '3.7.9';

    late ShorebirdFlutterValidator validator;
    late Directory tempDir;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late Platform platform;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    Directory flutterDirectory(Directory root) =>
        Directory(p.join(root.path, 'bin', 'cache', 'flutter'));

    Directory setupTempDirectory() {
      final tempDir = Directory.systemTemp.createTempSync();
      flutterDirectory(tempDir).createSync(recursive: true);
      return tempDir;
    }

    setUp(() {
      tempDir = setupTempDirectory();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();

      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdEnv.flutterDirectory,
      ).thenReturn(flutterDirectory(tempDir));
      when(() => platform.environment).thenReturn({});
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => flutterVersion);
      when(
        () => shorebirdFlutter.getSystemVersion(),
      ).thenAnswer((_) async => flutterVersion);

      validator = ShorebirdFlutterValidator();
      when(
        () => shorebirdFlutter.isUnmodified(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => true);
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    test('canRunInContext always returns true', () {
      expect(validator.canRunInCurrentContext(), isTrue);
    });

    test('returns no issues when the Flutter install is good', () async {
      final results = await runWithOverrides(validator.validate);

      expect(results, isEmpty);
    });

    test('errors when Flutter does not exist', () async {
      flutterDirectory(tempDir).deleteSync();

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(results.first.message, contains('No Flutter directory found'));
    });

    test('warns when Flutter has local modifications', () async {
      when(
        () => shorebirdFlutter.isUnmodified(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => false);

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(results.first.message, contains('has local modifications'));
    });

    test(
      'does not warn if system flutter does not exist',
      () async {
        when(
          () => shorebirdFlutter.getSystemVersion(),
        ).thenThrow(const ProcessException('flutter', ['--version'], '', 127));

        final results = await runWithOverrides(
          () => validator.validate(),
        );

        expect(results, isEmpty);
      },
    );

    test(
      'does not warn if flutter version and shorebird flutter version have same'
      ' major and minor but different patch versions',
      () async {
        when(
          () => shorebirdFlutter.getSystemVersion(),
        ).thenAnswer((_) async => '3.7.10');

        final results = await runWithOverrides(
          () => validator.validate(),
        );

        expect(results, isEmpty);
      },
    );

    test(
      'warns when path flutter version has different major or minor version '
      'than shorebird flutter',
      () async {
        when(
          () => shorebirdFlutter.getSystemVersion(),
        ).thenAnswer((_) async => '3.8.9');

        final results = await runWithOverrides(validator.validate);

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.warning);
        expect(
          results.first.message,
          contains(
            'The version of Flutter that Shorebird includes and the Flutter on '
            'your path are different',
          ),
        );
      },
    );

    test(
      'warns if FLUTTER_STORAGE_BASE_URL has a non-empty value',
      () async {
        when(() => platform.environment).thenReturn(
          {'FLUTTER_STORAGE_BASE_URL': 'https://storage.flutter-io.cn'},
        );

        final results = await runWithOverrides(validator.validate);

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.warning);
        expect(
          results.first.message,
          contains(
            'Shorebird does not respect the FLUTTER_STORAGE_BASE_URL '
            'environment variable',
          ),
        );
      },
    );

    test('throws exception if path flutter version lookup fails', () async {
      when(() => shorebirdFlutter.getSystemVersion()).thenThrow(
        const ProcessException(
          'flutter',
          ['--version'],
          'OH NO THERE IS NO FLUTTER VERSION HERE',
          1,
        ),
      );

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(
        results[0],
        isA<ValidationIssue>().having(
          (exception) => exception.message,
          'message',
          contains('Failed to determine path Flutter version'),
        ),
      );
    });

    test('throws exception if shorebird flutter version lookup fails',
        () async {
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenThrow(
        const ProcessException(
          'flutter',
          ['--version'],
          'OH NO THERE IS NO FLUTTER VERSION HERE',
          1,
        ),
      );

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(
        results[0],
        isA<ValidationIssue>().having(
          (exception) => exception.message,
          'message',
          contains('Failed to determine Shorebird Flutter version'),
        ),
      );
    });
  });
}
