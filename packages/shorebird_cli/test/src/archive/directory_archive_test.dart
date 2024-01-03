import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

void main() {
  group('DirectoryArchive', () {
    group('zipToTempFile', () {
      test('zips directory to location in system temp', () async {
        final directoryToZip = Directory.systemTemp.createTempSync();
        File('${directoryToZip.path}/a.txt')
          ..createSync()
          ..writeAsStringSync('a');
        File('${directoryToZip.path}/b.txt')
          ..createSync()
          ..writeAsStringSync('b');

        final zipFile = await directoryToZip.zipToTempFile();

        expect(zipFile.existsSync(), isTrue);
        expect(p.extension(zipFile.path), equals('.zip'));

        final tempDir = await Directory.systemTemp.createTemp();
        await extractFileToDisk(zipFile.path, tempDir.path);
        final extractedContents = tempDir.listSync(recursive: true);
        expect(extractedContents, hasLength(2));

        final extractedFileA = extractedContents.whereType<File>().firstWhere(
              (entity) => p.basename(entity.path) == 'a.txt',
            );
        final extractedFileB = extractedContents.whereType<File>().firstWhere(
              (entity) => p.basename(entity.path) == 'b.txt',
            );
        expect(extractedFileA.existsSync(), isTrue);
        expect(extractedFileB.existsSync(), isTrue);
        expect(extractedFileA.readAsStringSync(), equals('a'));
        expect(extractedFileB.readAsStringSync(), equals('b'));
      });
    });
  });
}
