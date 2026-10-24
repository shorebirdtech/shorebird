import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';

/// A reference to a [ServerNotices] instance.
final serverNoticesRef = create(ServerNotices.new);

/// The [ServerNotices] instance available in the current zone.
ServerNotices get serverNotices => read(serverNoticesRef);

/// {@template server_notices}
/// Notices the Shorebird server sent during this run, such as a warning that
/// the account's patches are paused or near the install limit.
///
/// The code push client adds each `Shorebird-Notice` header it receives, and
/// the command runner prints them once the command has finished, whether it
/// succeeded or failed. Printing at the end keeps a notice out of progress
/// output and makes it the last thing the developer reads, and printing once
/// keeps a notice repeated on several responses (one per platform, say) to a
/// single line.
/// {@endtemplate}
class ServerNotices {
  final _pending = <String>{};

  /// Records [notice] to be printed by [printAll].
  void add(String notice) => _pending.add(notice);

  /// Prints every recorded notice as a warning, then forgets them.
  void printAll() {
    _pending
      ..forEach(logger.warn)
      ..clear();
  }
}
