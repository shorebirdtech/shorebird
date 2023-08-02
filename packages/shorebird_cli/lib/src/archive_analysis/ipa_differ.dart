import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';

class IpaDiffer extends ArchiveDiffer {
  String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  @override
  FileSetDiff changedFiles(String oldArchivePath, String newArchivePath) =>
      FileSetDiff.fromPathHashes(
        oldPathHashes: _fileHashes(File(oldArchivePath)),
        newPathHashes: _fileHashes(File(newArchivePath)),
      );

  @override
  bool containsPotentiallyBreakingAssetDiffs(FileSetDiff fileSetDiff) =>
      assetsFileSetDiff(fileSetDiff).isNotEmpty;

  @override
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) {
    // Because every IPA will have changed .symbols files, we can't reliably
    // tell whether potentially problematic native changes have been made.
    return false;
  }

  @override
  bool isAssetFilePath(String filePath) {
    /// The flutter_assets directory contains the assets listed in the assets
    ///   section of the pubspec.yaml file.
    /// Assets.car is the compiled asset catalog(s) (.xcassets files).
    return p.basename(filePath) == 'Assets.car' ||
        p.split(filePath).contains('flutter_assets');
  }

  @override
  bool isDartFilePath(String filePath) => p.extension(filePath) == '.symbols';

  @override
  bool isNativeFilePath(String filePath) => p.extension(filePath) == '.symbols';

  PathHashes _fileHashes(File ipa) {
    final files = ZipDecoder()
        .decodeBuffer(InputFileStream(ipa.path))
        .files
        .where((file) => file.isFile);
    return {
      for (final file in files) file.name: _hash(file.content as List<int>)
    };
  }
}
