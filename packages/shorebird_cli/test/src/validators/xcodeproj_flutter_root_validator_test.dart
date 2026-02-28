import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(XcodeprojFlutterRootValidator, () {
    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;
    late XcodeprojFlutterRootValidator validator;

    void writePbxprojFile(String contents) {
      final xcodeprojDir = Directory(
        p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
      );
      xcodeprojDir.createSync(recursive: true);
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
      validator = XcodeprojFlutterRootValidator();

      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
      expect(
        validator.description,
        'Xcode project does not override FLUTTER_ROOT environment variable',
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
        'returns successful result if project.pbxproj does not contain FLUTTER_ROOT',
        () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 54;
	objects = {
		/* Begin PBXBuildFile section */
		/* End PBXBuildFile section */
	};
	rootObject = 1234567890 /* Project object */;
}
''';
          writePbxprojFile(pbxprojContent);

          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        },
      );

      group('when FLUTTER_ROOT override exists', () {
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
            contains('contains a FLUTTER_ROOT override'),
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
      });

      group('when FLUTTER_ROOT does not exist', () {
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

        test('does not detect similar variable names', () async {
          const pbxprojContent = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	FLUTTER_BUILD_DIR = build;
	FLUTTER_FRAMEWORK_DIR = Flutter;
	classes = {
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
