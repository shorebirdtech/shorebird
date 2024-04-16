import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';

/// {@template release_command}
/// `shorebird release`
/// Create new app releases.
/// {@endtemplate}
class ReleaseCommand extends ShorebirdCommand {
  /// {@macro release_command}
  ReleaseCommand() {
    addSubcommand(ReleaseAarCommand());
    addSubcommand(ReleaseAndroidCommand());
    addSubcommand(ReleaseIosCommand());
    addSubcommand(ReleaseIosFrameworkCommand());
  }

  @override
  String get description => 'Manage your Shorebird app releases.';

  @override
  String get name => 'release';

  static void printConflictingFlutterRevisionError({
    required String existingFlutterRevision,
    required String currentFlutterRevision,
    required String releaseVersion,
  }) {
    logger.err(
      '''
${styleBold.wrap(lightRed.wrap('A release with version $releaseVersion already exists but was built using a different Flutter revision.'))}

  Existing release built with: ${lightCyan.wrap(existingFlutterRevision)}
  Current release built with: ${lightCyan.wrap(currentFlutterRevision)}

${styleBold.wrap(lightRed.wrap('All platforms for a given release must be built using the same Flutter revision.'))}

To resolve this issue, you can:
  * Re-run the release command with ${lightCyan.wrap('--flutter-version=$existingFlutterRevision')}
  * Delete the existing release and re-run the release command with the desired Flutter version.
  * Bump the release version and re-run the release command with the desired Flutter version.''',
    );
  }

  static void printPatchInstructions({
    required String name,
    required String releaseVersion,
    String? flavor,
    String? target,
    bool requiresReleaseVersion = false,
  }) {
    final baseCommand = [
      'shorebird patch',
      name,
      if (flavor != null) '--flavor=$flavor',
      if (target != null) '--target=$target',
    ].join(' ');
    logger.info(
      '''To create a patch for this release, run ${lightCyan.wrap('$baseCommand --release-version=$releaseVersion')}''',
    );

    if (!requiresReleaseVersion) {
      logger.info(
        '''

Note: ${lightCyan.wrap(baseCommand)} without the --release-version option will patch the current version of the app.
''',
      );
    }
  }
}
