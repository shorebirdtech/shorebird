import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

extension DirectoryArchive on Directory {
  /// Copies this directory to a temporary directory and zips it.
  Future<File> zipToTempFile() async {
    final tempDir = await Directory.systemTemp.createTemp();
    final outFile = File(p.join(tempDir.path, '${p.basename(path)}.zip'));
    await Isolate.run(() {
      copyPathSync(path, tempDir.path);
      ZipFileEncoder().zipDirectory(tempDir, filename: outFile.path);
    });
    return outFile;
  }
}
