import 'package:path/path.dart' as path;
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdAndroidArtifacts, () {
    late Directory project;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;

    setUp(() {
      project = Directory.systemTemp.createTempSync();
      shorebirdAndroidArtifacts = ShorebirdAndroidArtifacts();
    });

    test('throws ArtifactNotFoundException when cannot find the aab', () {
      expect(
        () => shorebirdAndroidArtifacts.findAppBundle(
          project: project,
          flavor: null,
        ),
        throwsA(isA<ArtifactNotFoundException>()),
      );
    });

    test('throws ArtifactNotFoundException when cannot find the apk', () {
      expect(
        () => shorebirdAndroidArtifacts.findApk(
          project: project,
          flavor: null,
        ),
        throwsA(isA<ArtifactNotFoundException>()),
      );
    });

    test('finds the app bundle without any flavors', () {
      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'bundle',
        'release',
        'app-release.aab',
      );
      final artifact = File(
        path.join(project.path, artifactPath),
      )..createSync(recursive: true);

      expect(
        shorebirdAndroidArtifacts
            .findAppBundle(
              project: project,
              flavor: null,
            )
            .path,
        equals(artifact.path),
      );
    });
    test('find the apk bundle without any flavors', () {
      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-release.apk',
      );
      final artifact = File(
        path.join(project.path, artifactPath),
      )..createSync(recursive: true);

      expect(
        shorebirdAndroidArtifacts
            .findApk(
              project: project,
              flavor: null,
            )
            .path,
        equals(artifact.path),
      );
    });

    test('find the app bundle with an one dimensional flavor', () {
      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'bundle',
        'internalRelease',
        'app-internal-release.aab',
      );
      final artifact = File(
        path.join(project.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'internal';

      expect(
        shorebirdAndroidArtifacts
            .findAppBundle(
              project: project,
              flavor: flavor,
            )
            .path,
        equals(artifact.path),
      );
    });
    test('find the apk with an one dimensional flavor', () {
      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-internal-release.apk',
      );
      final artifact = File(
        path.join(project.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'internal';

      expect(
        shorebirdAndroidArtifacts
            .findApk(
              project: project,
              flavor: flavor,
            )
            .path,
        equals(artifact.path),
      );
    });

    test('find the app bundle with multi dimensional flavors', () {
      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'bundle',
        'stableGlobalRelease',
        'app-stable-global-release.aab',
      );
      final artifact = File(
        path.join(project.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'stableGlobal';

      expect(
        shorebirdAndroidArtifacts
            .findAppBundle(
              project: project,
              flavor: flavor,
            )
            .path,
        equals(artifact.path),
      );
    });
    test('find the apk with multi dimensional flavors', () {
      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-stableglobal-release.apk',
      );
      final artifact = File(
        path.join(project.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'stableGlobal';

      expect(
        shorebirdAndroidArtifacts
            .findApk(
              project: project,
              flavor: flavor,
            )
            .path,
        equals(artifact.path),
      );
    });

    test(
        'find the app bundle with multi dimensional flavors and multi '
        'word flavor name', () {
      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'bundle',
        'stablePlayStoreRelease',
        'app-stable-playStore-release.aab',
      );
      final artifact = File(
        path.join(project.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'stablePlayStore';

      expect(
        shorebirdAndroidArtifacts
            .findAppBundle(
              project: project,
              flavor: flavor,
            )
            .path,
        equals(artifact.path),
      );
    });
    test(
        'find the apk with multi dimensional flavors and multi '
        'word flavor name', () {
      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-stableplaystore-release.apk',
      );
      final artifact = File(
        path.join(project.path, artifactPath),
      )..createSync(recursive: true);

      const flavor = 'stablePlayStore';

      expect(
        shorebirdAndroidArtifacts
            .findApk(
              project: project,
              flavor: flavor,
            )
            .path,
        equals(artifact.path),
      );
    });

    test('throws when finding multiple aab files', () {
      final duplicatedArtifactPath = path.join(
        'build',
        'app',
        'outputs',
        'bundle',
        'stablePlayStoreRelease',
        'app---stable-playStore-release.aab',
      );
      File(
        path.join(project.path, duplicatedArtifactPath),
      ).createSync(recursive: true);

      const artifactPath =
          'build/app/outputs/bundle/stablePlayStoreRelease/app-stable-playStore-release.aab';
      File(
        path.join(project.path, artifactPath),
      ).createSync(recursive: true);

      const flavor = 'stablePlayStore';

      expect(
        () => shorebirdAndroidArtifacts.findAppBundle(
          project: project,
          flavor: flavor,
        ),
        throwsA(isA<MultipleArtifactsFoundException>()),
      );
    });
    test('throws when finding multiple apk files', () {
      final duplicatedArtifactPath = path.join(
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app----stableplaystore-release.apk',
      );
      File(
        path.join(project.path, duplicatedArtifactPath),
      ).createSync(recursive: true);

      final artifactPath = path.join(
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-stableplaystore-release.apk',
      );
      File(
        path.join(project.path, artifactPath),
      ).createSync(recursive: true);

      const flavor = 'stablePlayStore';

      expect(
        () => shorebirdAndroidArtifacts.findApk(
          project: project,
          flavor: flavor,
        ),
        throwsA(isA<MultipleArtifactsFoundException>()),
      );
    });
  });
}
