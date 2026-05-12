import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(LegacyKeepDebugSymbolsValidator, () {
    const flutterRevision = 'aaaa1111bbbb2222cccc3333dddd4444eeee5555';

    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;

    String kotlinGradleWithLegacyLine = '''
android {
  buildTypes {
    release {
      packaging.jniLibs.keepDebugSymbols.add("**/libapp.so")
    }
  }
}
''';

    String groovyGradleWithLegacyPlusEquals = '''
android {
  buildTypes {
    release {
      packaging.jniLibs.keepDebugSymbols += '**/libapp.so'
    }
  }
}
''';

    String cleanGradle = '''
android {
  buildTypes {
    release {
      // Nothing about libapp.so here.
    }
  }
}
''';

    void writeGradle(String filename, String contents) {
      final appDir = Directory(p.join(projectRoot.path, 'android', 'app'))
        ..createSync(recursive: true);
      File(p.join(appDir.path, filename)).writeAsStringSync(contents);
    }

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();

      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdFlutter.resolveFlutterVersion(any()),
      ).thenAnswer((_) async => Version(3, 44, 0));
    });

    test('has a non-empty description', () {
      expect(LegacyKeepDebugSymbolsValidator().description, isNotEmpty);
    });

    group('canRunInCurrentContext', () {
      test('returns false when no android/app directory exists', () {
        expect(
          runWithOverrides(
            () => LegacyKeepDebugSymbolsValidator().canRunInCurrentContext(),
          ),
          isFalse,
        );
      });

      test('returns true when build.gradle.kts exists', () {
        writeGradle('build.gradle.kts', cleanGradle);
        expect(
          runWithOverrides(
            () => LegacyKeepDebugSymbolsValidator().canRunInCurrentContext(),
          ),
          isTrue,
        );
      });

      test('returns true when only build.gradle (Groovy) exists', () {
        writeGradle('build.gradle', cleanGradle);
        expect(
          runWithOverrides(
            () => LegacyKeepDebugSymbolsValidator().canRunInCurrentContext(),
          ),
          isTrue,
        );
      });
    });

    group('on Flutter < 3.44', () {
      setUp(() {
        // The keepDebugSymbols line was the intended configuration before
        // 3.44, so the validator must be a no-op on older Flutter to avoid
        // false-positive warnings.
        when(
          () => shorebirdFlutter.resolveFlutterVersion(any()),
        ).thenAnswer((_) async => Version(3, 41, 9));
      });

      test('returns no issues even when the legacy line is present', () async {
        writeGradle('build.gradle.kts', kotlinGradleWithLegacyLine);

        final issues = await runWithOverrides(
          LegacyKeepDebugSymbolsValidator().validate,
        );

        expect(issues, isEmpty);
      });
    });

    group('on Flutter >= 3.44', () {
      test(
        'returns no issues when neither gradle file contains the line',
        () async {
          writeGradle('build.gradle.kts', cleanGradle);

          final issues = await runWithOverrides(
            LegacyKeepDebugSymbolsValidator().validate,
          );

          expect(issues, isEmpty);
        },
      );

      test(
        'returns a warning when build.gradle.kts has the .add(...) form',
        () async {
          writeGradle('build.gradle.kts', kotlinGradleWithLegacyLine);

          final issues = await runWithOverrides(
            LegacyKeepDebugSymbolsValidator().validate,
          );

          expect(issues, hasLength(1));
          final issue = issues.single;
          expect(issue.severity, ValidationIssueSeverity.warning);
          expect(issue.message, contains('build.gradle.kts'));
          expect(issue.message, contains('keepDebugSymbols'));
          expect(issue.message, contains('libapp.so'));
          expect(issue.message, contains('flutter/flutter#181275'));
        },
      );

      test('returns a warning when build.gradle has the += form', () async {
        writeGradle('build.gradle', groovyGradleWithLegacyPlusEquals);

        final issues = await runWithOverrides(
          LegacyKeepDebugSymbolsValidator().validate,
        );

        expect(issues, hasLength(1));
        expect(issues.single.message, contains('build.gradle'));
      });

      test(
        'returns two warnings when both files contain the legacy line',
        () async {
          writeGradle('build.gradle.kts', kotlinGradleWithLegacyLine);
          writeGradle('build.gradle', groovyGradleWithLegacyPlusEquals);

          final issues = await runWithOverrides(
            LegacyKeepDebugSymbolsValidator().validate,
          );

          expect(issues, hasLength(2));
          expect(
            issues.map((i) => i.severity),
            everyElement(ValidationIssueSeverity.warning),
          );
        },
      );
    });

    test(
      'treats an unknown Flutter version as satisfying the constraint',
      () async {
        // resolveFlutterVersion returns null for development pins. The
        // validator should still surface the warning in that case rather
        // than silently skipping; users on bleeding-edge pins are exactly
        // the ones most likely to be on a 3.44-equivalent fork.
        when(
          () => shorebirdFlutter.resolveFlutterVersion(any()),
        ).thenAnswer((_) async => null);
        writeGradle('build.gradle.kts', kotlinGradleWithLegacyLine);

        final issues = await runWithOverrides(
          LegacyKeepDebugSymbolsValidator().validate,
        );

        expect(issues, hasLength(1));
      },
    );
  });
}
