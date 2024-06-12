import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// A wrapper around a directory that can be zipped.
extension DirectoryArchive on Directory {
  /// Copies this directory to a temporary directory and zips it.
  Future<File> zipToTempFile() async {
    final tempDir = await Directory.systemTemp.createTemp();
    final outFile = File(p.join(tempDir.path, '${p.basename(path)}.zip'));
    await Isolate.run(() {
      ZipFileEncoder().zipDirectory(this, filename: outFile.path);
    });
    return outFile;
  }
}
