import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template build_apk_command}
///
/// `shorebird build apk`
/// Build an Android APK file from your app.
/// {@endtemplate}
class BuildApkCommand extends ShorebirdCommand {
  /// {@macro build_apk_command}
  BuildApkCommand() {
    argParser
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      );
  }

  @override
  String get description => 'Build an Android APK file from your app.';

  @override
  String get name => 'apk';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final buildProgress = logger.progress('Building apk');
    try {
      await artifactBuilder.buildApk(flavor: flavor, target: target);
    } on ArtifactBuildException catch (error) {
      buildProgress.fail(error.message);
      return ExitCode.software.code;
    }

    buildProgress.complete();

    final apkDirPath = p.join('build', 'app', 'outputs', 'apk');
    final apkPath = flavor != null
        ? p.join(apkDirPath, flavor, 'release', 'app-$flavor-release.apk')
        : p.join(apkDirPath, 'release', 'app-release.apk');

    logger.info('''
📦 Generated an apk at:
${lightCyan.wrap(apkPath)}''');

    return ExitCode.success.code;
  }
}
