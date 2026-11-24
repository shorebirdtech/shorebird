import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache_pruning.dart';
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
/// It installs nothing, not even the pinned Flutter other commands install
/// first (see [ShorebirdCommand.usesPinnedFlutter]): a Flutter that is not
/// installed, pinned or `--flutter-version`, is an error naming the
/// `shorebird flutter precache` command that installs it, so a script never
/// waits on a download it didn't ask for.
/// It does record the install as used, as a build would: the caller is about
/// to build with it, and an install that goes unused for long enough is
/// pruned after the next command, this one included.
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

  // It reports a missing Flutter instead of installing it.
  @override
  bool get usesPinnedFlutter => false;

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
    // `shorebird flutter path 3.38.5` would otherwise print the pinned
    // Flutter's directory, and a script would build with the wrong Flutter.
    if (results.rest.isNotEmpty) {
      return reportError(
        message: 'shorebird flutter path takes no arguments.',
        hint:
            'Pass a version with --flutter-version, e.g. '
            '--flutter-version=${results.rest.first}',
      );
    }

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
    int notInstalled({bool isResolved = true}) => reportError(
      message: '$label is not installed.',
      hint: isResolved
          ? 'Run: $precacheCommand'
          : 'Run: $precacheCommand\n'
                'shorebird flutter versions list shows the versions '
                'Shorebird has.',
      code: JsonErrorCode.preconditionFailed,
      exitCode: ExitCode.unavailable.code,
    );

    final String revision;
    if (isPinned) {
      revision = shorebirdEnv.flutterRevision;
    } else {
      // Resolved from the refs already on disk, without cloning or fetching:
      // precache left them there when it installed this version, so a
      // version missing from them is not installed.
      String? resolved;
      try {
        resolved = await shorebirdFlutter.resolveInstalledFlutterRevision(
          versionOrHash,
        );
      } on Exception catch (error) {
        logger.detail('Unable to resolve Flutter $versionOrHash: $error');
      }
      if (resolved == null) return notInstalled(isResolved: false);
      revision = resolved;
    }

    if (!shorebirdFlutter.isInstalled(revision: revision)) {
      return notInstalled();
    }

    final directory = shorebirdFlutter.installDirectory(revision: revision);
    markUsed(directory);
    final path = directory.path;
    if (isJsonMode) {
      emitJsonSuccess({'path': path, 'revision': revision});
    } else {
      output.writeln(path);
    }
    return ExitCode.success.code;
  }
}
