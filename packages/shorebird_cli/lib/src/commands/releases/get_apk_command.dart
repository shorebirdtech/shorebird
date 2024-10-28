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
class GetApkCommand extends ShorebirdCommand {
  /// {@macro get_apk_command}
  GetApkCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: 'The release version to generate an apk for',
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The build flavor to generate an apk for',
      )
      ..addOption(
        'out',
        abbr: 'o',
        help: 'The output directory for the generated apks',
      );
  }

  @override
  String get name => 'get-apk';

  @override
  String get description =>
      'Generates an apk for the specified release version';

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The build flavor, if provided.
  late String? flavor = results.findOption(
    CommonArguments.flavorArg.name,
    argParser: argParser,
  );

  /// The output directory path for the generated apks. Defaults to the
  /// project's build directory if not provided.
  late String? outDirectoryPath = results.findOption(
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
      await bundletool.buildApks(bundle: aabFile.path, output: apksFile.path);
      buildApksProgress.complete();
    } catch (error) {
      buildApksProgress.fail('$error');
      return ExitCode.software.code;
    }

    final apksZipFile = apksFile.renameSync('${apksFile.path}.zip');
    final apkDirectory = Directory(apksFile.path.replaceAll('.apks', ''));
    await extractFileToDisk(
      apksZipFile.path,
      apkDirectory.path,
    );

    final apkFile = apkDirectory
        .listSync()
        .firstWhere((f) => p.extension(f.path) == '.apk') as File;

    final File outApkFile;
    if (outDirectoryPath != null) {
      final outDirectory = Directory(outDirectoryPath!);
      if (!outDirectory.existsSync()) {
        outDirectory.createSync(recursive: true);
      }

      outApkFile = File(p.join(outDirectory.path, p.basename(apkFile.path)));
    } else {
      // The output of `flutter build apk` is build/app/outputs/flutter-apk,
      // so we move the generated apk to build/app/outputs/shorebird-apk.
      outApkFile = File(
        p.join(
          shorebirdEnv.getShorebirdProjectRoot()!.path,
          'build',
          'app',
          'outputs',
          'shorebird-apk',
          '${appId}_${release.version}.apk',
        ),
      )..createSync(recursive: true);
    }

    apkFile.renameSync(outApkFile.path);
    logger.info('apk generated at ${lightCyan.wrap(outApkFile.path)}');
    return ExitCode.success.code;
  }

  Future<Release> _promptForRelease() async {
    final releases = await codePushClientWrapper.getReleases(
      appId: appId,
      sideloadableOnly: true,
    );

    if (releases.isEmpty) {
      logger.warn(
        '''No releases found for app $appId. You need to make first a release before you can create a patch.''',
      );
      throw ProcessExit(ExitCode.usage.code);
    }

    return logger.chooseOne<Release>(
      'Which release would you like to generate an apk for?',
      choices: releases.sortedBy((r) => r.createdAt).reversed.toList(),
      display: (r) => r.version,
    );
  }

  Future<File> _downloadAab({
    required ReleaseArtifact releaseArtifact,
  }) async {
    final File artifactFile;
    try {
      artifactFile = await artifactManager.downloadWithProgressUpdates(
        Uri.parse(releaseArtifact.url),
        message: 'Downloading aab',
      );
    } catch (_) {
      throw ProcessExit(ExitCode.software.code);
    }

    return artifactFile;
  }
}
