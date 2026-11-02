import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/github_actions_oidc.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';

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
  ///
  /// On GitHub Actions each notice is a `::warning` workflow command instead,
  /// which the log shows as a warning and the run's summary page lists as an
  /// annotation, so it is seen without opening the job's log.
  /// https://docs.github.com/actions/reference/workflows-and-actions/workflow-commands#setting-a-warning-message
  void printAll() {
    if (_pending.isEmpty) return;
    final onGitHubActions = platform.environment[githubActionsEnvVar] == 'true';
    for (final notice in _pending) {
      if (onGitHubActions) {
        logger.info('::warning title=Shorebird::${_escapeData(notice)}');
      } else {
        logger.warn(notice);
      }
    }
    _pending.clear();
  }

  /// Escapes a workflow command's message as the Actions runner expects.
  /// https://github.com/actions/toolkit/blob/main/packages/core/src/command.ts
  static String _escapeData(String message) => message
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');
}
