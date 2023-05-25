import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/aab/mf_reader.dart';

/// Types of code changes that we care about.
enum AabDifferences {
  dart,
  native,
  assets,
}

/// Finds differences between two AABs.
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
/// See https://developer.android.com/guide/app-bundle/app-bundle-format for
/// reference.
class AabDiffer {
  /// Returns a set of file paths whose hashes differ between the AABs at the
  /// provided paths.
  Set<String> aabChangedFiles(String aabPath1, String aabPath2) {
    final mfContents1 = _metaInfMfContent(File(aabPath1));
    final mfContents2 = _metaInfMfContent(File(aabPath2));
    final mfEntries1 = MfReader.parse(mfContents1).toSet();
    final mfEntries2 = MfReader.parse(mfContents2).toSet();
    return mfEntries1.difference(mfEntries2).map((entry) => entry.name).toSet();
  }

  /// Returns a set of difference types detected between the aabs at [aabPath1]
  /// and [aabPath2].
  Set<AabDifferences> aabContentDifferences(String aabPath1, String aabPath2) {
    final fileDifferences = aabChangedFiles(aabPath1, aabPath2);

    final differences = <AabDifferences>{};
    if (_hasAssetChanges(fileDifferences)) {
      differences.add(AabDifferences.assets);
    }
    if (_hasDartChanges(fileDifferences)) {
      differences.add(AabDifferences.dart);
    }
    if (_hasNativeChanges(fileDifferences)) {
      differences.add(AabDifferences.native);
    }

    return differences;
  }

  /// Reads the contents of META-INF/MANIFEST.MF from an AAB.
  ///
  /// This file contains a list of file paths and their SHA-256 hashes.
  String _metaInfMfContent(File aab) {
    final inputStream = InputFileStream(aab.path);
    final archive = ZipDecoder().decodeBuffer(inputStream);
    return utf8.decode(
      archive.files
          .firstWhere((file) => file.name == 'META-INF/MANIFEST.MF')
          .content as List<int>,
    );
  }

  /// Whether any changed files correspond to a change in assets.
  bool _hasAssetChanges(Set<String> paths) {
    const assetDirNames = ['assets', 'res'];
    const assetFileNames = ['AssetManifest.json'];
    return paths.any(
      (path) =>
          p.split(path).any((component) => assetDirNames.contains(component)) ||
          assetFileNames.contains(p.basename(path)),
    );
  }

  /// Whether any changed files correspond to a change in Dart code.
  bool _hasDartChanges(Set<String> paths) {
    const dartFileNames = ['libapp.so', 'libflutter.so'];
    return paths.any((path) => dartFileNames.contains(p.basename(path)));
  }

  /// Whether changed files correspond to a change in Java or Kotlin code.
  bool _hasNativeChanges(Set<String> path) {
    return path.any((path) => p.extension(path) == '.dex');
  }
}
