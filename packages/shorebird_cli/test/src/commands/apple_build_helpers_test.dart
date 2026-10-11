import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/apple_build_helpers.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../matchers.dart';
import '../mocks.dart';

void main() {
  late ShorebirdLogger logger;
  late Directory tempDir;

  R runWithOverrides<R>(R Function() body) {
    return runScoped(
      body,
      values: {loggerRef.overrideWith(() => logger)},
    );
  }

  File writePlist(String body) {
    return File(p.join(tempDir.path, 'Info.plist'))..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$body
</dict>
</plist>
''');
  }

  setUp(() {
    logger = MockShorebirdLogger();
    tempDir = Directory.systemTemp.createTempSync('apple_build_helpers_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('readReleaseVersionFromInfoPlist', () {
    const hint = 'Try something else.';

    test('returns the version and build number', () {
      final plistFile = writePlist('''
<key>CFBundleShortVersionString</key><string>1.2.3</string>
<key>CFBundleVersion</key><string>4</string>''');

      expect(
        runWithOverrides(() => readReleaseVersionFromInfoPlist(plistFile)),
        equals('1.2.3+4'),
      );
      verifyNever(() => logger.err(any()));
    });

    test('logs error and hint and exits when the file is missing', () {
      final plistFile = File(p.join(tempDir.path, 'Info.plist'));

      expect(
        () => runWithOverrides(
          () => readReleaseVersionFromInfoPlist(plistFile, hint: hint),
        ),
        exitsWithCode(ExitCode.software),
      );
      verify(
        () => logger.err('No Info.plist file found at ${plistFile.path}'),
      ).called(1);
      verify(() => logger.info(hint)).called(1);
    });

    test('logs error and hint and exits when there is no version', () {
      final plistFile = writePlist('');

      expect(
        () => runWithOverrides(
          () => readReleaseVersionFromInfoPlist(plistFile, hint: hint),
        ),
        exitsWithCode(ExitCode.software),
      );
      verify(
        () => logger.err(
          any(
            that: startsWith(
              'Failed to determine release version from ${plistFile.path}',
            ),
          ),
        ),
      ).called(1);
      verify(() => logger.info(hint)).called(1);
    });

    test('logs error and exits when the file cannot be parsed', () {
      final plistFile = File(p.join(tempDir.path, 'Info.plist'))
        ..writeAsBytesSync([0xff, 0xfe, 0xfd]);

      expect(
        () => runWithOverrides(
          () => readReleaseVersionFromInfoPlist(plistFile),
        ),
        exitsWithCode(ExitCode.software),
      );
      verify(
        () => logger.err(
          any(
            that: startsWith(
              'Failed to determine release version from ${plistFile.path}',
            ),
          ),
        ),
      ).called(1);
      verifyNever(() => logger.info(any()));
    });
  });

  group('AppleBuildArgs', () {
    late ArgResults argResults;

    setUp(() {
      argResults = MockArgResults();
    });

    group('codesign', () {
      test('is true only when the flag is true', () {
        when(() => argResults['codesign']).thenReturn(true);
        expect(argResults.codesign, isTrue);

        when(() => argResults['codesign']).thenReturn(false);
        expect(argResults.codesign, isFalse);

        when(() => argResults['codesign']).thenReturn(null);
        expect(argResults.codesign, isFalse);
      });
    });

    group('assertValidExportOptionsPlistArg', () {
      void stubExportOptionsPlist(String? path) {
        when(
          () => argResults[CommonArguments.exportOptionsPlistArg.name],
        ).thenReturn(path);
      }

      test('returns normally when no plist is passed', () {
        stubExportOptionsPlist(null);
        expect(
          () => runWithOverrides(argResults.assertValidExportOptionsPlistArg),
          returnsNormally,
        );
      });

      test(
        'returns normally when manageAppVersionAndBuildNumber is absent',
        () {
          stubExportOptionsPlist(
            writePlist('<key>method</key><string>app-store</string>').path,
          );
          expect(
            () => runWithOverrides(argResults.assertValidExportOptionsPlistArg),
            returnsNormally,
          );
        },
      );

      test(
        'logs error and exits with usage when '
        'manageAppVersionAndBuildNumber is true',
        () {
          stubExportOptionsPlist(
            writePlist(
              '<key>manageAppVersionAndBuildNumber</key><true/>',
            ).path,
          );
          expect(
            () => runWithOverrides(argResults.assertValidExportOptionsPlistArg),
            exitsWithCode(ExitCode.usage),
          );
          verify(
            () => logger.err(
              any(that: contains('manageAppVersionAndBuildNumber')),
            ),
          ).called(1);
        },
      );
    });
  });
}
