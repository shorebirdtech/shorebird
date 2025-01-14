import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/portable_executable.dart';

/// {@template windows_archive_differ}
/// Finds differences between two Windows app packages.
/// {@endtemplate}
class WindowsArchiveDiffer extends ArchiveDiffer {
  /// {@macro windows_archive_differ}
  const WindowsArchiveDiffer();

  String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  bool _isDirectoryPath(String path) {
    return path.endsWith('/');
  }

  @override
  bool isAssetFilePath(String filePath) {
    // We don't care if an empty directory is added or removed, so ignore paths
    // that end with a '/'.
    return !_isDirectoryPath(filePath) &&
        p.split(filePath).contains('flutter_assets');
  }

  @override
  bool isDartFilePath(String filePath) {
    return p.basename(filePath) == 'app.so';
  }

  @override
  bool isNativeFilePath(String filePath) {
    const nativeFileExtensions = ['.dll', '.exe'];
    return nativeFileExtensions.contains(p.extension(filePath));
  }

  @override
  Future<FileSetDiff> changedFiles(
    String oldArchivePath,
    String newArchivePath,
  ) async {
    var oldPathHashes = await fileHashes(File(oldArchivePath));
    var newPathHashes = await fileHashes(File(newArchivePath));

    oldPathHashes = await _updateHashes(
      archivePath: oldArchivePath,
      pathHashes: oldPathHashes,
    );
    newPathHashes = await _updateHashes(
      archivePath: newArchivePath,
      pathHashes: newPathHashes,
    );

    return FileSetDiff.fromPathHashes(
      oldPathHashes: oldPathHashes,
      newPathHashes: newPathHashes,
    );
  }

  /// Removes the timestamps from exe headers
  Future<PathHashes> _updateHashes({
    required String archivePath,
    required PathHashes pathHashes,
  }) async {
    return Isolate.run(() async {
      for (final file in _exeFiles(archivePath)) {
        pathHashes[file.name] = await _sanitizedFileHash(file);
      }

      return pathHashes;
    });
  }

  Future<String> _sanitizedFileHash(ArchiveFile file) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final outPath = p.join(tempDir.path, file.name);
    final outputStream = OutputFileStream(outPath);
    file.writeContent(outputStream);
    await outputStream.close();

    final outFile = File(outPath);
    final bytes = PortableExecutable.bytesWithZeroedTimestamps(outFile);
    return _hash(bytes);
  }

  List<ArchiveFile> _exeFiles(String archivePath) {
    return ZipDecoder()
        .decodeStream(InputFileStream(archivePath))
        .files
        .where((file) => file.isFile)
        .where(
          (file) => p.extension(file.name) == '.exe',
        )
        .toList();
  }
}
