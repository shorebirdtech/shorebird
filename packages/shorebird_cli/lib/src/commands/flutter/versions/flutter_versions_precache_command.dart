import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';

/// {@template flutter_versions_precache_command}
/// `shorebird flutter versions precache X.Y.Z`
/// Ensures a given flutter version is cached.
/// {@endtemplate}
class FlutterVersionsPrecacheCommand extends ShorebirdCommand {
  /// {@macro flutter_versions_precache_command}
  FlutterVersionsPrecacheCommand();

  @override
  String get description => 'Precache a specific Flutter version.';

  @override
  String get name => 'precache';

  @override
  Future<int> run() async {
    final flutterVersionArg = argResults?.rest.first;

    if (flutterVersionArg == null) {
      logger.err('No Flutter version specified.');
      return ExitCode.usage.code;
    }

    final targetFlutterRevision = await shorebirdFlutter.resolveFlutterRevision(
      flutterVersionArg,
    );
    if (targetFlutterRevision == null) {
      logger.err('Invalid Flutter revision: $flutterVersionArg');
      return ExitCode.usage.code;
    }

    await cache.updateAll();
    final progress = logger.progress(
      'Caching Flutter version $targetFlutterRevision',
    );
    // Install revision runs precache for us.
    await shorebirdFlutter.installRevision(revision: targetFlutterRevision);
    progress.complete(
      'Flutter version $targetFlutterRevision cached successfully.',
    );

    return ExitCode.success.code;
  }
}
