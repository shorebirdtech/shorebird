import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:test/test.dart';

void main() {
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
  });
}
