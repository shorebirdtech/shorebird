import 'dart:io';
import 'package:path/path.dart' as p;

File createTempFile(String name) {
  return File(
    p.join(
      Directory.systemTemp.createTempSync().path,
      name,
    ),
  )..createSync();
}
