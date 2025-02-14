import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/executables/bundletool.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template get_apk_command}
/// Generates an APK for the release with the specified version.
/// {@endtemplate}
class GetApksCommand extends ShorebirdCommand {
  /// {@macro get_apk_command}
  GetApksCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: 'The release version to generate apks for',
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The build flavor to generate an apks for',
      )
      ..addOption(
        'out',
        abbr: 'o',
        help: 'The output directory for the generated apks',
      )
      ..addFlag(
        'universal',
        defaultsTo: true,
        help: 'Whether to generate a universal apk. Defaults to true.',
      );
  }

  @override
  String get name => 'get-apks';

  @override
  String get description =>
      'Generates apk(s) for the specified release version';

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The build flavor, if provided.
  late String? flavor = results.findOption(
    CommonArguments.flavorArg.name,
    argParser: argParser,
  );

  /// The output directory path for the generated apks. Defaults to the
  /// project's build directory if not provided.
  late String? outDirectoryArg = results.findOption(
    'out',
    argParser: argParser,
  );

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final Release release;
    if (results.wasParsed(CommonArguments.releaseVersionArg.name)) {
      final releaseVersion =
          results[CommonArguments.releaseVersionArg.name] as String;
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    } else {
      release = await _promptForRelease();
    }

    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: 'aab',
      platform: ReleasePlatform.android,
    );

    final aabFile = await _downloadAab(releaseArtifact: releaseArtifact);
    final apksFile = File(
      p.join(
        Directory.systemTemp.createTempSync().path,
        '${appId}_${release.version}.apks',
      ),
    );

    final buildApksProgress = logger.progress(
      'Building apks for release ${release.version} (app: $appId)',
    );
    try {
      await bundletool.buildApks(
        bundle: aabFile.path,
        output: apksFile.path,
        universal: results['universal'] as bool,
      );
      buildApksProgress.complete();
    } on Exception catch (error) {
      buildApksProgress.fail('$error');
      return ExitCode.software.code;
    }

    final apksZipFile = apksFile.renameSync('${apksFile.path}.zip');

    final Directory outputDirectory;
    if (outDirectoryArg != null) {
      outputDirectory = Directory(outDirectoryArg!);
      if (!outputDirectory.existsSync()) {
        outputDirectory.createSync(recursive: true);
      }
    } else {
      // The output of `flutter build apk` is build/app/outputs/flutter-apk,
      // so we move the generated apk to build/app/outputs/shorebird-apk.
      outputDirectory = Directory(
        p.join(
          shorebirdEnv.getShorebirdProjectRoot()!.path,
          'build',
          'app',
          'outputs',
          'shorebird-apk',
        ),
      )..createSync(recursive: true);
    }

    await extractFileToDisk(apksZipFile.path, outputDirectory.path);

    logger.info('apk(s) generated at ${lightCyan.wrap(outputDirectory.path)}');
    return ExitCode.success.code;
  }

  Future<Release> _promptForRelease() async {
    final releases = await codePushClientWrapper.getReleases(
      appId: appId,
      sideloadableOnly: true,
    );

    if (releases.isEmpty) {
      logger.err('No releases found for app $appId');
      throw ProcessExit(ExitCode.usage.code);
    }

    return logger.chooseOne<Release>(
      'Which release would you like to generate an apk for?',
      choices: releases.sortedBy((r) => r.createdAt).reversed.toList(),
      display: (r) => r.version,
    );
  }

  Future<File> _downloadAab({required ReleaseArtifact releaseArtifact}) async {
    final File artifactFile;
    try {
      artifactFile = await artifactManager.downloadWithProgressUpdates(
        Uri.parse(releaseArtifact.url),
        message: 'Downloading aab',
      );
    } on Exception catch (_) {
      throw ProcessExit(ExitCode.software.code);
    }

    return artifactFile;
  }
}
