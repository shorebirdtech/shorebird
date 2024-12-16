import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [Open] instance.
final openRef = create(Open.new);

/// The [Open] instance available in the current zone.
Open get open => read(openRef);

/// A wrapper around the `open` command.
/// https://ss64.com/mac/open.html
class Open {
  /// Opens a new application at the provided [path] and streams the stdout and
  /// stderr.
  Future<Stream<List<int>>> newApplication({required String path}) async {
    final tmp = Directory.systemTemp.createTempSync();
    final stdout = File(p.join(tmp.path, 'stdout.log'))..createSync();
    await process.start(
      'open',
      [
        '-n',
        path,
        '--stdout=${stdout.path}',
        '--stderr=${stdout.path}',
      ],
    );

    final stdoutProcess = await process.start(
      'tail',
      ['-fn+1', stdout.path],
    );

    return stdoutProcess.stdout;
  }
}
