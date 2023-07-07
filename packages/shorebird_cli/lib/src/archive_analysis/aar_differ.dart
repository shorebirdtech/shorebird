import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';

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
class AarDiffer extends ArchiveDiffer {
  String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  @override
  FileSetDiff changedFiles(String oldArchivePath, String newArchivePath) =>
      FileSetDiff.fromPathHashes(
        oldPathHashes: _fileHashes(File(oldArchivePath)),
        newPathHashes: _fileHashes(File(newArchivePath)),
      );

  PathHashes _fileHashes(File aar) {
    final files = ZipDecoder()
        .decodeBuffer(InputFileStream(aar.path))
        .files
        .where((file) => file.isFile);
    return {
      for (final file in files) file.name: _hash(file.content as List<int>)
    };
  }
}
