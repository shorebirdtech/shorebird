import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:yaml/yaml.dart';

/// {@template archive_differ}
/// Computes content differences between two archives.
/// {@endtemplate}
abstract class ArchiveDiffer {
  /// {@macro archive_differ}
  const ArchiveDiffer();

  /// Asset files that are not considered to be breaking changes.
  static const assetFileNamesToIgnore = {
    'AssetManifest.bin',
    'AssetManifest.json',
    'NOTICES.Z',
  };

  /// Whether there are asset differences between the archives that may cause
  /// issues when patching a release.
  bool containsPotentiallyBreakingAssetDiffs(FileSetDiff fileSetDiff) {
    final assetsDiff = assetsFileSetDiff(fileSetDiff);

    // If assets were added, we need to warn the user about asset differences.
    // We don't care about removed assets, as they can't be removed by patch
    // and won't cause issues.
    if (assetsDiff.addedPaths.isNotEmpty) {
      return true;
    }

    return assetsDiff.changedPaths
        .whereNot(
          (path) =>
              ArchiveDiffer.assetFileNamesToIgnore.contains(p.basename(path)),
        )
        .isNotEmpty;
  }

  /// Whether there are native code differences between the archives that may
  /// cause issues when patching a release.
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) =>
      nativeFileSetDiff(fileSetDiff).isNotEmpty;

  /// Whether the provided file path represents a changed asset.
  bool isAssetFilePath(String filePath);

  /// Whether the provided file path represents changed Dart code.
  bool isDartFilePath(String filePath);

  /// Whether the provided file path represents changed Native code.
  bool isNativeFilePath(String filePath);

  /// The subset of [fileSetDiff] that contains only changes that result from
  /// edited assets.
  FileSetDiff assetsFileSetDiff(FileSetDiff fileSetDiff) =>
      fileSetDiff.where(isAssetFilePath);

  /// The subset of [fileSetDiff] that contains only changes that result from
  /// edited Dart code.
  FileSetDiff dartFileSetDiff(FileSetDiff fileSetDiff) =>
      fileSetDiff.where(isDartFilePath);

  /// The subset of [fileSetDiff] that contains only changes that result from
  /// edited native code.
  FileSetDiff nativeFileSetDiff(FileSetDiff fileSetDiff) =>
      fileSetDiff.where(isNativeFilePath);

  /// Files that have been added, removed, or that have changed between the
  /// archives at the two provided paths.
  Future<FileSetDiff> changedFiles(
    String oldArchivePath,
    String newArchivePath,
  ) async {
    return FileSetDiff.fromPathHashes(
      oldPathHashes: await fileHashes(File(oldArchivePath)),
      newPathHashes: await fileHashes(File(newArchivePath)),
    );
  }

  /// The checksum of a generated (bundled) shorebird.yaml's [content],
  /// leaving out its `release_version` key.
  ///
  /// Flutter bakes an add-to-app module's release version into that file. A
  /// patch can't change the release's shorebird.yaml, and the key only
  /// differs when the release and the patch were built by different CLI
  /// versions (one passed the module's release version to Flutter and the
  /// other didn't), so it is not a change worth warning about. The YAML is
  /// compared parsed, so quoting, line endings and a trailing newline don't
  /// count as changes either.
  @visibleForTesting
  static String shorebirdYamlHash(List<int> content) {
    Object? parsed;
    try {
      parsed = loadYaml(utf8.decode(content));
    } on Exception {
      parsed = null;
    }
    if (parsed is! Map) return getCrc32(content).toString();
    final canonical = jsonEncode({
      for (final key in parsed.keys.map((k) => '$k').toList()..sort())
        if (key != 'release_version') key: parsed[key],
    });
    return getCrc32(utf8.encode(canonical)).toString();
  }

  /// Whether [path] is the generated (bundled) shorebird.yaml, which sits
  /// directly in `flutter_assets`, not a project asset of the same name.
  static bool _isBundledShorebirdYaml(String path) {
    final parts = p.posix.split(path);
    return parts.length >= 2 &&
        parts.last == 'shorebird.yaml' &&
        parts[parts.length - 2] == 'flutter_assets';
  }

  static String _headerHash(ZipFileHeader header) {
    final file = header.file;
    if (file != null && _isBundledShorebirdYaml(header.filename)) {
      return shorebirdYamlHash(file.readBytes());
    }
    // Zip files contain an (optional) crc32 checksum for a file. IPAs and AARs
    // seem to always include this for files, so a quick way for us to tell if
    // file contents differ is if their checksums differ.
    return header.crc32.toString();
  }

  /// Returns a map of file paths to their respective checksums.
  ///
  /// Throws an [ArchiveException] if [archive] is not a readable zip, such as
  /// one cut short, rather than returning no paths, which would read as every
  /// file having been added.
  Future<PathHashes> fileHashes(File archive) async {
    return Isolate.run(() {
      final input = InputFileStream(archive.path);
      try {
        final zipDirectory = ZipDirectory()..read(input, verify: true);
        // A zip cut short, or a file that is not a zip, has no end of
        // central directory record; `read` then finds no entries rather than
        // throwing.
        if (zipDirectory.filePosition < 0) {
          throw ArchiveException('zip: end of central directory not found');
        }
        return {
          for (final header in zipDirectory.fileHeaders)
            header.filename: _headerHash(header),
        };
      } finally {
        input.closeSync();
      }
    });
  }

  /// Prints the diffs of the changed files to the console.
  Future<String> availableAssetDiffs({
    required FileSetDiff fileSetDiff,
    required String oldArchivePath,
    required String newArchivePath,
  }) async {
    return '';
  }
}
