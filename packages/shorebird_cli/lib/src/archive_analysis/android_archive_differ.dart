// cspell:words unparseable
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dex/dex.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/bundle_dependencies.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';

/// A [FileSetDiff] that also carries semantic DEX diff results.
class AndroidFileSetDiff extends FileSetDiff {
  /// Creates an [AndroidFileSetDiff] with DEX diff results.
  const AndroidFileSetDiff({
    required super.addedPaths,
    required super.removedPaths,
    required super.changedPaths,
    this.dexDiffResults = const {},
    this.dependencyVersionChanges = const [],
  });

  /// DEX diff results for breaking changes, keyed by file path.
  final Map<String, DexDiffResult> dexDiffResults;

  /// Maven libraries whose resolved versions differ between the two bundles.
  ///
  /// Only computed when DEX files have breaking changes, since a dependency
  /// version change is the most common cause of DEX changes the developer
  /// didn't make. Empty if neither bundle carries dependency metadata.
  final List<DependencyVersionChange> dependencyVersionChanges;
}

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
///        or assets were changed. When DEX files change, the Maven versions it
///        records are compared to explain why (see
///        [AndroidFileSetDiff.dependencyVersionChanges]).
///
/// See https://developer.android.com/guide/app-bundle/app-bundle-format and
/// /// https://developer.android.com/studio/projects/android-library.html#aar-contents
/// for reference. Note that .aars produced by Flutter modules do not contain
/// .jar files, so only asset and dart changes are possible.
/// {@endtemplate}
class AndroidArchiveDiffer extends ArchiveDiffer {
  /// {@macro android_archive_differ}
  const AndroidArchiveDiffer();

  @override
  Future<AndroidFileSetDiff> changedFiles(
    String oldArchivePath,
    String newArchivePath,
  ) async {
    final fileSetDiff = await super.changedFiles(
      oldArchivePath,
      newArchivePath,
    );

    final dexPaths = fileSetDiff.changedPaths
        .where((p) => p.endsWith('.dex'))
        .toList();

    if (dexPaths.isEmpty) {
      return AndroidFileSetDiff(
        addedPaths: fileSetDiff.addedPaths,
        removedPaths: fileSetDiff.removedPaths,
        changedPaths: fileSetDiff.changedPaths,
      );
    }

    // Extract DEX file bytes (and dependency metadata) from both archives.
    final oldFiles = _extractFiles(oldArchivePath, [
      ...dexPaths,
      bundleDependenciesPath,
    ]);
    final newFiles = _extractFiles(newArchivePath, [
      ...dexPaths,
      bundleDependenciesPath,
    ]);

    const parser = DexParser();
    const differ = DexDiffer();
    final safePaths = <String>{};
    final dexDiffResults = <String, DexDiffResult>{};

    for (final path in dexPaths) {
      final oldBytes = oldFiles[path];
      final newBytes = newFiles[path];
      if (oldBytes == null || newBytes == null) continue;

      try {
        final oldDex = parser.parse(oldBytes);
        final newDex = parser.parse(newBytes);
        final result = differ.diff(oldDex, newDex);

        if (result.isSafe) {
          safePaths.add(path);
        } else {
          dexDiffResults[path] = result;
        }
        // Catch all exceptions so unparseable DEX files are conservatively
        // treated as changed rather than crashing the diff.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // If parsing fails, conservatively keep the path as changed.
      }
    }

    final changedPaths = fileSetDiff.changedPaths.difference(safePaths);
    final hasBreakingDexChanges = changedPaths.any((p) => p.endsWith('.dex'));

    return AndroidFileSetDiff(
      addedPaths: fileSetDiff.addedPaths,
      removedPaths: fileSetDiff.removedPaths,
      changedPaths: changedPaths,
      dexDiffResults: dexDiffResults,
      dependencyVersionChanges: hasBreakingDexChanges
          ? _dependencyVersionChanges(
              oldFiles[bundleDependenciesPath],
              newFiles[bundleDependenciesPath],
            )
          : const [],
    );
  }

  List<DependencyVersionChange> _dependencyVersionChanges(
    Uint8List? oldBytes,
    Uint8List? newBytes,
  ) {
    if (oldBytes == null || newBytes == null) return const [];
    try {
      return diffDependencyVersions(
        parseBundleDependencies(oldBytes),
        parseBundleDependencies(newBytes),
      );
    } on FormatException {
      // The metadata is only used to explain a DEX change, so a file we can't
      // parse just means no explanation.
      return const [];
    }
  }

  Map<String, Uint8List> _extractFiles(
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
