import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

void main() {
  const manifestWithInternetPermission = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="dev.shorebird.u_shorebird_clock">
    <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
''';

  const manifestWithCommentedOutInternetPermission = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="dev.shorebird.u_shorebird_clock">
    <!-- <uses-permission android:name="android.permission.INTERNET"/> -->
</manifest>
''';

  const manifestWithNonInternetPermissions = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="dev.shorebird.u_shorebird_clock">
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
</manifest>
''';

  const manifestWithNoPermissions = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="dev.shorebird.u_shorebird_clock">
</manifest>
''';

  group(AndroidInternetPermissionValidator, () {
    Directory createTempDir() => Directory.systemTemp.createTempSync();

    void writeManifestToPath(String manifestContents, String path) {
      Directory(path).createSync(recursive: true);
      File(p.join(path, 'AndroidManifest.xml'))
          .writeAsStringSync(manifestContents);
    }

    test('has a non-empty description', () {
      expect(AndroidInternetPermissionValidator().description, isNotEmpty);
    });

    group('canRunInContext', () {
      test('returns false if no android src directory exists', () {
        final tempDirectory = createTempDir();

        final result = IOOverrides.runZoned(
          () => AndroidInternetPermissionValidator().canRunInCurrentContext(),
          getCurrentDirectory: () => tempDirectory,
        );

        expect(result, isFalse);
      });

      test('returns true if an android src directory exists', () {
        final tempDirectory = createTempDir();
        writeManifestToPath(
          manifestWithInternetPermission,
          p.join(tempDirectory.path, 'android', 'app', 'src', 'main'),
        );

        final result = IOOverrides.runZoned(
          () => AndroidInternetPermissionValidator().canRunInCurrentContext(),
          getCurrentDirectory: () => tempDirectory,
        );

        expect(result, isTrue);
      });
    });

    test(
      '''returns successful result if the main AndroidManifest.xml file has the INTERNET permission''',
      () async {
        final tempDirectory = createTempDir();
        writeManifestToPath(
          manifestWithInternetPermission,
          p.join(tempDirectory.path, 'android', 'app', 'src', 'main'),
        );

        final results = await IOOverrides.runZoned(
          AndroidInternetPermissionValidator().validate,
          getCurrentDirectory: () => tempDirectory,
        );

        expect(results.map((res) => res.severity), isEmpty);
      },
    );

    test('returns an error if AndroidManifest.xml file does not exist',
        () async {
      final tempDirectory = createTempDir();
      Directory(p.join(tempDirectory.path, 'android', 'app', 'src', 'main'))
          .createSync(recursive: true);

      final results = await IOOverrides.runZoned(
        AndroidInternetPermissionValidator().validate,
        getCurrentDirectory: () => tempDirectory,
      );

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(
        results.first.message,
        startsWith('No AndroidManifest.xml file found at'),
      );
      expect(results.first.fix, isNull);
    });

    group('when the INTERNET permission is commented out', () {
      test('returns error', () async {
        final tempDirectory = createTempDir();
        final manifestPath =
            p.join(tempDirectory.path, 'android', 'app', 'src', 'main');

        writeManifestToPath(
          manifestWithCommentedOutInternetPermission,
          manifestPath,
        );

        final results = await IOOverrides.runZoned(
          AndroidInternetPermissionValidator().validate,
          getCurrentDirectory: () => tempDirectory,
        );

        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            const ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message:
                  '''android/app/src/main/AndroidManifest.xml is missing the INTERNET permission.''',
            ),
          ),
        );
      });
    });

    group('when the INTERNET permission is missing', () {
      test('returns error', () async {
        final tempDirectory = createTempDir();
        final manifestPath =
            p.join(tempDirectory.path, 'android', 'app', 'src', 'main');

        writeManifestToPath(manifestWithNoPermissions, manifestPath);

        final results = await IOOverrides.runZoned(
          AndroidInternetPermissionValidator().validate,
          getCurrentDirectory: () => tempDirectory,
        );

        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            const ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message:
                  '''android/app/src/main/AndroidManifest.xml is missing the INTERNET permission.''',
            ),
          ),
        );
      });
    });

    group('when manifest has non-INTERNET permissions', () {
      test('returns error', () async {
        final tempDirectory = createTempDir();
        final manifestPath =
            p.join(tempDirectory.path, 'android', 'app', 'src', 'main');

        writeManifestToPath(
          manifestWithNonInternetPermissions,
          manifestPath,
        );

        final results = await IOOverrides.runZoned(
          AndroidInternetPermissionValidator().validate,
          getCurrentDirectory: () => tempDirectory,
        );

        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            const ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message:
                  '''android/app/src/main/AndroidManifest.xml is missing the INTERNET permission.''',
            ),
          ),
        );
      });
    });

    group('fix', () {
      test('adds permission to manifest file', () async {
        final tempDirectory = createTempDir();
        writeManifestToPath(
          manifestWithNonInternetPermissions,
          p.join(tempDirectory.path, 'android', 'app', 'src', 'main'),
        );

        var results = await IOOverrides.runZoned(
          AndroidInternetPermissionValidator().validate,
          getCurrentDirectory: () => tempDirectory,
        );
        expect(results, hasLength(1));
        expect(results.first.fix, isNotNull);

        await IOOverrides.runZoned(
          () => results.first.fix!(),
          getCurrentDirectory: () => tempDirectory,
        );

        results = await IOOverrides.runZoned(
          AndroidInternetPermissionValidator().validate,
          getCurrentDirectory: () => tempDirectory,
        );
        expect(results, isEmpty);
      });
    });
  });
}
