import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:test/test.dart';
import '../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group('DirectoryArchive', () {
    group('zipToTempFile', () {
      test('zips directory to location in system temp', () async {
        const numFiles = 500;
        final directoryToZip = Directory.systemTemp.createTempSync();
        for (var i = 0; i < numFiles; i++) {
          File('${directoryToZip.path}/$i.txt')
            ..createSync()
            ..writeAsStringSync('$i');
        }

        final zipFile = await directoryToZip.zipToTempFile();
        expect(zipFile.existsSync(), isTrue);
        expect(p.extension(zipFile.path), equals('.zip'));

        final tempDir = await Directory.systemTemp.createTemp();
        await extractFileToDisk(zipFile.path, tempDir.path);
        final extractedContents = tempDir.listSync(recursive: true);
        expect(extractedContents, hasLength(numFiles));
        for (var i = 0; i < numFiles; i++) {
          final extractedFile = extractedContents.whereType<File>().firstWhere(
            (entity) => p.basename(entity.path) == '$i.txt',
          );
          expect(extractedFile.existsSync(), isTrue);
          expect(extractedFile.readAsStringSync(), equals('$i'));
        }
      });
    });

    group('zipInto', () {
      late Directory directoryToZip;
      late Directory outDirectory;

      setUp(() {
        directoryToZip = Directory(
          p.join(Directory.systemTemp.createTempSync().path, 'my_dir'),
        )..createSync();
        File(p.join(directoryToZip.path, 'a.txt')).writeAsStringSync('a');
        outDirectory = Directory.systemTemp.createTempSync();
      });

      test('zips directory into the given directory', () async {
        final zipFile = await directoryToZip.zipInto(outDirectory);

        expect(zipFile.path, equals(p.join(outDirectory.path, 'my_dir.zip')));
        expect(zipFile.existsSync(), isTrue);

        final extractDir = Directory.systemTemp.createTempSync();
        await extractFileToDisk(zipFile.path, extractDir.path);
        final extracted = File(p.join(extractDir.path, 'a.txt'));
        expect(extracted.readAsStringSync(), equals('a'));
      });

      test('names the zip after name when provided', () async {
        final zipFile = await directoryToZip.zipInto(
          outDirectory,
          name: 'other',
        );

        expect(zipFile.path, equals(p.join(outDirectory.path, 'other.zip')));
        expect(zipFile.existsSync(), isTrue);
      });
    });
  });
}
