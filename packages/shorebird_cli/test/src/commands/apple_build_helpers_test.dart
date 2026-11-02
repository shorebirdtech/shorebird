import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/apple_build_helpers.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../matchers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
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

    test('exits with an error and the hint when the file is missing', () {
      final plistFile = File(p.join(tempDir.path, 'Info.plist'));

      expect(
        () => runWithOverrides(
          () => readReleaseVersionFromInfoPlist(plistFile, hint: hint),
        ),
        exitsWithError(
          message: 'No Info.plist file found at ${plistFile.path}',
          hint: hint,
          exitCode: ExitCode.software,
        ),
      );
    });

    test('exits with an error and the hint when there is no version', () {
      final plistFile = writePlist('');

      expect(
        () => runWithOverrides(
          () => readReleaseVersionFromInfoPlist(plistFile, hint: hint),
        ),
        exitsWithError(
          message: startsWith(
            'Failed to determine release version from ${plistFile.path}',
          ),
          hint: hint,
          exitCode: ExitCode.software,
        ),
      );
    });

    test('exits with an error and no hint when the file cannot be parsed', () {
      final plistFile = File(p.join(tempDir.path, 'Info.plist'))
        ..writeAsBytesSync([0xff, 0xfe, 0xfd]);

      expect(
        () => runWithOverrides(
          () => readReleaseVersionFromInfoPlist(plistFile),
        ),
        throwsA(
          allOf(
            isCommandError(
              message: startsWith(
                'Failed to determine release version from ${plistFile.path}',
              ),
              exitCode: ExitCode.software,
            ),
            isA<CommandError>().having((e) => e.hint, 'hint', isNull),
          ),
        ),
      );
    });
  });
}
