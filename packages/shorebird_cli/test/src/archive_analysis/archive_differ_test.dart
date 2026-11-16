import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
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

    group('shorebirdYamlHash', () {
      const yaml = 'app_id: abc\nrelease_version: 1.0.0\nauto_update: true\n';

      test('ignores the release_version line', () {
        expect(
          ArchiveDiffer.shorebirdYamlHash(utf8.encode(yaml)),
          equals(
            ArchiveDiffer.shorebirdYamlHash(
              utf8.encode('app_id: abc\nauto_update: true\n'),
            ),
          ),
        );
        expect(
          ArchiveDiffer.shorebirdYamlHash(utf8.encode(yaml)),
          equals(
            ArchiveDiffer.shorebirdYamlHash(
              utf8.encode(yaml.replaceFirst('1.0.0', '2.0.0')),
            ),
          ),
        );
      });

      test('ignores release_version as Flutter writes it', () {
        // Flutter's yaml_edit output: quoted, last key, no trailing newline.
        expect(
          ArchiveDiffer.shorebirdYamlHash(
            utf8.encode('app_id: base-app-id\nrelease_version: "1.10"'),
          ),
          equals(
            ArchiveDiffer.shorebirdYamlHash(utf8.encode('app_id: base-app-id')),
          ),
        );
      });

      test('falls back to the raw bytes for invalid yaml', () {
        expect(
          ArchiveDiffer.shorebirdYamlHash(utf8.encode('a: [')),
          equals(getCrc32(utf8.encode('a: [')).toString()),
        );
        expect(
          ArchiveDiffer.shorebirdYamlHash(utf8.encode('a: [')),
          isNot(equals(ArchiveDiffer.shorebirdYamlHash(utf8.encode('a: [1')))),
        );
      });

      test('sees changes to other lines', () {
        expect(
          ArchiveDiffer.shorebirdYamlHash(utf8.encode(yaml)),
          isNot(
            equals(
              ArchiveDiffer.shorebirdYamlHash(
                utf8.encode(yaml.replaceFirst('abc', 'xyz')),
              ),
            ),
          ),
        );
      });
    });

    group('fileHashes', () {
      File zipWith(
        String name,
        String yaml, {
        String path = 'assets/flutter_assets/shorebird.yaml',
      }) {
        final archive = Archive()
          ..addFile(ArchiveFile.bytes(path, utf8.encode(yaml)));
        return File(p.join(Directory.current.path, name))
          ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      }

      test('ignores the release_version line in shorebird.yaml', () async {
        final release = zipWith(
          'release.zip',
          'app_id: abc\nrelease_version: 1.0.0\n',
        );
        final patch = zipWith('patch.zip', 'app_id: abc\n');
        final changed = zipWith('changed.zip', 'app_id: xyz\n');

        final releaseHashes = await archiveDiffer.fileHashes(release);
        expect(await archiveDiffer.fileHashes(patch), equals(releaseHashes));
        expect(
          await archiveDiffer.fileHashes(changed),
          isNot(equals(releaseHashes)),
        );
      });

      test('sees release_version in a project asset of that name', () async {
        const path = 'assets/flutter_assets/assets/config/shorebird.yaml';
        final release = zipWith(
          'release.zip',
          'release_version: 1.0.0\n',
          path: path,
        );
        final patch = zipWith(
          'patch.zip',
          'release_version: 2.0.0\n',
          path: path,
        );
        expect(
          await archiveDiffer.fileHashes(patch),
          isNot(equals(await archiveDiffer.fileHashes(release))),
        );
      });
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
