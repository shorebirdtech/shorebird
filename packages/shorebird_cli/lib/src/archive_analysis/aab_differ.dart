import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/mf_reader.dart';

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
class AabDiffer extends AndroidArchiveDiffer {
  /// Returns a set of file paths whose hashes differ between the AABs at the
  /// provided paths.
  @override
  Set<String> changedFiles(String aabPath1, String aabPath2) {
    final mfContents1 = _metaInfMfContent(File(aabPath1));
    final mfContents2 = _metaInfMfContent(File(aabPath2));
    final mfEntries1 = MfReader.parse(mfContents1).toSet();
    final mfEntries2 = MfReader.parse(mfContents2).toSet();
    return mfEntries1.difference(mfEntries2).map((entry) => entry.name).toSet();
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
}
