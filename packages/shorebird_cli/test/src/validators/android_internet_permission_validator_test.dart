import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

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

  // A stock AndroidManifest.xml from `flutter create`.
  const stockFlutterManifest = r'''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="xml"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
''';

  group(AndroidInternetPermissionValidator, () {
    late Directory projectRoot;
    late ShorebirdEnv shorebirdEnv;

    void writeManifestToPath(String manifestContents, String path) {
      Directory(path).createSync(recursive: true);
      File(
        p.join(path, 'AndroidManifest.xml'),
      ).writeAsStringSync(manifestContents);
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

      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);
    });

    test('has a non-empty description', () {
      expect(AndroidInternetPermissionValidator().description, isNotEmpty);
    });

    group('canRunInContext', () {
      test('returns false if no android src directory exists', () {
        final result = runWithOverrides(
          () => AndroidInternetPermissionValidator().canRunInCurrentContext(),
        );

        expect(result, isFalse);
      });

      test('returns true if an android src directory exists', () {
        writeManifestToPath(
          manifestWithInternetPermission,
          p.join(projectRoot.path, 'android', 'app', 'src', 'main'),
        );

        final result = runWithOverrides(
          () => AndroidInternetPermissionValidator().canRunInCurrentContext(),
        );

        expect(result, isTrue);
      });
    });

    test(
      '''returns successful result if the main AndroidManifest.xml file has the INTERNET permission''',
      () async {
        writeManifestToPath(
          manifestWithInternetPermission,
          p.join(projectRoot.path, 'android', 'app', 'src', 'main'),
        );

        final results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );

        expect(results.map((res) => res.severity), isEmpty);
      },
    );

    test(
      'returns an error if AndroidManifest.xml file does not exist',
      () async {
        Directory(
          p.join(projectRoot.path, 'android', 'app', 'src', 'main'),
        ).createSync(recursive: true);

        final results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.error);
        expect(
          results.first.message,
          startsWith('No AndroidManifest.xml file found at'),
        );
        expect(results.first.fix, isNull);
      },
    );

    group('when the INTERNET permission is commented out', () {
      test('returns error', () async {
        final manifestPath = p.join(
          projectRoot.path,
          'android',
          'app',
          'src',
          'main',
        );

        writeManifestToPath(
          manifestWithCommentedOutInternetPermission,
          manifestPath,
        );

        final results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );

        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message:
                  '''${p.join('android', 'app', 'src', 'main', 'AndroidManifest.xml')} is missing the INTERNET permission.''',
            ),
          ),
        );
      });
    });

    group('when the INTERNET permission is missing', () {
      test('returns error', () async {
        final manifestPath = p.join(
          projectRoot.path,
          'android',
          'app',
          'src',
          'main',
        );

        writeManifestToPath(manifestWithNoPermissions, manifestPath);

        final results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );

        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message:
                  '''${p.join('android', 'app', 'src', 'main', 'AndroidManifest.xml')} is missing the INTERNET permission.''',
            ),
          ),
        );
      });
    });

    group('when manifest has non-INTERNET permissions', () {
      test('returns error', () async {
        final manifestPath = p.join(
          projectRoot.path,
          'android',
          'app',
          'src',
          'main',
        );

        writeManifestToPath(manifestWithNonInternetPermissions, manifestPath);

        final results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );

        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message:
                  '''${p.join('android', 'app', 'src', 'main', 'AndroidManifest.xml')} is missing the INTERNET permission.''',
            ),
          ),
        );
      });
    });

    group('fix', () {
      test('adds permission to manifest file', () async {
        writeManifestToPath(
          manifestWithNonInternetPermissions,
          p.join(projectRoot.path, 'android', 'app', 'src', 'main'),
        );

        var results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );
        expect(results, hasLength(1));
        expect(results.first.fix, isNotNull);

        await runWithOverrides(() => results.first.fix!());

        results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );
        expect(results, isEmpty);
      });

      test('preserves formatting of stock Flutter manifest', () async {
        final manifestPath = p.join(
          projectRoot.path,
          'android',
          'app',
          'src',
          'main',
        );
        writeManifestToPath(stockFlutterManifest, manifestPath);

        final results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );
        expect(results, hasLength(1));
        await runWithOverrides(() => results.first.fix!());

        final updated = File(
          p.join(manifestPath, 'AndroidManifest.xml'),
        ).readAsStringSync();
        final originalLines = stockFlutterManifest.split('\n');
        final updatedLines = updated.split('\n');
        // Should only add one line.
        expect(updatedLines.length, originalLines.length + 1);
        // First line is the manifest tag, unchanged.
        expect(updatedLines[0], originalLines[0]);
        // Second line is the new permission.
        expect(
          updatedLines[1],
          '    <uses-permission '
          'android:name="android.permission.INTERNET"/>',
        );
        // Remaining lines are identical to the original.
        for (var i = 1; i < originalLines.length; i++) {
          expect(updatedLines[i + 1], originalLines[i]);
        }
      });

      test('preserves existing formatting', () async {
        final manifestPath = p.join(
          projectRoot.path,
          'android',
          'app',
          'src',
          'main',
        );
        writeManifestToPath(manifestWithNoPermissions, manifestPath);

        final results = await runWithOverrides(
          AndroidInternetPermissionValidator().validate,
        );
        await runWithOverrides(() => results.first.fix!());

        final updated = File(
          p.join(manifestPath, 'AndroidManifest.xml'),
        ).readAsStringSync();
        // The permission should be inserted after <manifest> with matching
        // indentation, and the rest of the file should be unchanged.
        expect(
          updated,
          contains(
            '    <uses-permission '
            'android:name="android.permission.INTERNET"/>',
          ),
        );
        // Original closing tag should remain untouched.
        expect(updated, contains('</manifest>'));
        // Should not collapse attributes onto one line (no reformatting).
        expect(
          updated,
          contains(
            '    package="dev.shorebird.u_shorebird_clock">',
          ),
        );
      });
    });
  });
}
