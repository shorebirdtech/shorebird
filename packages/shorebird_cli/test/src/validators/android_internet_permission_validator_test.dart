import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

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

  group('AndroidInternetPermissionValidator', () {
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      shorebirdProcess = _MockShorebirdProcess();
    });

    Directory createTempDir() => Directory.systemTemp.createTempSync();

    void writeManifestToPath(String manifestContents, String path) {
      Directory(path).createSync(recursive: true);
      File(p.join(path, 'AndroidManifest.xml'))
          .writeAsStringSync(manifestContents);
    }

    test(
      'returns successful result if all AndroidManifest.xml files have the '
      'INTERNET permission',
      () async {
        final tempDirectory = createTempDir();
        writeManifestToPath(
          manifestWithInternetPermission,
          p.join(tempDirectory.path, 'android', 'app', 'src', 'debug'),
        );
        writeManifestToPath(
          manifestWithInternetPermission,
          p.join(tempDirectory.path, 'android', 'app', 'src', 'main'),
        );

        final results = await IOOverrides.runZoned(
          () => AndroidInternetPermissionValidator().validate(shorebirdProcess),
          getCurrentDirectory: () => tempDirectory,
        );

        expect(results.map((res) => res.severity), isEmpty);
      },
    );

    test('returns an error if no android project is found', () async {
      final results =
          await AndroidInternetPermissionValidator().validate(shorebirdProcess);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(results.first.message, 'No Android project found');
    });

    test('returns an error if no AndroidManifest.xml files are found',
        () async {
      final tempDirectory = createTempDir();
      Directory(p.join(tempDirectory.path, 'android', 'app', 'src', 'debug'))
          .createSync(recursive: true);

      final results = await IOOverrides.runZoned(
        () => AndroidInternetPermissionValidator().validate(shorebirdProcess),
        getCurrentDirectory: () => tempDirectory,
      );

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(
        results.first.message,
        startsWith('No AndroidManifest.xml files found in'),
      );
    });

    test(
      'returns separate errors for all AndroidManifest.xml files without the '
      'INTERNET permission',
      () async {
        final tempDirectory = createTempDir();
        final manifestPaths = [
          'internet_permission',
          'debug',
          'main',
          'profile',
        ]
            .map(
              (dir) => p.join(
                tempDirectory.path,
                'android',
                'app',
                'src',
                dir,
              ),
            )
            .toList();
        final badManifestPaths = manifestPaths.slice(1);

        writeManifestToPath(
          manifestWithInternetPermission,
          manifestPaths[0],
        );
        writeManifestToPath(
          manifestWithCommentedOutInternetPermission,
          manifestPaths[1],
        );
        writeManifestToPath(
          manifestWithNonInternetPermissions,
          manifestPaths[2],
        );
        writeManifestToPath(
          manifestWithNoPermissions,
          manifestPaths[3],
        );

        final results = await IOOverrides.runZoned(
          () => AndroidInternetPermissionValidator().validate(shorebirdProcess),
          getCurrentDirectory: () => tempDirectory,
        );

        expect(results, hasLength(3));

        expect(
          results,
          containsAll(
            badManifestPaths.map(
              (path) => ValidationIssue(
                severity: ValidationIssueSeverity.error,
                message:
                    '${p.join(path, 'AndroidManifest.xml')} is missing the '
                    'INTERNET permission.',
              ),
            ),
          ),
        );
      },
    );
  });
}
