import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';

/// {@template flutter_versions_use_command}
/// `shorebird flutter versions use`
/// Use a different Flutter version.
/// {@endtemplate}
class FlutterVersionsUseCommand extends ShorebirdCommand {
  /// {@macro flutter_versions_use_command}
  FlutterVersionsUseCommand();

  @override
  String get description => 'Use a different Flutter version.';

  @override
  String get name => 'use';

  @override
  Future<int> run() async {
    if (results.rest.isEmpty) {
      logger.err(
        '''
No version specified.
Usage: shorebird flutter versions use <version>
Use `shorebird flutter versions list` to list available versions.''',
      );
      return ExitCode.usage.code;
    }

    if (results.rest.length > 1) {
      logger.err('''
Too many arguments.
Usage: shorebird flutter versions use <version>''');
      return ExitCode.usage.code;
    }

    final version = results.rest.first;
    final fetchFlutterVersionsProgress = logger.progress(
      'Fetching Flutter versions',
    );
    final List<String> versions;
    try {
      versions = await shorebirdFlutter.getVersions();
      fetchFlutterVersionsProgress.complete();
    } catch (error) {
      fetchFlutterVersionsProgress.fail('Failed to fetch Flutter versions.');
      logger.err('$error');
      return ExitCode.software.code;
    }

    if (!versions.contains(version)) {
      logger.err('''
Version $version not found.
Use `shorebird flutter versions list` to list available versions.''');
      return ExitCode.software.code;
    }

    final installRevisionProgress = logger.progress(
      'Installing Flutter $version',
    );
    try {
      await shorebirdFlutter.useVersion(version: version);
      installRevisionProgress.complete();
    } catch (error) {
      installRevisionProgress.fail('Failed to install Flutter $version.');
      logger.err('$error');
      return ExitCode.software.code;
    }

    return ExitCode.success.code;
  }
}
