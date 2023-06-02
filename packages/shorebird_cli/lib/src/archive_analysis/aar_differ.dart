import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';

/// Finds differences between two AABs.
///
/// Types of changes we care about:
///   - Dart code changes
///      - libapp.so will be different
///   - Assets
///      - **/assets/** will be different
///      - AssetManifest.json will have changed if assets have been added or
///        removed
///
/// See
/// https://developer.android.com/studio/projects/android-library.html#aar-contents
/// for reference. Note that .aars produced by Flutter modules do not contain
/// .jar files, so only asset and dart changes are possible.
class AarDiffer extends AndroidArchiveDiffer {
  String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  @override
  Set<String> changedFiles(String archivePath1, String archivePath2) =>
      _fileHashes(File(archivePath1))
          .difference(_fileHashes(File(archivePath2)))
          .map((pair) => pair.$1)
          .toSet();

  Set<(String, String)> _fileHashes(File aar) => ZipDecoder()
      .decodeBuffer(InputFileStream(aar.path))
      .files
      .where((file) => file.isFile)
      .map((file) => (file.name, _hash(file.content as List<int>)))
      .toSet();
}
