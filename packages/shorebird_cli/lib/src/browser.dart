// cspell:words rundll32 FileProtocolHandler
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [Browser] instance.
final browserRef = create(Browser.new);

/// The [Browser] instance available in the current zone.
Browser get browser => read(browserRef);

/// Opens URLs in the user's default browser.
class Browser {
  /// Whether this machine is likely to have a browser that [open] can reach.
  ///
  /// False on CI, over SSH (a browser on the user's own machine could not
  /// reach this machine's localhost anyway), and on Linux without a display.
  bool get canOpen {
    if (shorebirdEnv.isRunningOnCI) return false;
    final environment = platform.environment;
    if (environment.containsKey('SSH_CONNECTION') ||
        environment.containsKey('SSH_TTY')) {
      return false;
    }
    if (platform.isMacOS || platform.isWindows) return true;
    if (platform.isLinux) {
      return environment.containsKey('DISPLAY') ||
          environment.containsKey('WAYLAND_DISPLAY');
    }
    return false;
  }

  /// Opens [url] in the default browser. Returns whether the platform's
  /// opener reported success. Never throws; a failure is logged at detail
  /// level, since the caller has already shown the URL.
  Future<bool> open(Uri url) async {
    final (executable, arguments) = switch (platform) {
      _ when platform.isMacOS => ('open', [url.toString()]),
      // `start` is a cmd builtin that treats `&` as a command separator, so
      // hand the URL to the shell's protocol handler directly instead.
      _ when platform.isWindows => (
        'rundll32',
        ['url.dll,FileProtocolHandler', url.toString()],
      ),
      _ => ('xdg-open', [url.toString()]),
    };
    try {
      final result = await process.run(executable, arguments);
      if (result.exitCode != 0) {
        logger.detail('$executable exited with code ${result.exitCode}');
        return false;
      }
      return true;
    } on Exception catch (error) {
      logger.detail('Unable to open a browser: $error');
      return false;
    }
  }
}
