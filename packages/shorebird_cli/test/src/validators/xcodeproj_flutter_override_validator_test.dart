import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(XcodeprojFlutterOverrideValidator, () {
    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;
    late XcodeprojFlutterOverrideValidator validator;

    void writePbxprojFile(String contents) {
      final xcodeprojDir = Directory(
        p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
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
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
      expect(
        validator.description,
        'Xcode project does not override FLUTTER_ build settings',
      );
    });

    group('canRunInCurrentContext', () {
      test('returns false if no ios/Runner.xcodeproj directory exists', () {
        final result = runWithOverrides(
          () => validator.canRunInCurrentContext(),
        );

        expect(result, isFalse);
      });

      test('returns true if ios/Runner.xcodeproj directory exists', () {
        Directory(
          p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
        ).createSync(recursive: true);

        final result = runWithOverrides(
          () => validator.canRunInCurrentContext(),
        );

        expect(result, isTrue);
      });

      test('returns false if project root is null', () {
        when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(null);

        final result = runWithOverrides(
          () => validator.canRunInCurrentContext(),
        );

        expect(result, isFalse);
      });
    });

    group('validate', () {
      test('returns error if project.pbxproj file does not exist', () async {
        Directory(
          p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
        ).createSync(recursive: true);

        final results = await runWithOverrides(validator.validate);

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.error);
        expect(
          results.first.message,
          startsWith('No project.pbxproj file found at'),
        );
        expect(results.first.fix, isNull);
      });

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
          expect(results.first.severity, ValidationIssueSeverity.error);
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
          expect(results.first.severity, ValidationIssueSeverity.error);
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
          expect(results.first.severity, ValidationIssueSeverity.error);
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
          expect(results.first.severity, ValidationIssueSeverity.error);
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
          expect(results.first.severity, ValidationIssueSeverity.error);
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
          expect(results.first.severity, ValidationIssueSeverity.error);
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
          expect(results.first.severity, ValidationIssueSeverity.error);
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
	ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
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
    });
  });
}
