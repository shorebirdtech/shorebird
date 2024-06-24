import 'dart:io';

import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
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

    group('exportOptionsPlistFromArgs', () {
      late ArgResults argResults;

      setUp(() {
        argResults = MockArgResults();

        when(() => argResults.wasParsed(any())).thenReturn(false);
        when(() => argResults.options).thenReturn([
          CommonArguments.exportMethodArg.name,
          CommonArguments.exportOptionsPlistArg.name,
        ]);
      });

      group('when both export-method and export-options-plist are provided',
          () {
        setUp(() {
          when(
            () => argResults.wasParsed(CommonArguments.exportMethodArg.name),
          ).thenReturn(true);
          when(
            () => argResults[CommonArguments.exportOptionsPlistArg.name],
          ).thenReturn('/path/to/export.plist');
        });

        test('throws ArgumentError', () {
          expect(
            () => ios.exportOptionsPlistFromArgs(argResults),
            throwsArgumentError,
          );
        });
      });

      group('when export-method is provided', () {
        setUp(() {
          when(() => argResults.wasParsed(CommonArguments.exportMethodArg.name))
              .thenReturn(true);
          when(() => argResults[CommonArguments.exportMethodArg.name])
              .thenReturn(ExportMethod.adHoc.argName);
          when(() => argResults[CommonArguments.exportOptionsPlistArg.name])
              .thenReturn(null);
        });

        test('generates an export options plist with that export method',
            () async {
          final exportOptionsPlistFile = ios.exportOptionsPlistFromArgs(
            argResults,
          );
          final exportOptionsPlist = Plist(file: exportOptionsPlistFile);
          expect(
            exportOptionsPlist.properties['method'],
            ExportMethod.adHoc.argName,
          );
        });
      });

      group('when export-options-plist is provided', () {
        group('when file does not exist', () {
          setUp(() {
            when(
              () => argResults[CommonArguments.exportOptionsPlistArg.name],
            ).thenReturn('/does/not/exist');
          });

          test('throws a FileSystemException', () async {
            expect(
              () => ios.exportOptionsPlistFromArgs(argResults),
              throwsA(
                isA<FileSystemException>().having(
                  (e) => e.message,
                  'message',
                  '''Export options plist file /does/not/exist does not exist''',
                ),
              ),
            );
          });
        });

        group('when manageAppVersionAndBuildNumber is not set to false', () {
          const exportPlistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
''';

          test('throws InvalidExportOptionsPlistException', () async {
            final tmpDir = Directory.systemTemp.createTempSync();
            final exportPlistFile = File(
              p.join(tmpDir.path, 'export.plist'),
            )..writeAsStringSync(exportPlistContent);
            when(
              () => argResults[CommonArguments.exportOptionsPlistArg.name],
            ).thenReturn(exportPlistFile.path);
            expect(
              () => ios.exportOptionsPlistFromArgs(argResults),
              throwsA(
                isA<InvalidExportOptionsPlistException>().having(
                  (e) => e.message,
                  'message',
                  '''Export options plist ${exportPlistFile.path} does not set manageAppVersionAndBuildNumber to false. This is required for shorebird to work.''',
                ),
              ),
            );
          });
        });
      });

      group('when neither export-method nor export-options-plist is provided',
          () {
        setUp(() {
          when(() => argResults.wasParsed(CommonArguments.exportMethodArg.name))
              .thenReturn(false);
          when(() => argResults[CommonArguments.exportOptionsPlistArg.name])
              .thenReturn(null);
        });

        test('generates an export options plist with app-store export method',
            () async {
          final exportOptionsPlistFile =
              ios.exportOptionsPlistFromArgs(argResults);
          final exportOptionsPlist = Plist(file: exportOptionsPlistFile);
          expect(
            exportOptionsPlist.properties['method'],
            ExportMethod.appStore.argName,
          );

          final exportOptionsPlistMap =
              PropertyListSerialization.propertyListWithString(
            exportOptionsPlistFile.readAsStringSync(),
          ) as Map<String, Object>;
          expect(
            exportOptionsPlistMap['manageAppVersionAndBuildNumber'],
            isFalse,
          );
          expect(exportOptionsPlistMap['signingStyle'], 'automatic');
          expect(exportOptionsPlistMap['uploadBitcode'], isFalse);
          expect(exportOptionsPlistMap['method'], 'app-store');
        });
      });

      group('when export-method option does not exist', () {
        setUp(() {
          when(() => argResults.options)
              .thenReturn([CommonArguments.exportOptionsPlistArg.name]);
        });

        test('does not check whether export-method was parsed', () {
          ios.exportOptionsPlistFromArgs(argResults);
          verifyNever(
            () => argResults.wasParsed(CommonArguments.exportMethodArg.name),
          );
        });
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
