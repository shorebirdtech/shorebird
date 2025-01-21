import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(InvalidExportOptionsPlistException, () {
    test('toString', () {
      final exception = InvalidExportOptionsPlistException('message');
      expect(exception.toString(), 'message');
    });
  });

  group(Apple, () {
    late ShorebirdEnv shorebirdEnv;
    late Apple apple;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      apple = Apple();
    });

    group(MissingXcodeProjectException, () {
      test('toString', () {
        const exception = MissingXcodeProjectException('test_project_path');
        expect(
          exception.toString(),
          '''
Could not find an Xcode project in test_project_path.
To add iOS, run "flutter create . --platforms ios"
To add macOS, run "flutter create . --platforms macos"''',
        );
      });
    });

    group('flavors', () {
      late Directory projectRoot;

      void copyFixturesToProjectRoot({required String schemesPath}) {
        if (!projectRoot.existsSync()) {
          return;
        }

        final fixturesDir = Directory(
          p.join(
            'test',
            'fixtures',
            'xcschemes',
          ),
        );
        for (final file in fixturesDir.listSync().whereType<File>()) {
          final destination = File(
            p.join(
              projectRoot.path,
              schemesPath,
              p.basename(file.path),
            ),
          )..createSync(recursive: true);
          file.copySync(destination.path);
        }
      }

      setUp(() {
        projectRoot = Directory.systemTemp.createTempSync();
        when(() => shorebirdEnv.getFlutterProjectRoot())
            .thenReturn(projectRoot);
      });

      group('ios', () {
        final schemesPath = p.join(
          'ios',
          'Runner.xcodeproj',
          'xcshareddata',
          'xcschemes',
        );

        setUp(() {
          copyFixturesToProjectRoot(schemesPath: schemesPath);
        });

        group('when ios directory does not exist', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'ios'),
            ).deleteSync(recursive: true);
          });

          test('returns null', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              isNull,
            );
          });
        });

        group('when xcodeproj does not exist', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
            ).deleteSync(recursive: true);
          });

          test('throws exception', () {
            expect(
              () => runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              throwsA(isA<MissingXcodeProjectException>()),
            );
          });
        });

        group('when xcschemes directory does not exist', () {
          setUp(() {
            Directory(
              p.join(
                projectRoot.path,
                'ios',
                'Runner.xcodeproj',
                'xcshareddata',
              ),
            ).deleteSync(recursive: true);
          });

          test('throws exception', () {
            expect(
              () => runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              throwsException,
            );
          });
        });

        group('when only Runner scheme exists', () {
          setUp(() {
            final schemesDir = Directory(p.join(projectRoot.path, schemesPath));
            for (final schemeFile in schemesDir.listSync().whereType<File>()) {
              if (p.basenameWithoutExtension(schemeFile.path) != 'Runner') {
                schemeFile.deleteSync();
              }
            }
          });

          test('returns no flavors', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              isEmpty,
            );
          });
        });

        group('when extension and non-extension schemes exist', () {
          test('returns only non-extension schemes', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              {'internal', 'beta', 'stable'},
            );
          });
        });

        group('when Runner has been renamed', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
            ).renameSync(
              p.join(projectRoot.path, 'ios', 'RenamedRunner.xcodeproj'),
            );
          });

          test('returns only non-extension schemes', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              {'internal', 'beta', 'stable'},
            );
          });
        });
      });

      group('macos', () {
        final schemesPath = p.join(
          'macos',
          'Runner.xcodeproj',
          'xcshareddata',
          'xcschemes',
        );

        setUp(() {
          copyFixturesToProjectRoot(schemesPath: schemesPath);
        });

        group('when macOS directory does not exist', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'macos'),
            ).deleteSync(recursive: true);
          });

          test('returns null', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.macos),
              ),
              isNull,
            );
          });
        });

        group('when Xcode project does not exist', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'macos', 'Runner.xcodeproj'),
            ).deleteSync(recursive: true);
          });

          test('throws MissingXcodeProjectException', () {
            expect(
              () => runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.macos),
              ),
              throwsA(isA<MissingXcodeProjectException>()),
            );
          });
        });

        group('when schemes directory does not exist', () {
          setUp(() {
            Directory(
              p.join(
                projectRoot.path,
                'macos',
                'Runner.xcodeproj',
                'xcshareddata',
              ),
            ).deleteSync(recursive: true);
          });

          test('throws Exception', () {
            expect(
              () => runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.macos),
              ),
              throwsException,
            );
          });
        });

        group('when schemes are found', () {
          test('returns all schemes except Runner', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.macos),
              ),
              {'internal', 'beta', 'stable'},
            );
          });
        });
      });
    });
  });
}
