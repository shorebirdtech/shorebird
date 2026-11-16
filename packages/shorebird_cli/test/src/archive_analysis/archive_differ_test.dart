import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';
import 'package:test/test.dart';
import '../helpers.dart';

const assetFilePath = 'some/assets/file';

void main() {
  useTempWorkingDirectory();
  group(ArchiveDiffer, () {
    late TestArchiveDiffer archiveDiffer;

    setUp(() {
      archiveDiffer = TestArchiveDiffer();
    });

    group('containsPotentiallyBreakingAssetDiffs', () {
      test('returns true if any assets were added', () {
        archiveDiffer.changedFileSetDiff = const FileSetDiff(
          addedPaths: {assetFilePath},
          removedPaths: {},
          changedPaths: {},
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            archiveDiffer.changedFileSetDiff,
          ),
          isTrue,
        );
      });

      test('returns false if changed assets are all in the ignore list', () {
        archiveDiffer.changedFileSetDiff = const FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {'AssetManifest.bin'},
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            archiveDiffer.changedFileSetDiff,
          ),
          isFalse,
        );
      });

      test('returns true if changed assets are not all in the ignore list', () {
        archiveDiffer.changedFileSetDiff = const FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {assetFilePath},
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            archiveDiffer.changedFileSetDiff,
          ),
          isTrue,
        );
      });
    });

    group('fileHashes', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync();
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      File writeFile(String name, List<int> bytes) =>
          File(p.join(tempDir.path, name))..writeAsBytesSync(bytes);

      List<int> zipBytes() => ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.string('lib/libapp.so', 'a' * 4096)),
      );

      test("maps each entry's path to its crc32", () async {
        final zip = writeFile('release.zip', zipBytes());

        expect(
          await archiveDiffer.fileHashes(zip),
          equals({
            'lib/libapp.so': getCrc32(utf8.encode('a' * 4096)).toString(),
          }),
        );
      });

      test('maps an empty zip to no paths', () async {
        final zip = writeFile('empty.zip', ZipEncoder().encode(Archive()));

        expect(await archiveDiffer.fileHashes(zip), isEmpty);
      });

      test('throws for a zip cut short', () async {
        final bytes = zipBytes();
        final zip = writeFile('cut.zip', bytes.sublist(0, bytes.length - 30));

        await expectLater(
          archiveDiffer.fileHashes(zip),
          throwsA(isA<ArchiveException>()),
        );
      });

      test('throws for a file that is not a zip', () async {
        final notZip = writeFile('release.zip', utf8.encode('not a zip'));

        await expectLater(
          archiveDiffer.fileHashes(notZip),
          throwsA(isA<ArchiveException>()),
        );
      });
    });
  });
}

class TestArchiveDiffer extends ArchiveDiffer {
  FileSetDiff changedFileSetDiff = FileSetDiff.empty();

  @override
  Future<FileSetDiff> changedFiles(
    String oldArchivePath,
    String newArchivePath,
  ) async => changedFileSetDiff;

  @override
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) => false;

  @override
  bool isAssetFilePath(String filePath) => filePath == assetFilePath;

  @override
  bool isDartFilePath(String filePath) => true;

  @override
  bool isNativeFilePath(String filePath) => true;

  @override
  Future<String> availableAssetDiffs({
    required FileSetDiff fileSetDiff,
    required String oldArchivePath,
    required String newArchivePath,
  }) async => '';
}
