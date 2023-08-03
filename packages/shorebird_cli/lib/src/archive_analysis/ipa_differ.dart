import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';

/// Finds differences between two IPAs.
///
/// Asset changes will be in the `Assets.car` file (which is a combination of
/// the `.xcasset` catalogs in the Xcode project) and the `flutter_assets`
/// directory.
///
/// Native changes will appear in the Runner.app/Runner executable.
///
/// Dart changes will appear in the App.framework/App executable.
class IpaDiffer extends ArchiveDiffer {
  static const binaryFiles = {
    'App.framework/App',
    'Flutter.framework/Flutter',
  };
  static RegExp appRegex = RegExp(r'^Payload/[\w\-. ]+.app/[\w\-. ]+$');

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
    // TODO(bryanoltman): Implement this
    // We will need to unsign executable files (App.framework/app,
    // Runner.app/Runner) to determine whether native changes have been made. If
    // these files are signed, they will be different between builds from
    // identical code bases.
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
  bool isDartFilePath(String filePath) =>
      filePath.endsWith('App.framework/App');

  @override
  bool isNativeFilePath(String filePath) => appRegex.hasMatch(filePath);

  PathHashes _fileHashes(File ipa) {
    final files = ZipDecoder()
        .decodeBuffer(InputFileStream(ipa.path))
        .files
        .where((file) => file.isFile);
    final namesToHashes = <String, String>{};
    for (final file in files) {
      String hash;
      if (_shouldUnsignFile(file.name)) {
        final tempDir = Directory.systemTemp.createTempSync();
        final outPath = p.join(tempDir.path, file.name);
        final outputStream = OutputFileStream(outPath);
        file.writeContent(outputStream);
        outputStream.close();

        Process.runSync('codesign', [
          '--remove-signature',
          outPath,
        ]);

        final outFile = File(outPath);
        hash = _hash(outFile.readAsBytesSync());
      } else {
        hash = _hash(file.content as List<int>);
      }
      namesToHashes[file.name] = hash;
    }

    return namesToHashes;
  }

  bool _shouldUnsignFile(String filePath) =>
      filePath.endsWith('App.framework/App') ||
      filePath.endsWith('Flutter.framework/Flutter') ||
      appRegex.hasMatch(filePath);
}
