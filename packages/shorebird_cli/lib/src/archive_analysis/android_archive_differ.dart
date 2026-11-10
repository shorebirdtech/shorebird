import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:dex/dex.dart';
import 'package:elf/elf.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/bundle_dependencies.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';

/// A [FileSetDiff] that also carries semantic DEX and ELF diff results.
class AndroidFileSetDiff extends FileSetDiff {
  /// Creates an [AndroidFileSetDiff] with DEX and ELF diff results.
  const AndroidFileSetDiff({
    required super.addedPaths,
    required super.removedPaths,
    required super.changedPaths,
    this.dexDiffResults = const {},
    this.elfDiffResults = const {},
    this.dependencyVersionChanges = const [],
  });

  /// DEX diff results for breaking changes, keyed by file path.
  final Map<String, DexDiffResult> dexDiffResults;

  /// ELF diff results for breaking `.so` changes, keyed by file path.
  final Map<String, ElfDiffResult> elfDiffResults;

  /// Maven libraries whose resolved versions differ between the two bundles.
  ///
  /// Only computed when native files have breaking changes, since a dependency
  /// version change is the most common cause of native changes the developer
  /// didn't make. Empty if neither bundle carries dependency metadata.
  final List<DependencyVersionChange> dependencyVersionChanges;
}

/// {@template android_archive_differ}
/// Finds differences between two Android archives (either AABs or AARs).
///
/// Types of changes we care about:
///   - Dart code changes
///      - libapp.so will be different
///   - Java/Kotlin/C/C++/Rust native code changes
///      - .dex files will be different
///      - non-Flutter .so files (`lib/<abi>/lib*.so`) will be different
///   - Assets
///      - **/assets/** will be different
///      - AssetManifest.json will have changed if assets have been added or
///        removed
///
/// Changes we don't care about:
///   - Anything in META-INF
///   - BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb
///      - This seems to change with every build, regardless of whether any code
///        or assets were changed. When native files change, the Maven versions
///        it records are compared to explain why (see
///        [AndroidFileSetDiff.dependencyVersionChanges]).
///   - Per-build UUID-only rotation in `sentry-debug-meta.properties` and
///     `crashlytics-build.properties`.
///
/// See https://developer.android.com/guide/app-bundle/app-bundle-format and
/// https://developer.android.com/studio/projects/android-library.html#aar-contents
/// for reference.
/// {@endtemplate}
class AndroidArchiveDiffer extends ArchiveDiffer {
  /// {@macro android_archive_differ}
  const AndroidArchiveDiffer();

  static const _dartSharedLibraryNames = {'libapp.so', 'libflutter.so'};

  static const _sentryBuildPropertiesFileName = 'sentry-debug-meta.properties';
  static const _crashlyticsBuildPropertiesFileName =
      'crashlytics-build.properties';

  static const _buildUuidKeysByFileName = <String, Set<String>>{
    _sentryBuildPropertiesFileName: {
      'io.sentry.ProguardUuids',
      'io.sentry.proguard-uuid',
      'io.sentry.bundle-ids',
    },
    _crashlyticsBuildPropertiesFileName: {
      'build_id',
      'com.crashlytics.android.build_id',
    },
  };

  static final _uuidListValueRegex = RegExp(
    '^(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
    '[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{32})'
    '(?:,(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
    r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{32}))*$',
  );

  static bool _isNativeSharedLibraryPath(String filePath) =>
      p.extension(filePath) == '.so' &&
      !_dartSharedLibraryNames.contains(p.basename(filePath));

  static bool _isBuildPropertiesPath(String filePath) =>
      _buildUuidKeysByFileName.containsKey(p.basename(filePath));

  /// Canonicalizes per-build UUID values and timestamp comments in known
  /// 3rd-party build metadata `.properties` files
  /// (`sentry-debug-meta.properties` and `crashlytics-build.properties`).
  ///
  /// Returns `null` if [filePath] is not a recognized build properties file,
  /// if [bytes] is not valid UTF-8, if any property line is malformed, or if
  /// no valid per-build UUID key is present.
  @visibleForTesting
  static Map<String, String>? canonicalizeBuildProperties(
    String filePath,
    Uint8List bytes,
  ) {
    final uuidKeys = _buildUuidKeysByFileName[p.basename(filePath)];
    if (uuidKeys == null) return null;

    final String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      return null;
    }

    final canonical = <String, String>{};
    var sawUuidKey = false;

    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('!')) {
        continue;
      }
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex <= 0) return null;

      final key = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();
      if (key.isEmpty) return null;

      if (uuidKeys.contains(key)) {
        if (!_uuidListValueRegex.hasMatch(value)) return null;
        final count = value.split(',').length;
        canonical[key] = List.filled(count, '<uuid>').join(',');
        sawUuidKey = true;
      } else {
        canonical[key] = value;
      }
    }

    if (!sawUuidKey) return null;
    return canonical;
  }

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
    final elfPaths = fileSetDiff.changedPaths
        .where(_isNativeSharedLibraryPath)
        .toList();
    final propertyPaths = fileSetDiff.changedPaths
        .where(_isBuildPropertiesPath)
        .toList();

    if (dexPaths.isEmpty && elfPaths.isEmpty && propertyPaths.isEmpty) {
      return AndroidFileSetDiff(
        addedPaths: fileSetDiff.addedPaths,
        removedPaths: fileSetDiff.removedPaths,
        changedPaths: fileSetDiff.changedPaths,
      );
    }

    final pathsToExtract = <String>[
      ...dexPaths,
      ...elfPaths,
      ...propertyPaths,
      if (dexPaths.isNotEmpty || elfPaths.isNotEmpty) bundleDependenciesPath,
    ];

    final oldFiles = _extractFiles(oldArchivePath, pathsToExtract);
    final newFiles = _extractFiles(newArchivePath, pathsToExtract);

    const dexParser = DexParser();
    const dexDiffer = DexDiffer();
    const elfDiffer = ElfDiffer();
    final safePaths = <String>{};
    final dexDiffResults = <String, DexDiffResult>{};
    final elfDiffResults = <String, ElfDiffResult>{};

    for (final path in dexPaths) {
      final oldBytes = oldFiles[path];
      final newBytes = newFiles[path];
      if (oldBytes == null || newBytes == null) continue;

      try {
        final oldDex = dexParser.parse(oldBytes);
        final newDex = dexParser.parse(newBytes);
        final result = dexDiffer.diff(oldDex, newDex);

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

    for (final path in elfPaths) {
      final oldBytes = oldFiles[path];
      final newBytes = newFiles[path];
      if (oldBytes == null || newBytes == null) continue;

      final result = elfDiffer.diffBytes(oldBytes, newBytes);
      if (result.isSafe) {
        safePaths.add(path);
      } else {
        elfDiffResults[path] = result;
      }
    }

    const mapEquality = MapEquality<String, String>();
    for (final path in propertyPaths) {
      final oldBytes = oldFiles[path];
      final newBytes = newFiles[path];
      if (oldBytes == null || newBytes == null) continue;

      final oldProps = canonicalizeBuildProperties(path, oldBytes);
      final newProps = canonicalizeBuildProperties(path, newBytes);
      if (oldProps != null &&
          newProps != null &&
          mapEquality.equals(oldProps, newProps)) {
        safePaths.add(path);
      }
    }

    final changedPaths = fileSetDiff.changedPaths.difference(safePaths);
    final hasBreakingNativeChanges = changedPaths.any(isNativeFilePath);

    return AndroidFileSetDiff(
      addedPaths: fileSetDiff.addedPaths,
      removedPaths: fileSetDiff.removedPaths,
      changedPaths: changedPaths,
      dexDiffResults: dexDiffResults,
      elfDiffResults: elfDiffResults,
      dependencyVersionChanges: hasBreakingNativeChanges
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
      // The metadata is only used to explain a native change, so a file we
      // can't parse just means no explanation.
      return const [];
    }
  }

  Map<String, Uint8List> _extractFiles(
    String archivePath,
    List<String> paths,
  ) {
    final pathSet = paths.toSet();
    final result = <String, Uint8List>{};
    final input = InputFileStream(archivePath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final file in archive.files) {
        if (file.isFile && pathSet.contains(file.name)) {
          result[file.name] = Uint8List.fromList(file.content);
        }
      }
    } finally {
      input.closeSync();
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
  bool isDartFilePath(String filePath) =>
      _dartSharedLibraryNames.contains(p.basename(filePath));

  @override
  bool isNativeFilePath(String filePath) =>
      p.extension(filePath) == '.dex' || _isNativeSharedLibraryPath(filePath);
}
