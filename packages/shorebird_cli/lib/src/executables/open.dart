import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [Open] instance.
final openRef = create(Open.new);

/// The [Open] instance available in the current zone.
Open get open => read(openRef);

/// A wrapper around the macOS `open` command.
/// https://ss64.com/mac/open.html
class Open {
  /// Opens a new application at the provided [path] and streams the stdout and
  /// stderr.
  Future<Stream<List<int>>> newApplication({required String path}) async {
    final app = Directory(
      p.join(path, 'Contents', 'MacOS'),
    ).listSync().firstWhere((f) => f is File);

    await shorebirdProcess.start('open', ['-n', path]);

    final logStreamProcess = await shorebirdProcess.start('log', [
      'stream',
      '--style=compact',
      '--process',
      p.basenameWithoutExtension(app.path),
    ]);

    return logStreamProcess.stdout;
  }
}
