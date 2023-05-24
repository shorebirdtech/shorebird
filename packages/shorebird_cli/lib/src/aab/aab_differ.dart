import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/aab/mf_reader.dart';

/// Types of code changes that we care about.
enum AabDifferences {
  none,
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
  /// Match files that change when Dart code changes.
  final _dartChangePatterns = [
    RegExp(r'.+libapp\.so$'),
    RegExp(r'.+libflutter\.so$'),
  ];

  /// Match files that change when Java/Kotlin code changes.
  final _nativeChangePatterns = [
    RegExp(r'.+\.dex$'),
  ];

  /// Match files that change when assets change.
  final _assetChangePatterns = [
    RegExp(r'(.*)\/assets\/(.*)'),
    RegExp(r'AssetManifest\.json$'),
  ];

  /// Returns a set of file paths whose hashes differ between the AABs at the
  /// provided paths.
  Set<String> aabFileDifferences(String aabPath1, String aabPath2) {
    final mfContents1 = _metaInfMfContent(File(aabPath1));
    final mfContents2 = _metaInfMfContent(File(aabPath2));
    final mfEntries1 = MfReader.parse(mfContents1).toSet();
    final mfEntries2 = MfReader.parse(mfContents2).toSet();
    return mfEntries1.difference(mfEntries2).map((entry) => entry.name).toSet();
  }

  /// Returns a set of difference types detected between the aabs at [aabPath1]
  /// and [aabPath2].
  Set<AabDifferences> aabContentDifferences(String aabPath1, String aabPath2) {
    final fileDifferences = aabFileDifferences(aabPath1, aabPath2);

    final hasAssetChanges = fileDifferences.any((file) {
      return _assetChangePatterns.any((pattern) => pattern.hasMatch(file));
    });
    final hasDartChanges = fileDifferences.any((file) {
      return _dartChangePatterns.any((pattern) => pattern.hasMatch(file));
    });
    final hasNativeChanges = fileDifferences.any((file) {
      return _nativeChangePatterns.any((pattern) => pattern.hasMatch(file));
    });

    final differences = <AabDifferences>{};
    if (hasAssetChanges) {
      differences.add(AabDifferences.assets);
    }
    if (hasDartChanges) {
      differences.add(AabDifferences.dart);
    }
    if (hasNativeChanges) {
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
          .firstWhere((file) => file.name == p.join('META-INF', 'MANIFEST.MF'))
          .content as List<int>,
    );
  }
}
