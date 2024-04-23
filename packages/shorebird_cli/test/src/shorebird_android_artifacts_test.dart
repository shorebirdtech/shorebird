import 'package:path/path.dart' as path;
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdAndroidArtifacts, () {
    late Directory projectPath;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;

    setUp(() {
      projectPath = Directory.systemTemp.createTempSync();
      shorebirdAndroidArtifacts = ShorebirdAndroidArtifacts();
    });

    test('returns null when cannot find the aab', () {
      expect(
        shorebirdAndroidArtifacts.findAppBundle(
          projectPath: projectPath.path,
          flavor: null,
        ),
        isNull,
      );
    });
    test('returns null when cannot find the apk', () {
      expect(
        shorebirdAndroidArtifacts.findApk(
          projectPath: projectPath.path,
          flavor: null,
        ),
        isNull,
      );
    });

    test('find the app bundle without any flavors', () {
      const artifactPath = 'build/app/outputs/bundle/release/app-release.aab';
      final artifact = File(
        path.join(projectPath.path, artifactPath),
      )..createSync(recursive: true);

      expect(
        shorebirdAndroidArtifacts.findAppBundle(
          projectPath: projectPath.path,
          flavor: null,
        ),
        equals(artifact.path),
      );
    });
    test('find the apk bundle without any flavors', () {
      const artifactPath = 'build/app/outputs/flutter-apk/app-release.apk';
      final artifact = File(
        path.join(projectPath.path, artifactPath),
      )..createSync(recursive: true);

      expect(
        shorebirdAndroidArtifacts.findApk(
          projectPath: projectPath.path,
          flavor: null,
        ),
        equals(artifact.path),
      );
    });

    test('find the app bundle with an one dimensional flavor', () {
      const artifactPath =
          'build/app/outputs/bundle/internalRelease/app-internal-release.aab';
      final artifact = File(
        path.join(projectPath.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'internal';

      expect(
        shorebirdAndroidArtifacts.findAppBundle(
          projectPath: projectPath.path,
          flavor: flavor,
        ),
        equals(artifact.path),
      );
    });
    test('find the apk with an one dimensional flavor', () {
      const artifactPath =
          'build/app/outputs/flutter-apk/app-internal-release.apk';
      final artifact = File(
        path.join(projectPath.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'internal';

      expect(
        shorebirdAndroidArtifacts.findApk(
          projectPath: projectPath.path,
          flavor: flavor,
        ),
        equals(artifact.path),
      );
    });

    test('find the app bundle with multi dimensional flavors', () {
      const artifactPath =
          'build/app/outputs/bundle/stableGlobalRelease/app-stable-global-release.aab';
      final artifact = File(
        path.join(projectPath.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'stableGlobal';

      expect(
        shorebirdAndroidArtifacts.findAppBundle(
          projectPath: projectPath.path,
          flavor: flavor,
        ),
        equals(artifact.path),
      );
    });
    test('find the apk with multi dimensional flavors', () {
      const artifactPath =
          'build/app/outputs/flutter-apk/app-stableglobal-release.apk';
      final artifact = File(
        path.join(projectPath.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'stableGlobal';

      expect(
        shorebirdAndroidArtifacts.findApk(
          projectPath: projectPath.path,
          flavor: flavor,
        ),
        equals(artifact.path),
      );
    });

    test(
        'find the app bundle with multi dimensional flavors and multi '
        'word flavor name', () {
      const artifactPath =
          'build/app/outputs/bundle/stablePlayStoreRelease/app-stable-playStore-release.aab';
      final artifact = File(
        path.join(projectPath.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'stablePlayStore';

      expect(
        shorebirdAndroidArtifacts.findAppBundle(
          projectPath: projectPath.path,
          flavor: flavor,
        ),
        equals(artifact.path),
      );
    });
    test(
        'find the apk with multi dimensional flavors and multi '
        'word flavor name', () {
      const artifactPath =
          'build/app/outputs/flutter-apk/app-stableplaystore-release.apk';
      final artifact = File(
        path.join(projectPath.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'stablePlayStore';

      expect(
        shorebirdAndroidArtifacts.findApk(
          projectPath: projectPath.path,
          flavor: flavor,
        ),
        equals(artifact.path),
      );
    });

    test('throws when finding multiple aab files', () {
      const duplicatedArtifactPath =
          'build/app/outputs/bundle/stablePlayStoreRelease/app---stable-playStore-release.aab';
      File(
        path.join(projectPath.path, duplicatedArtifactPath),
      ).createSync(recursive: true);

      const artifactPath =
          'build/app/outputs/bundle/stablePlayStoreRelease/app-stable-playStore-release.aab';
      File(
        path.join(projectPath.path, artifactPath),
      ).createSync(recursive: true);

      const flavor = 'stablePlayStore';

      expect(
        () => shorebirdAndroidArtifacts.findAppBundle(
          projectPath: projectPath.path,
          flavor: flavor,
        ),
        throwsA(isA<MultipleArtifactsFoundException>()),
      );
    });
    test('throws when finding multiple apk files', () {
      const duplicatedArtifactPath =
          'build/app/outputs/flutter-apk/app----stableplaystore-release.apk';
      File(
        path.join(projectPath.path, duplicatedArtifactPath),
      ).createSync(recursive: true);

      const artifactPath =
          'build/app/outputs/flutter-apk/app-stableplaystore-release.apk';
      File(
        path.join(projectPath.path, artifactPath),
      ).createSync(recursive: true);

      const flavor = 'stablePlayStore';

      expect(
        () => shorebirdAndroidArtifacts.findApk(
          projectPath: projectPath.path,
          flavor: flavor,
        ),
        throwsA(isA<MultipleArtifactsFoundException>()),
      );
    });
  });
}
