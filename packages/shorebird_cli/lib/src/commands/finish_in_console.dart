import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// Hands an operation the CLI does not perform to the Shorebird console.
///
/// ADR-0026: operations that are hard to undo (deleting an app, an account or
/// a team, creating a service-account key) and those the account API refuses
/// CLI tokens for finish in the browser, where a person confirms them, so an
/// agent can't run them in passing. Commands for them open the console page
/// that does it and send no request that changes anything.
mixin FinishInConsole on ShorebirdCommand {
  /// Sends the user to [url] to [action] (e.g. "delete app "Acme" (app-id)").
  ///
  /// In a terminal, prints the URL, opens it in the browser when this machine
  /// has one, and returns success. Otherwise (no terminal, CI, or `--json`),
  /// nobody is there to finish it, so it reports a
  /// [JsonErrorCode.consoleRequired] error naming the URL and returns
  /// [ExitCode.unavailable], so a script that relied on the command fails
  /// loudly rather than silently doing nothing.
  int finishInConsole({required String action, required Uri url}) {
    final link = '$url';
    if (!shorebirdEnv.canAcceptUserInput) {
      return reportError(
        code: JsonErrorCode.consoleRequired,
        message:
            'The Shorebird CLI does not $action. A person finishes it in '
            'the Shorebird console: $link',
        hint: 'Open $link in a browser to $action.',
        exitCode: ExitCode.unavailable.code,
      );
    }

    final openBrowser = browser.canOpen;
    logger.info(
      '${openBrowser ? 'Opening' : 'Visit'} the Shorebird console to $action:'
      '\n\n${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(link)))}',
    );
    if (openBrowser) unawaited(browser.open(url));
    return ExitCode.success.code;
  }
}
