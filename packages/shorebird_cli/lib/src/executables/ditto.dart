import 'dart:async';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [Ditto] instance.
final dittoRef = create(Ditto.new);

/// The [Ditto] instance available in the current zone.
Ditto get ditto => read(dittoRef);

/// A wrapper around the `ditto` command.
/// https://ss64.com/mac/ditto.html
class Ditto {
  Future<ShorebirdProcessResult> _exec(String command) async {
    return process.run('ditto', command.split(' '));
  }

  /// Extracts the contents of a compressed archive at [source] to
  /// [destination].
  Future<void> extract({
    required String source,
    required String destination,
  }) async {
    final result = await _exec('-x -k $source $destination');
    if (result.exitCode != 0) {
      throw Exception('Failed to extract: ${result.stderr}');
    }
  }

  /// Archives the contents of [source] to a compressed archive at
  /// [destination].
  Future<void> archive({
    required String source,
    required String destination,
    bool keepParent = false,
  }) async {
    final args = [
      '-c',
      '-k',
      // cspell: disable-next-line
      '--sequesterRsrc',
      if (keepParent) '--keepParent',
      source,
      destination,
    ];
    final result = await _exec(args.join(' '));
    if (result.exitCode != 0) {
      throw Exception('Failed to archive: ${result.stderr}');
    }
  }
}
