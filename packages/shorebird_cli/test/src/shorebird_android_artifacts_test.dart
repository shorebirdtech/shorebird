import 'package:archive/archive_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/bundletool.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(ShorebirdAndroidArtifacts, () {
    late Directory projectRoot;
    late Bundletool bundletool;
    late Cache cache;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          bundletoolRef.overrideWith(() => bundletool),
          cacheRef.overrideWith(() => cache),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      bundletool = MockBundleTool();
      cache = MockCache();
      logger = MockShorebirdLogger();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();

      when(() => cache.updateAll()).thenAnswer((_) async {});
      when(() => shorebirdEnv.getShorebirdProjectRoot())
          .thenReturn(projectRoot);

      shorebirdAndroidArtifacts = ShorebirdAndroidArtifacts();
    });

    group('when no build folder exists', () {
      test('throws ArtifactNotFoundException for aabs', () {
        expect(
          () => shorebirdAndroidArtifacts.findAab(
            project: projectRoot,
            flavor: null,
          ),
          throwsA(isA<ArtifactNotFoundException>()),
        );
      });

      test('throws ArtifactNotFoundException for apks', () {
        final buildDir = Directory(
          p.join(
            projectRoot.path,
            'build',
            'app',
            'outputs',
            'flutter-apk',
          ),
        );
        expect(
          () => shorebirdAndroidArtifacts.findApk(
            project: projectRoot,
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
          p.join(
            projectRoot.path,
            'build',
            'app',
            'outputs',
            'bundle',
            'release',
          ),
        )..createSync(recursive: true);
        expect(
          () => shorebirdAndroidArtifacts.findAab(
            project: projectRoot,
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
          p.join(
            projectRoot.path,
            'build',
            'app',
            'outputs',
            'flutter-apk',
          ),
        ).createSync(recursive: true);
        expect(
          () => shorebirdAndroidArtifacts.findApk(
            project: projectRoot,
            flavor: null,
          ),
          throwsA(isA<ArtifactNotFoundException>()),
        );
      });
    });

    group('when using no flavors', () {
      test('finds the app bundle flavors', () {
        final artifactPath = p.join(
          'build',
          'app',
          'outputs',
          'bundle',
          'release',
          'app-release.aab',
        );
        final artifact = File(
          p.join(projectRoot.path, artifactPath),
        )..createSync(recursive: true);

        expect(
          shorebirdAndroidArtifacts
              .findAab(
                project: projectRoot,
                flavor: null,
              )
              .path,
          equals(artifact.path),
        );
      });

      test('finds the apk', () {
        final artifactPath = p.join(
          'build',
          'app',
          'outputs',
          'flutter-apk',
          'app-release.apk',
        );
        final artifact = File(
          p.join(projectRoot.path, artifactPath),
        )..createSync(recursive: true);

        expect(
          shorebirdAndroidArtifacts
              .findApk(
                project: projectRoot,
                flavor: null,
              )
              .path,
          equals(artifact.path),
        );
      });
    });

    group('when using single-dimensional flavor', () {
      test('finds the app bundle', () {
        final artifactPath = p.join(
          'build',
          'app',
          'outputs',
          'bundle',
          'internalRelease',
          'app-internal-release.aab',
        );
        final artifact = File(
          p.join(projectRoot.path, artifactPath),
        )..createSync(recursive: true);

        const flavor = 'internal';

        expect(
          shorebirdAndroidArtifacts
              .findAab(
                project: projectRoot,
                flavor: flavor,
              )
              .path,
          equals(artifact.path),
        );
      });

      test('finds the apk', () {
        final artifactPath = p.join(
          'build',
          'app',
          'outputs',
          'flutter-apk',
          'app-internal-release.apk',
        );
        final artifact = File(
          p.join(projectRoot.path, artifactPath),
        )..createSync(recursive: true);

        const flavor = 'internal';

        expect(
          shorebirdAndroidArtifacts
              .findApk(
                project: projectRoot,
                flavor: flavor,
              )
              .path,
          equals(artifact.path),
        );
      });
    });

    group('when using multi-dimensional flavors', () {
      test('finds the app bundle', () {
        final artifactPath = p.join(
          'build',
          'app',
          'outputs',
          'bundle',
          'stableGlobalRelease',
          'app-stable-global-release.aab',
        );
        final artifact = File(
          p.join(projectRoot.path, artifactPath),
        )..createSync(recursive: true);

        const flavor = 'stableGlobal';

        expect(
          shorebirdAndroidArtifacts
              .findAab(
                project: projectRoot,
                flavor: flavor,
              )
              .path,
          equals(artifact.path),
        );
      });

      test('finds the apk', () {
        final artifactPath = p.join(
          'build',
          'app',
          'outputs',
          'flutter-apk',
          'app-stableglobal-release.apk',
        );
        final artifact = File(
          p.join(projectRoot.path, artifactPath),
        )..createSync(recursive: true);

        const flavor = 'stableGlobal';

        expect(
          shorebirdAndroidArtifacts
              .findApk(
                project: projectRoot,
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
        final artifactPath = p.join(
          'build',
          'app',
          'outputs',
          'bundle',
          'stablePlayStoreRelease',
          'app-stable-playStore-release.aab',
        );
        final artifact = File(
          p.join(projectRoot.path, artifactPath),
        )..createSync(recursive: true);

        const flavor = 'stablePlayStore';

        expect(
          shorebirdAndroidArtifacts
              .findAab(
                project: projectRoot,
                flavor: flavor,
              )
              .path,
          equals(artifact.path),
        );
      });

      test('finds the apk', () {
        final artifactPath = p.join(
          'build',
          'app',
          'outputs',
          'flutter-apk',
          'app-stableplaystore-release.apk',
        );
        final artifact = File(
          p.join(projectRoot.path, artifactPath),
        )..createSync(recursive: true);

        const flavor = 'stablePlayStore';

        expect(
          shorebirdAndroidArtifacts
              .findApk(
                project: projectRoot,
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
          p.join(
            projectRoot.path,
            'build',
            'app',
            'outputs',
            'bundle',
            'stablePlayStoreRelease',
          ),
        );
        final duplicatedArtifactPath = p.join(
          buildDir.path,
          'app---stable-playStore-release.aab',
        );
        File(
          p.join(projectRoot.path, duplicatedArtifactPath),
        ).createSync(recursive: true);

        final artifactPath = p.join(
          buildDir.path,
          'app-stable-playStore-release.aab',
        );
        File(
          p.join(projectRoot.path, artifactPath),
        ).createSync(recursive: true);

        const flavor = 'stablePlayStore';

        expect(
          () => shorebirdAndroidArtifacts.findAab(
            project: projectRoot,
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
          p.join(
            projectRoot.path,
            'build',
            'app',
            'outputs',
            'flutter-apk',
          ),
        );
        final duplicatedArtifactPath = p.join(
          buildDir.path,
          'app----stableplaystore-release.apk',
        );
        File(
          p.join(projectRoot.path, duplicatedArtifactPath),
        ).createSync(recursive: true);

        final artifactPath = p.join(
          buildDir.path,
          'app-stableplaystore-release.apk',
        );
        File(
          p.join(projectRoot.path, artifactPath),
        ).createSync(recursive: true);

        const flavor = 'stablePlayStore';

        expect(
          () => shorebirdAndroidArtifacts.findApk(
            project: projectRoot,
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

    group('aarLibraryPath', () {
      test('returns path to AAR library', () {
        expect(
          runWithOverrides(() => ShorebirdAndroidArtifacts.aarLibraryPath),
          equals(
            p.join(
              projectRoot.path,
              'build',
              'host',
              'outputs',
              'repo',
            ),
          ),
        );
      });
    });

    group('aarArtifactDirectory', () {
      test('returns path to AAR artifact directory', () {
        expect(
          runWithOverrides(
            () => ShorebirdAndroidArtifacts.aarArtifactDirectory(
              buildNumber: '1',
              packageName: 'com.example',
            ),
          ),
          equals(
            p.join(
              projectRoot.path,
              'build',
              'host',
              'outputs',
              'repo',
              'com',
              'example',
              'flutter_release',
              '1',
            ),
          ),
        );
      });
    });

    group('aarArtifactPath', () {
      test('returns path to AAR artifact', () {
        final result = runWithOverrides(
          () => ShorebirdAndroidArtifacts.aarArtifactPath(
            packageName: 'com.example',
            buildNumber: '1',
          ),
        );

        expect(
          result,
          equals(
            p.join(
              projectRoot.path,
              'build',
              'host',
              'outputs',
              'repo',
              'com',
              'example',
              'flutter_release',
              '1',
              'flutter_release-1.aar',
            ),
          ),
        );
      });
    });

    group('extractReleaseVersionFromAppBundle', () {
      setUp(() {
        when(() => bundletool.getVersionName(any()))
            .thenAnswer((_) async => '1.2.3');
        when(() => bundletool.getVersionCode(any()))
            .thenAnswer((_) async => '4');
      });

      test('returns version name and code from app bundle', () async {
        const appBundlePath = 'path/to/appbundle';
        expect(
          await runWithOverrides(
            () => shorebirdAndroidArtifacts
                .extractReleaseVersionFromAppBundle(appBundlePath),
          ),
          equals('1.2.3+4'),
        );
        verify(() => cache.updateAll()).called(1);
      });
    });

    group('extractAar', () {
      const buildNumber = '1.0';
      const packageName = 'com.example.my_flutter_module';
      const zippedContents = 'foo';

      void setUpProjectRootArtifacts() {
        final aarDir = p.join(
          projectRoot.path,
          'build',
          'host',
          'outputs',
          'repo',
          'com',
          'example',
          'my_flutter_module',
          'flutter_release',
          buildNumber,
        );
        final aarPath = p.join(aarDir, 'flutter_release-$buildNumber.aar');
        File(aarPath)
          ..createSync(recursive: true)
          ..writeAsStringSync(zippedContents);
        createArchiveFromDirectory(Directory(aarDir));
      }

      setUp(setUpProjectRootArtifacts);

      test('extracts aar', () async {
        final outDir = await runWithOverrides(
          () => shorebirdAndroidArtifacts.extractAar(
            packageName: packageName,
            buildNumber: buildNumber,
            unzipFn: (_, __) async {},
          ),
        );

        expect(
          outDir.path,
          endsWith(
            p.join(
              'build',
              'host',
              'outputs',
              'repo',
              'com',
              'example',
              'my_flutter_module',
              'flutter_release',
              buildNumber,
              'flutter_release-$buildNumber',
            ),
          ),
        );
        expect(
          File('${outDir.path}.aar').readAsStringSync(),
          equals(zippedContents),
        );
      });
    });
  });
}
