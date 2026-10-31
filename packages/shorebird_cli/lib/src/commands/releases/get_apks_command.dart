import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:io/io.dart' show copyPath;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/executables/bundletool.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/release_chooser.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template get_apk_command}
/// Generates an APK for the release with the specified version.
/// {@endtemplate}
class GetApksCommand extends ShorebirdCommand with AppScopedCommand {
  /// {@macro get_apk_command}
  GetApksCommand() {
    addAppScopeOptions();
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help:
            'The version of the release to generate APKs for '
            '(e.g. "1.0.0+1"). Prompts for selection if omitted.',
      )
      ..addOption(
        'out',
        abbr: 'o',
        help: 'The output directory for the generated apks.',
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
      'Generates apk(s) for the specified release version.\n\n'
      'Writes to the project build directory unless --out is given, which is '
      'required when running outside a Shorebird project. Pass --no-universal '
      'for split-per-ABI apks instead of one that runs anywhere.\n\n'
      'Examples:\n'
      '  shorebird releases get-apks --release-version 1.0.0+1\n'
      '  shorebird releases get-apks --release-version 1.0.0+1 --out ./build\n'
      '  shorebird releases get-apks --release-version 1.0.0+1 --no-universal';

  /// The app ID, from `--app-id` or shorebird.yaml. Set by [run].
  late final String appId;

  /// The output directory path for the generated apks. Defaults to the
  /// project's build directory if not provided.
  late String? outDirectoryArg = results.findOption(
    'out',
    argParser: argParser,
  );

  @override
  Future<int> run() async {
    final resolved = await resolveAppId();
    if (resolved.errorCode case final errorCode?) return errorCode;
    appId = resolved.appId;

    // Without a project there is no build directory to default to.
    if (outDirectoryArg == null &&
        shorebirdEnv.getShorebirdProjectRoot() == null) {
      return reportError(
        message:
            '--out is required when not running in a Shorebird project, so '
            'there is no build directory to write the apks to.',
      );
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

    // The downloaded aab, the built .apks and the extracted apks are staged
    // in one temporary directory created here, deleted once the apks are in
    // the output directory.
    final stagingDirectory = Directory.systemTemp.createTempSync();
    try {
      return await _buildApks(
        release: release,
        releaseArtifact: releaseArtifact,
        stagingDirectory: stagingDirectory,
      );
    } finally {
      stagingDirectory.deleteTemporarySync();
    }
  }

  Future<int> _buildApks({
    required Release release,
    required ReleaseArtifact releaseArtifact,
    required Directory stagingDirectory,
  }) async {
    final aabFile = await _downloadAab(
      releaseArtifact: releaseArtifact,
      outputPath: p.join(stagingDirectory.path, 'release.aab'),
    );
    final apksFile = File(
      p.join(stagingDirectory.path, '${appId}_${release.version}.apks'),
    );
    final extractedDirectory = Directory(
      p.join(stagingDirectory.path, 'extracted'),
    )..createSync();

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

    // Extract somewhere fresh first, so the apks reported are the ones this
    // run produced rather than whatever earlier runs left in the output
    // directory.
    await extractFileToDisk(apksZipFile.path, extractedDirectory.path);
    final extractedApkNames = extractedDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.apk'))
        .map((file) => p.basename(file.path))
        .toList();
    await copyPath(extractedDirectory.path, outputDirectory.path);

    final apks = [
      for (final name in extractedApkNames)
        File(p.join(outputDirectory.path, name)),
    ];
    if (apks.isNotEmpty) {
      logger.info('Generated ${apks.length} apk(s):');
      for (final file in apks) {
        logger.info('  - ${lightCyan.wrap(file.path)}');
      }
    } else {
      logger.err(
        'No apks found in the generated .apks archive for release '
        '${release.version}.',
      );
      return ExitCode.software.code;
    }

    logger.info('apk(s) generated at ${lightCyan.wrap(outputDirectory.path)}');
    return ExitCode.success.code;
  }

  Future<Release> _promptForRelease() async {
    final releases = await codePushClientWrapper.getReleases(
      appId: appId,
      sideloadableOnly: true,
    );

    if (releases.isEmpty) {
      throw CommandError(
        message: 'No Android releases found for app $appId.',
        hint: 'Run: shorebird release android',
      );
    }

    return chooseRelease(
      releases: releases,
      action: 'generate an apk for',
    );
  }

  Future<File> _downloadAab({
    required ReleaseArtifact releaseArtifact,
    required String outputPath,
  }) async {
    final File artifactFile;
    try {
      artifactFile = await artifactManager.downloadWithProgressUpdates(
        Uri.parse(releaseArtifact.url),
        message: 'Downloading aab',
        outputPath: outputPath,
      );
    } on Exception catch (_) {
      throw CommandError(
        message: 'Could not download the release artifact.',
        hint:
            'Fix the cause above (often the network or disk space), then run '
            'the command again.',
        exitCode: ExitCode.software,
      );
    }

    return artifactFile;
  }
}
