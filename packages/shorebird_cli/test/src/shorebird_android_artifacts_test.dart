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

    group('when cannot find artifacts', () {
      group('when no build folder exists', () {
        test('throws ArtifactNotFoundException for aabs', () {
          expect(
            () => shorebirdAndroidArtifacts.findAppBundle(
              project: project,
              flavor: null,
            ),
            throwsA(isA<ArtifactNotFoundException>()),
          );
        });
        test('throws ArtifactNotFoundException for apks', () {
          expect(
            () => shorebirdAndroidArtifacts.findApk(
              project: project,
              flavor: null,
            ),
            throwsA(isA<ArtifactNotFoundException>()),
          );
        });
      });
      group('when build folder exists but not the file', () {
        test('throws ArtifactNotFoundException for aabs', () {
          Directory(
            path.join(
              project.path,
              'build',
              'app',
              'outputs',
              'bundle',
              'release',
            ),
          ).createSync(recursive: true);
          expect(
            () => shorebirdAndroidArtifacts.findAppBundle(
              project: project,
              flavor: null,
            ),
            throwsA(isA<ArtifactNotFoundException>()),
          );
        });
        test('throws ArtifactNotFoundException for apks', () {
          Directory(
            path.join(
              project.path,
              'build',
              'app',
              'outputs',
              'flutter-apk',
            ),
          ).createSync(recursive: true);
          expect(
            () => shorebirdAndroidArtifacts.findApk(
              project: project,
              flavor: null,
            ),
            throwsA(isA<ArtifactNotFoundException>()),
          );
        });
      });
    });

    group('with no flavors', () {
      test('finds the app bundle flavors', () {
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
      test('finds the apk', () {
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
    });

    group('with one dimensional flavor', () {
      test('finds the app bundle', () {
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
      test('finds the apk', () {
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
    });

    group('when with multi dimensional flavors', () {
      test('finds the app bundle with multi dimensional flavors', () {
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
      test('finds the apk with multi dimensional flavors', () {
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
    });

    group('when with multi dimensional flavors and mult word flavor name', () {
      test('finds the app bundle', () {
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
      test('finds the apk', () {
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
    });

    group('when finding multiple files', () {
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
  });
}
