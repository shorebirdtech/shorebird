import 'dart:async';
import 'dart:convert';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/adb.dart';
import 'package:shorebird_cli/src/bundletool.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template preview_command}
/// `shorebird preview` command.
/// {@endtemplate}
class PreviewCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdValidationMixin {
  /// {@macro preview_command}
  PreviewCommand() {
    argParser
      ..addOption(
        'device-id',
        help: 'The ID of the device or simulator to preview the release on.',
      )
      ..addOption(
        'app-id',
        help: 'The ID of the app to preview the release for.',
      )
      ..addOption(
        'release-version',
        help: 'The version of the release (e.g. "1.0.0").',
      );
  }

  @override
  String get name => 'preview';

  @override
  String get description => 'Preview a specific release on a device.';

  @override
  Future<int> run() async {
    // TODO(bryanoltman): check preview target and run either
    // doctor.iosValidators or doctor.androidValidators as appropriate.
    try {
      await validatePreconditions(checkUserIsAuthenticated: true);
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    const platform = ReleasePlatform.android;
    final appId = results['app-id'] as String? ?? await promptForApp();

    if (appId == null) {
      logger.info('No apps found');
      return ExitCode.success.code;
    }

    final releaseVersion = results['release-version'] as String? ??
        await promptForReleaseVersion(appId);

    if (releaseVersion == null) {
      logger.info('No releases found');
      return ExitCode.success.code;
    }

    final previewDirectory = cache.getPreviewDirectory(appId);
    final aabPath = p.join(
      previewDirectory.path,
      '${platform}_$releaseVersion.aab',
    );

    if (!File(aabPath).existsSync()) {
      final downloadArtifactProgress = logger.progress('Downloading release');
      try {
        final release = await codePushClientWrapper.getRelease(
          appId: appId,
          releaseVersion: releaseVersion,
        );
        final releaseAabArtifact =
            await codePushClientWrapper.getReleaseArtifact(
          appId: appId,
          releaseId: release.id,
          // TODO(felangel): add iOS support
          arch: 'aab',
          platform: platform,
        );

        await releaseAabArtifact.url.download(aabPath);
        downloadArtifactProgress.complete();
      } catch (error) {
        downloadArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final extractMetadataProgress = logger.progress('Extracting metadata');
    late String package;
    try {
      package = await bundletool.getPackageName(aabPath);
      extractMetadataProgress.complete();
    } catch (error) {
      extractMetadataProgress.fail('$error');
      return ExitCode.software.code;
    }

    final apksPath = p.join(
      previewDirectory.path,
      '${platform}_$releaseVersion.apks',
    );

    if (!File(apksPath).existsSync()) {
      final buildApksProgress = logger.progress('Building apks');
      try {
        await bundletool.buildApks(bundle: aabPath, output: apksPath);
        buildApksProgress.complete();
      } catch (error) {
        buildApksProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final installApksProgress = logger.progress('Installing apks');
    try {
      await bundletool.installApks(apks: apksPath);
      installApksProgress.complete();
    } catch (error) {
      installApksProgress.fail('$error');
      return ExitCode.software.code;
    }

    final startAppProgress = logger.progress('Starting app');
    try {
      await adb.startApp(package);
      startAppProgress.complete();
    } catch (error) {
      startAppProgress.fail('$error');
      return ExitCode.software.code;
    }

    final process = await adb.logcat(filter: 'flutter');
    process.stdout.listen((event) {
      logger.info(utf8.decode(event));
    });
    process.stderr.listen((event) {
      logger.err(utf8.decode(event));
    });

    return process.exitCode;
  }

  Future<String?> promptForApp() async {
    final apps = await codePushClientWrapper.getApps();
    if (apps.isEmpty) return null;
    final app = logger.chooseOne(
      'Which app would you like to preview?',
      choices: apps,
      display: (app) => app.displayName,
    );
    return app.appId;
  }

  Future<String?> promptForReleaseVersion(String appId) async {
    final releases = await codePushClientWrapper.getReleases(appId: appId);
    if (releases.isEmpty) return null;
    final release = logger.chooseOne(
      'Which release would you like to preview?',
      choices: releases,
      display: (release) => release.version,
    );
    return release.version;
  }
}

extension on String {
  Future<void> download(String path) async {
    final uri = Uri.parse(this);
    final client = HttpClient();
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('Failed to download artifact at $this');
    }
    final file = File(path)..createSync(recursive: true);
    await response.pipe(file.openWrite());
  }
}
