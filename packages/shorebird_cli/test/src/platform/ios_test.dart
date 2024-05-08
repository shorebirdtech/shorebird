import 'dart:io';

import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
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
    late Ios ios;

    setUp(() {
      ios = Ios();
    });

    group('exportOptionsPlistFromArgs', () {
      late ArgResults argResults;

      setUp(() {
        argResults = MockArgResults();

        when(() => argResults.wasParsed(any())).thenReturn(false);
        when(() => argResults.options).thenReturn([
          exportMethodArgName,
          exportOptionsPlistArgName,
        ]);
      });

      group('when both export-method and export-options-plist are provided',
          () {
        setUp(() {
          when(
            () => argResults.wasParsed(exportMethodArgName),
          ).thenReturn(true);
          when(
            () => argResults[exportOptionsPlistArgName],
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
          when(() => argResults.wasParsed(exportMethodArgName))
              .thenReturn(true);
          when(() => argResults[exportMethodArgName])
              .thenReturn(ExportMethod.adHoc.argName);
          when(() => argResults[exportOptionsPlistArgName]).thenReturn(null);
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
              () => argResults[exportOptionsPlistArgName],
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
              () => argResults[exportOptionsPlistArgName],
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
          when(() => argResults.wasParsed(exportMethodArgName))
              .thenReturn(false);
          when(() => argResults[exportOptionsPlistArgName]).thenReturn(null);
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
              .thenReturn([exportOptionsPlistArgName]);
        });

        test('does not check whether export-method was parsed', () {
          ios.exportOptionsPlistFromArgs(argResults);
          verifyNever(() => argResults.wasParsed(exportMethodArgName));
        });
      });
    });
  });
}
