import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

const _appPubspec = '''
name: my_app
environment:
  sdk: ^3.0.0
flutter:
  uses-material-design: true
''';

const _modulePubspec = '''
name: my_flutter_module
environment:
  sdk: ^3.0.0
flutter:
  module:
    androidPackage: com.example.my_flutter_module
    iosBundleIdentifier: com.example.myFlutterModule
''';

void main() {
  group(XcodeprojFlutterOverrideValidator, () {
    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;
    late XcodeprojFlutterOverrideValidator validator;

    void writePbxprojFile(String contents, {String iosDir = 'ios'}) {
      final xcodeprojDir = Directory(
        p.join(projectRoot.path, iosDir, 'Runner.xcodeproj'),
      )..createSync(recursive: true);
      File(
        p.join(xcodeprojDir.path, 'project.pbxproj'),
      ).writeAsStringSync(contents);
    }

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
    }

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();
      validator = XcodeprojFlutterOverrideValidator();

      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);
      // Default to a non-module pubspec; module-specific tests override.
      when(
        () => shorebirdEnv.getPubspecYaml(),
      ).thenReturn(Pubspec.parse(_appPubspec));
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
      expect(
        validator.description,
        'Xcode project does not override FLUTTER_ build settings',
      );
    });

    group('validate', () {
      test('returns no issues if project root is null', () async {
        when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(null);

        final results = await runWithOverrides(validator.validate);

        expect(results, isEmpty);
      });

      test(
        'returns no issues if ios/Runner.xcodeproj directory does not exist '
        '(e.g. Flutter module / no iOS platform)',
        () async {
          // No ios/Runner.xcodeproj created — simulates a Flutter module or
          // an app without the iOS platform. The validator must silently
          // skip rather than error, otherwise commands like
          // `shorebird release ios-framework` are blocked.

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        },
      );

      test(
        'returns no issues if project.pbxproj file does not exist',
        () async {
          // Edge case: the Runner.xcodeproj directory exists but its
          // project.pbxproj file is missing. Treat as nothing-to-validate.
          Directory(
            p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
          ).createSync(recursive: true);

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        },
      );

      test(
        'returns successful result if project.pbxproj has no FLUTTER_ '
        'assignments',
        () async {
          // The default Flutter iOS template only *references* FLUTTER_ROOT
          // and FLUTTER_BUILD_NUMBER (via $FLUTTER_ROOT and
          // $(FLUTTER_BUILD_NUMBER)); it never assigns them in project.pbxproj.
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 54;
	objects = {
		9740EEB61CF901F6004384FC /* Run Script */ = {
			shellScript = "/bin/sh \"$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\" build";
		};
	};
	buildSettings = {
		CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
	};
	rootObject = 1234567890 /* Project object */;
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        },
      );

      group('when a FLUTTER_ override exists', () {
        test('detects FLUTTER_ROOT with space around equals', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	FLUTTER_ROOT = /path/to/flutter;
	classes = {
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, hasLength(1));
          expect(results.first.severity, ValidationIssueSeverity.warning);
          expect(
            results.first.message,
            contains('FLUTTER_ build setting(s): FLUTTER_ROOT'),
          );
        });

        // I'm not aware of this occurring in the wild, but being defensive.
        test('detects FLUTTER_ROOT with no spaces around equals', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	FLUTTER_ROOT=/path/to/flutter;
	classes = {
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, hasLength(1));
          expect(results.first.severity, ValidationIssueSeverity.warning);
        });

        // I'm also not aware of this occurring in the wild, but
        // again being defensive.
        test('detects FLUTTER_ROOT with quoted value', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	FLUTTER_ROOT = "/Users/developer/flutter";
	classes = {
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, hasLength(1));
          expect(results.first.severity, ValidationIssueSeverity.warning);
        });

        test('detects FLUTTER_ROOT with variable reference', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	FLUTTER_ROOT = $(FLUTTER_ROOT);
	classes = {
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, hasLength(1));
          expect(results.first.severity, ValidationIssueSeverity.warning);
        });

        test('detects FLUTTER_ROOT with multiple spaces', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	FLUTTER_ROOT   =   /path/to/flutter;
	classes = {
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, hasLength(1));
          expect(results.first.severity, ValidationIssueSeverity.warning);
        });

        test('detects FLUTTER_ROOT in buildSettings section', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	buildSettings = {
		FLUTTER_ROOT = /path/to/flutter;
		PRODUCT_NAME = Runner;
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, hasLength(1));
          expect(results.first.severity, ValidationIssueSeverity.warning);
        });

        test('detects other FLUTTER_-prefixed overrides', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	buildSettings = {
		FLUTTER_BUILD_DIR = build;
		FLUTTER_FRAMEWORK_DIR = /custom/Flutter;
		PRODUCT_NAME = Runner;
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, hasLength(1));
          expect(results.first.severity, ValidationIssueSeverity.warning);
          expect(
            results.first.message,
            allOf(
              contains('FLUTTER_BUILD_DIR'),
              contains('FLUTTER_FRAMEWORK_DIR'),
            ),
          );
        });

        test('lists each overridden name only once', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	buildSettings = {
		FLUTTER_ROOT = /path/to/flutter;
	};
	otherSettings = {
		FLUTTER_ROOT = /another/path;
		FLUTTER_BUILD_DIR = build;
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, hasLength(1));
          final message = results.first.message;
          expect(message, contains('FLUTTER_ROOT'));
          expect(message, contains('FLUTTER_BUILD_DIR'));
          expect(
            RegExp('FLUTTER_ROOT').allMatches(message),
            hasLength(1),
          );
        });
      });

      group('FLUTTER_TARGET allow-list', () {
        // FLUTTER_TARGET is commonly hard-coded per-configuration to point at
        // a flavor-specific entrypoint (e.g. lib/main_dev.dart). It does not
        // participate in SDK selection, so it must not be flagged.
        test('does not flag FLUTTER_TARGET on its own', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	buildSettings = {
		FLUTTER_TARGET = lib/main_dev.dart;
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        });

        test(
          'still flags other FLUTTER_ overrides when FLUTTER_TARGET is also '
          'set',
          () async {
            const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	buildSettings = {
		FLUTTER_TARGET = lib/main_dev.dart;
		FLUTTER_ROOT = /path/to/flutter;
	};
}
''';
            writePbxprojFile(pbxprojContent);

            final results = await runWithOverrides(validator.validate);

            expect(results, hasLength(1));
            expect(results.first.severity, ValidationIssueSeverity.warning);
            expect(results.first.message, contains('FLUTTER_ROOT'));
            expect(results.first.message, isNot(contains('FLUTTER_TARGET')));
          },
        );
      });

      group('when no FLUTTER_ override exists', () {
        test('does not detect FLUTTER_ROOT in comments', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
// FLUTTER_ROOT = /path/to/flutter;
{
	archiveVersion = 1;
	classes = {
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        });

        test('does not detect non-FLUTTER_-prefixed names', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	PRODUCT_NAME = Runner;
	CURRENT_PROJECT_VERSION = 1;
	classes = {
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        });

        // Flutter's own template includes a Run Script phase that shells out
        // to "$FLUTTER_ROOT/packages/...". That's a reference, not an
        // assignment, and must not trigger the validator.
        test('does not flag string-literal references', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	objects = {
		9740EEB61CF901F6004384FC /* Run Script */ = {
			shellScript = "/bin/sh \"$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\" build";
		};
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        });

        // This wouldn't be a valid project.pbxproj file, so this is
        // sorta a contrived test.
        test('does not detect FLUTTER_ROOT without semicolon', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	FLUTTER_ROOT = /path/to/flutter
	classes = {
	};
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        });
      });

      // Flutter modules (used for add-to-app) keep their generated Xcode
      // project under `.ios/Runner.xcodeproj` rather than `ios/Runner.xcodeproj`.
      // The validator must scan that path; otherwise commands like
      // `shorebird release ios-framework` either skip validation entirely or
      // (worse) hard-fail because they can't find an `ios/Runner.xcodeproj`.
      group('Flutter module (.ios/)', () {
        setUp(() {
          when(
            () => shorebirdEnv.getPubspecYaml(),
          ).thenReturn(Pubspec.parse(_modulePubspec));
        });

        test(
          'returns no issues if .ios/Runner.xcodeproj/project.pbxproj does '
          'not exist (e.g. before flutter pub get)',
          () async {
            final results = await runWithOverrides(validator.validate);

            expect(results, isEmpty);
          },
        );

        test(
          'returns no issues if .ios/Runner.xcodeproj/project.pbxproj has '
          'no FLUTTER_ assignments',
          () async {
            const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	buildSettings = {
		PRODUCT_NAME = Runner;
	};
}
''';
            writePbxprojFile(pbxprojContent, iosDir: '.ios');

            final results = await runWithOverrides(validator.validate);

            expect(results, isEmpty);
          },
        );

        test(
          'detects FLUTTER_ROOT in .ios/Runner.xcodeproj/project.pbxproj',
          () async {
            const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	buildSettings = {
		FLUTTER_ROOT = /path/to/flutter;
	};
}
''';
            writePbxprojFile(pbxprojContent, iosDir: '.ios');

            final results = await runWithOverrides(validator.validate);

            expect(results, hasLength(1));
            expect(results.first.severity, ValidationIssueSeverity.warning);
            expect(
              results.first.message,
              allOf(
                contains(p.join('.ios', 'Runner.xcodeproj', 'project.pbxproj')),
                contains('FLUTTER_ROOT'),
              ),
            );
          },
        );

        test(
          'does not look at ios/ when project is a module',
          () async {
            // A module that for some reason also has an `ios/Runner.xcodeproj`
            // (e.g. left behind from a previous `flutter create`) should still
            // be checked at `.ios/`, not `ios/`.
            const appPbxprojWithOverride = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	FLUTTER_ROOT = /should/not/be/scanned;
}
''';
            writePbxprojFile(appPbxprojWithOverride, iosDir: 'ios');
            // Module project has no overrides.
            const modulePbxproj = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	buildSettings = {
		PRODUCT_NAME = Runner;
	};
}
''';
            writePbxprojFile(modulePbxproj, iosDir: '.ios');

            final results = await runWithOverrides(validator.validate);

            expect(results, isEmpty);
          },
        );
      });
    });
  });
}
