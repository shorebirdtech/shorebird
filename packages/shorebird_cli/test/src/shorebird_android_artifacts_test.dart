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

    group('when no build folder exists', () {
      test('throws ArtifactNotFoundException for aabs', () {
        expect(
          () => shorebirdAndroidArtifacts.findAab(
            project: project,
            flavor: null,
          ),
          throwsA(isA<ArtifactNotFoundException>()),
        );
      });

      test('throws ArtifactNotFoundException for apks', () {
        final buildDir = Directory(
          path.join(
            project.path,
            'build',
            'app',
            'outputs',
            'flutter-apk',
          ),
        );
        expect(
          () => shorebirdAndroidArtifacts.findApk(
            project: project,
            flavor: null,
          ),
          throwsA(
            isA<ArtifactNotFoundException>().having(
              (exception) => exception.toString(),
              'message',
              equals('Artifact app-release.apk not found in ${buildDir.path}'),
            ),
          ),
        );
      });
    });

    group('when build folder exists but not the file', () {
      test('throws ArtifactNotFoundException for aabs', () {
        final buildDir = Directory(
          path.join(
            project.path,
            'build',
            'app',
            'outputs',
            'bundle',
            'release',
          ),
        )..createSync(recursive: true);
        expect(
          () => shorebirdAndroidArtifacts.findAab(
            project: project,
            flavor: null,
          ),
          throwsA(
            isA<ArtifactNotFoundException>().having(
              (exception) => exception.toString(),
              'message',
              equals('Artifact app-release.aab not found in ${buildDir.path}'),
            ),
          ),
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

    group('when using no flavors', () {
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
              .findAab(
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

    group('when using single-dimensional flavor', () {
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
              .findAab(
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

    group('when using multi-dimensional flavors', () {
      test('finds the app bundle', () {
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
              .findAab(
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

    group('when using multi-dimensional flavors and multi-word flavor name',
        () {
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
              .findAab(
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

    group('when multiple files are found', () {
      test('throws MultipleArtifactsFoundException when looking for aab', () {
        final buildDir = Directory(
          path.join(
            project.path,
            'build',
            'app',
            'outputs',
            'bundle',
            'stablePlayStoreRelease',
          ),
        );
        final duplicatedArtifactPath = path.join(
          buildDir.path,
          'app---stable-playStore-release.aab',
        );
        File(
          path.join(project.path, duplicatedArtifactPath),
        ).createSync(recursive: true);

        final artifactPath = path.join(
          buildDir.path,
          'app-stable-playStore-release.aab',
        );
        File(
          path.join(project.path, artifactPath),
        ).createSync(recursive: true);

        const flavor = 'stablePlayStore';

        expect(
          () => shorebirdAndroidArtifacts.findAab(
            project: project,
            flavor: flavor,
          ),
          throwsA(
            isA<MultipleArtifactsFoundException>().having(
              (exception) => exception.toString(),
              'message',
              equals('Multiple artifacts found in ${buildDir.path}: '
                  '($duplicatedArtifactPath, $artifactPath)'),
            ),
          ),
        );
      });

      test('throws MultipleArtifactsFoundException when looking for apk', () {
        final buildDir = Directory(
          path.join(
            project.path,
            'build',
            'app',
            'outputs',
            'flutter-apk',
          ),
        );
        final duplicatedArtifactPath = path.join(
          buildDir.path,
          'app----stableplaystore-release.apk',
        );
        File(
          path.join(project.path, duplicatedArtifactPath),
        ).createSync(recursive: true);

        final artifactPath = path.join(
          buildDir.path,
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
          throwsA(
            isA<MultipleArtifactsFoundException>().having(
              (exception) => exception.toString(),
              'message',
              equals('Multiple artifacts found in ${buildDir.path}: '
                  '($duplicatedArtifactPath, $artifactPath)'),
            ),
          ),
        );
      });
    });
  });
}
