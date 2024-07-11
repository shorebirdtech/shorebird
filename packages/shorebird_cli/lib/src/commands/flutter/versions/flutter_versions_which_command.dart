import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';

/// {@template flutter_versions_which_command}
/// `shorebird flutter versions which [rev]`
/// Based on the provided revision, determine the Flutter version.
/// {@endtemplate}
class FlutterVersionsWhichCommand extends ShorebirdCommand {
  /// {@macro flutter_versions_which_command}
  FlutterVersionsWhichCommand() {
    argParser.addOption(
      'rev',
      help: 'The revision to determine the Flutter version.',
    );
  }

  @override
  String get description =>
      '''Shows the flutter version string for a given revision.''';

  @override
  String get name => 'which';

  @override
  Future<int> run() async {
    final revision = results['rev'] as String;
    final progress = logger.progress(
      'Finding Flutter Version based on revision: $revision',
    );

    try {
      final version = await shorebirdFlutter.getVersionString(
        revision: revision,
      );

      progress.complete(
        'Flutter Version: ${version ?? 'Unknown'}',
      );
    } catch (error) {
      progress.fail('Failed to determine Flutter version.');
      logger.err('$error');
      return ExitCode.software.code;
    }

    return ExitCode.success.code;
  }
}
