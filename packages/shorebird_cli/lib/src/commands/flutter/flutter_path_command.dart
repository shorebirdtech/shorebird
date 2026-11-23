import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';

/// {@template flutter_path_command}
/// `shorebird flutter path`
/// Print the directory of an installed Shorebird Flutter.
///
/// Scripts, IDE configs and CI actions (setup-shorebird) read the path from
/// here rather than building it from the cache layout, which is Shorebird's
/// to change. Only the path goes to stdout, so `$(shorebird flutter path)`
/// captures nothing else.
///
/// It never installs or fetches anything: a Flutter that is not installed is
/// an error naming the `shorebird flutter precache` command that installs it.
/// {@endtemplate}
class FlutterPathCommand extends ShorebirdCommand {
  /// {@macro flutter_path_command}
  FlutterPathCommand() {
    argParser.addOption(
      'flutter-version',
      help: '''
The Flutter version (e.g: 3.16.3) or commit hash whose directory to print.
Defaults to the version this Shorebird uses when building with
--flutter-version=latest.''',
    );
  }

  @override
  String get description =>
      'Print the directory of an installed Shorebird Flutter.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird flutter path --json')}';

  @override
  String get name => 'path';

  @override
  bool get reservesStdout => true;

  @override
  Future<int> run() {
    final output = isJsonMode
        ? read(jsonSinkRef, orElse: () => stdout)
        : stdout;
    return runWithStdoutOnStderr(
      () => runScoped(
        () => _run(output),
        values: {jsonSinkRef.overrideWith(() => output)},
      ),
    );
  }

  Future<int> _run(IOSink output) async {
    final versionOrHash = results['flutter-version'] as String?;
    final isPinned = versionOrHash == null || versionOrHash == 'latest';
    // These ask a project's Flutter for its version, and the system or fvm
    // Flutter is not Shorebird's to report.
    if (versionOrHash == 'system' || versionOrHash == 'fvm') {
      return reportError(
        message:
            '--flutter-version=$versionOrHash is not supported by '
            'shorebird flutter path.',
        hint: 'Pass the Flutter version itself, e.g. --flutter-version=3.38.5',
      );
    }

    final precacheCommand = isPinned
        ? 'shorebird flutter precache'
        : 'shorebird flutter precache --flutter-version $versionOrHash';
    final label = isPinned ? "Shorebird's Flutter" : 'Flutter $versionOrHash';
    int notInstalled() => reportError(
      message: '$label is not installed.',
      hint: 'Run: $precacheCommand',
      code: JsonErrorCode.preconditionFailed,
      exitCode: ExitCode.unavailable.code,
    );

    final String revision;
    if (isPinned) {
      revision = shorebirdEnv.flutterRevision;
    } else {
      // Resolved from the refs already on disk, without fetching: precache
      // fetched them when it installed this version, so a version missing
      // from them is not installed.
      String? resolved;
      try {
        resolved = await shorebirdFlutter.resolveFlutterRevision(
          versionOrHash,
        );
      } on Exception catch (error) {
        logger.detail('Unable to resolve Flutter $versionOrHash: $error');
      }
      if (resolved == null) return notInstalled();
      revision = resolved;
    }

    if (!shorebirdFlutter.isInstalled(revision: revision)) {
      return notInstalled();
    }

    final path = shorebirdFlutter.installDirectory(revision: revision).path;
    if (isJsonMode) {
      emitJsonSuccess({'path': path, 'revision': revision});
    } else {
      output.writeln(path);
    }
    return ExitCode.success.code;
  }
}
