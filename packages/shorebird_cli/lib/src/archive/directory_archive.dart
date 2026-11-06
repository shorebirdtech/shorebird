import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// A wrapper around a directory that can be zipped.
extension DirectoryArchive on Directory {
  /// Copies this directory to a temporary directory and zips it.
  Future<File> zipToTempFile({String? name}) async {
    final tempDir = await Directory.systemTemp.createTemp();
    return zipInto(tempDir, name: name);
  }

  /// Zips this directory into [directory] as `<name>.zip`, where [name]
  /// defaults to this directory's name, and returns the zip.
  Future<File> zipInto(Directory directory, {String? name}) async {
    final fileName = name ?? p.basename(path);
    final outFile = File(p.join(directory.path, '$fileName.zip'));
    await Isolate.run(() async {
      await ZipFileEncoder().zipDirectory(this, filename: outFile.path);
    });
    return outFile;
  }
}
