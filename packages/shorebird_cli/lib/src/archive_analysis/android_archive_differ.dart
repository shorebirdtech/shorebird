import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/dex_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/dex_parser.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';

/// {@template android_archive_differ}
/// Finds differences between two Android archives (either AABs or AARs).
///
/// Types of changes we care about:
///   - Dart code changes
///      - libapp.so will be different
///   - Java/Kotlin code changes
///      - .dex files will be different
///   - Assets
///      - **/assets/** will be different
///      - AssetManifest.json will have changed if assets have been added or
///        removed
///
/// Changes we don't care about:
///   - Anything in META-INF
///   - BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb
///      - This seems to change with every build, regardless of whether any code
///        or assets were changed.
///
/// See https://developer.android.com/guide/app-bundle/app-bundle-format and
/// /// https://developer.android.com/studio/projects/android-library.html#aar-contents
/// for reference. Note that .aars produced by Flutter modules do not contain
/// .jar files, so only asset and dart changes are possible.
/// {@endtemplate}
class AndroidArchiveDiffer extends ArchiveDiffer {
  /// {@macro android_archive_differ}
  const AndroidArchiveDiffer();

  /// DEX diff results for breaking changes, keyed by file path.
  ///
  /// Populated after [changedFiles] is called.
  static final Map<String, DexDiffResult> _dexDiffResults = {};

  /// Returns the [DexDiffResult] for a breaking DEX change at [path],
  /// or `null` if no result is available.
  static DexDiffResult? dexDiffResultForPath(String path) =>
      _dexDiffResults[path];

  @override
  Future<FileSetDiff> changedFiles(
    String oldArchivePath,
    String newArchivePath,
  ) async {
    final fileSetDiff = await super.changedFiles(
      oldArchivePath,
      newArchivePath,
    );

    final dexPaths =
        fileSetDiff.changedPaths.where((p) => p.endsWith('.dex')).toList();

    if (dexPaths.isEmpty) return fileSetDiff;

    // Extract DEX file bytes from both archives.
    final oldDexBytes = _extractDexFiles(oldArchivePath, dexPaths);
    final newDexBytes = _extractDexFiles(newArchivePath, dexPaths);

    const parser = DexParser();
    const differ = DexDiffer();
    final safePaths = <String>{};
    _dexDiffResults.clear();

    for (final path in dexPaths) {
      final oldBytes = oldDexBytes[path];
      final newBytes = newDexBytes[path];
      if (oldBytes == null || newBytes == null) continue;

      try {
        final oldDex = parser.parse(oldBytes);
        final newDex = parser.parse(newBytes);
        final result = differ.diff(oldDex, newDex);

        if (result.isSafe) {
          safePaths.add(path);
        } else {
          _dexDiffResults[path] = result;
        }
        // Catch all exceptions so unparseable DEX files are conservatively
        // treated as changed rather than crashing the diff.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // If parsing fails, conservatively keep the path as changed.
      }
    }

    if (safePaths.isEmpty) return fileSetDiff;

    return FileSetDiff(
      addedPaths: fileSetDiff.addedPaths,
      removedPaths: fileSetDiff.removedPaths,
      changedPaths: fileSetDiff.changedPaths.difference(safePaths),
    );
  }

  Map<String, Uint8List> _extractDexFiles(
    String archivePath,
    List<String> paths,
  ) {
    final pathSet = paths.toSet();
    final result = <String, Uint8List>{};
    final archive = ZipDecoder().decodeStream(
      InputFileStream(archivePath),
    );
    for (final file in archive.files) {
      if (file.isFile && pathSet.contains(file.name)) {
        result[file.name] = Uint8List.fromList(file.content);
      }
    }
    return result;
  }

  @override
  bool isAssetFilePath(String filePath) {
    const assetDirNames = ['assets', 'res'];
    const assetFileNames = ['AssetManifest.json'];

    return p
            .split(filePath)
            .any((component) => assetDirNames.contains(component)) ||
        assetFileNames.contains(p.basename(filePath));
  }

  @override
  bool isDartFilePath(String filePath) {
    const dartFileNames = ['libapp.so', 'libflutter.so'];
    return dartFileNames.contains(p.basename(filePath));
  }

  @override
  bool isNativeFilePath(String filePath) => p.extension(filePath) == '.dex';
}
