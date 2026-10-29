import 'dart:io';

import 'package:path/path.dart' as p;

/// The passes recorded so far, one file per key under `passed/`.
class ResultStore {
  /// A store kept in [directory].
  ResultStore(this.directory);

  /// Where the store lives. Shared by every checkout that uses it.
  final Directory directory;

  File _entry(String digest) => File(p.join(directory.path, 'passed', digest));

  /// The entry recorded for [digest], or null when none is.
  String? lookup(String digest) {
    final entry = _entry(digest);
    return entry.existsSync() ? entry.readAsStringSync() : null;
  }

  /// Records [contents] as the entry for [digest].
  ///
  /// Written to a temporary file and renamed into place, so a concurrent
  /// [lookup] sees either no entry or the whole of one.
  void record(String digest, String contents) {
    final entry = _entry(digest)..parent.createSync(recursive: true);
    File('${entry.path}.tmp.$pid')
      ..writeAsStringSync(contents, flush: true)
      ..renameSync(entry.path);
  }
}
