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

  group(Ios, () {
    late ShorebirdEnv shorebirdEnv;
    late Ios ios;

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
      ios = Ios();
    });

    group(MissingIOSProjectException, () {
      test('toString', () {
        const exception = MissingIOSProjectException('test_project_path');
        expect(
          exception.toString(),
          '''
Could not find an iOS project in test_project_path.
To add iOS, run "flutter create . --platforms ios"''',
        );
      });
    });

    group('flavors', () {
      final schemesPath = p.join(
        'ios',
        'Runner.xcodeproj',
        'xcshareddata',
        'xcschemes',
      );
      late Directory projectRoot;

      void copyFixturesToProjectRoot() {
        final fixturesDir = Directory(p.join('test', 'fixtures', 'xcschemes'));
        for (final file in fixturesDir.listSync().whereType<File>()) {
          final destination = File(
            p.join(projectRoot.path, schemesPath, p.basename(file.path)),
          )..createSync(recursive: true);
          file.copySync(destination.path);
        }
      }

      setUp(() {
        projectRoot = Directory.systemTemp.createTempSync();
        when(() => shorebirdEnv.getFlutterProjectRoot())
            .thenReturn(projectRoot);
      });

      group('when ios directory does not exist', () {
        test('returns null', () {
          expect(runWithOverrides(() => ios.flavors()), isNull);
        });
      });

      group('when xcodeproj does not exist', () {
        setUp(() {
          copyFixturesToProjectRoot();
          Directory(
            p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
          ).deleteSync(recursive: true);
        });

        test('throws exception', () {
          expect(
            () => runWithOverrides(ios.flavors),
            throwsA(isA<MissingIOSProjectException>()),
          );
        });
      });

      group('when xcschemes directory does not exist', () {
        setUp(() {
          copyFixturesToProjectRoot();
          Directory(
            p.join(projectRoot.path, 'ios', 'Runner.xcodeproj', 'xcshareddata'),
          ).deleteSync(recursive: true);
        });

        test('throws exception', () {
          expect(() => runWithOverrides(ios.flavors), throwsException);
        });
      });

      group('when only Runner scheme exists', () {
        setUp(() {
          copyFixturesToProjectRoot();
          final schemesDir = Directory(p.join(projectRoot.path, schemesPath));
          for (final schemeFile in schemesDir.listSync().whereType<File>()) {
            if (p.basenameWithoutExtension(schemeFile.path) != 'Runner') {
              schemeFile.deleteSync();
            }
          }
        });

        test('returns no flavors', () {
          expect(runWithOverrides(ios.flavors), isEmpty);
        });
      });

      group('when extension and non-extension schemes exist', () {
        setUp(copyFixturesToProjectRoot);

        test('returns only non-extension schemes', () {
          expect(runWithOverrides(ios.flavors), {'internal', 'beta', 'stable'});
        });
      });

      group('when Runner has been renamed', () {
        setUp(() {
          copyFixturesToProjectRoot();
          Directory(
            p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
          ).renameSync(
            p.join(projectRoot.path, 'ios', 'RenamedRunner.xcodeproj'),
          );
        });

        test('returns only non-extension schemes', () {
          expect(runWithOverrides(ios.flavors), {'internal', 'beta', 'stable'});
        });
      });
    });
  });
}
