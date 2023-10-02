import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/adb.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/bundletool.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/ios_deploy.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// {@template preview_command}
/// `shorebird preview` command.
/// {@endtemplate}
class PreviewCommand extends ShorebirdCommand {
  /// {@macro preview_command}
  PreviewCommand({
    http.Client? httpClient,
  }) : _httpClient = httpClient ??
            retryingHttpClient(LoggingClient(httpClient: http.Client())) {
    argParser
      ..addOption(
        'device-id',
        abbr: 'd',
        help: 'The ID of the device or simulator to preview the release on.',
      )
      ..addOption(
        'app-id',
        help: 'The ID of the app to preview the release for.',
      )
      ..addOption(
        'release-version',
        help: 'The version of the release (e.g. "1.0.0").',
      )
      ..addOption(
        'platform',
        allowed: [ReleasePlatform.android.name, ReleasePlatform.ios.name],
        allowedHelp: {
          ReleasePlatform.android.name: 'Android',
          ReleasePlatform.ios.name: 'iOS',
        },
        help: 'The platform of the release.',
      );
  }

  final http.Client _httpClient;

  @override
  String get name => 'preview';

  @override
  String get description => 'Preview a specific release on a device.';

  @override
  Future<int> run() async {
    // TODO(bryanoltman): check preview target and run either
    // doctor.iosValidators or doctor.androidValidators as appropriate.
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final appId = results['app-id'] as String? ?? await promptForApp();

    if (appId == null) {
      logger.info('No apps found');
      return ExitCode.success.code;
    }

    final releases = await codePushClientWrapper.getReleases(
      appId: appId,
      sideloadableOnly: true,
    );

    final releaseVersion = results['release-version'] as String? ??
        await promptForReleaseVersion(releases);

    final release = releases.firstWhereOrNull(
      (r) => r.version == releaseVersion,
    );

    if (releaseVersion == null || release == null) {
      // TODO(bryanoltman): link to FAQ explaining which releases are
      // previewable.
      logger.info('No previewable releases found');
      return ExitCode.success.code;
    }

    final platform = ReleasePlatform.values.byName(
      results['platform'] as String? ?? await promptForPlatform(release),
    );

    final deviceId = results['device-id'] as String?;
    const channel = 'stable';

    return switch (platform) {
      ReleasePlatform.android => installAndLaunchAndroid(
          appId: appId,
          release: release,
          deviceId: deviceId,
          channel: channel,
        ),
      ReleasePlatform.ios => installAndLaunchIos(
          appId: appId,
          release: release,
          deviceId: deviceId,
          channel: channel,
        ),
    };
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

  Future<String?> promptForReleaseVersion(List<Release> releases) async {
    if (releases.isEmpty) return null;
    final release = logger.chooseOne(
      'Which release would you like to preview?',
      choices: releases,
      display: (release) => release.version,
    );
    return release.version;
  }

  Future<String> promptForPlatform(Release release) async {
    final platforms = release.platformStatuses.keys.map((p) => p.name).toList();
    final platform = logger.chooseOne(
      'Which platform would you like to preview?',
      choices: platforms,
    );
    return platform;
  }

  Future<int> installAndLaunchAndroid({
    required String appId,
    required Release release,
    required String channel,
    String? deviceId,
  }) async {
    const platform = ReleasePlatform.android;
    final aabFile = File(
      getArtifactPath(
        appId: appId,
        release: release,
        platform: platform,
        extension: 'aab',
      ),
    );

    if (!aabFile.existsSync()) {
      aabFile.createSync(recursive: true);
      final downloadArtifactProgress = logger.progress('Downloading release');
      try {
        final releaseAabArtifact =
            await codePushClientWrapper.getReleaseArtifact(
          appId: appId,
          releaseId: release.id,
          arch: 'aab',
          platform: platform,
        );

        await artifactManager.downloadFile(
          Uri.parse(releaseAabArtifact.url),
          httpClient: _httpClient,
          outputPath: aabFile.path,
        );
        downloadArtifactProgress.complete();
      } catch (error) {
        downloadArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final apksPath = getArtifactPath(
      appId: appId,
      release: release,
      platform: platform,
      extension: 'apks',
    );

    if (File(apksPath).existsSync()) File(apksPath).deleteSync();
    final progress = logger.progress('Using channel $channel');
    try {
      await setChannelOnAab(aabFile: aabFile, channel: channel);
      progress.complete();
    } catch (error) {
      progress.fail('$error');
      return ExitCode.software.code;
    }

    final extractMetadataProgress = logger.progress('Extracting metadata');
    late String package;
    try {
      package = await bundletool.getPackageName(aabFile.path);
      extractMetadataProgress.complete();
    } catch (error) {
      extractMetadataProgress.fail('$error');
      return ExitCode.software.code;
    }

    final buildApksProgress = logger.progress('Building apks');
    try {
      await bundletool.buildApks(bundle: aabFile.path, output: apksPath);
      buildApksProgress.complete();
    } catch (error) {
      buildApksProgress.fail('$error');
      return ExitCode.software.code;
    }

    final installApksProgress = logger.progress('Installing apks');
    try {
      await bundletool.installApks(apks: apksPath, deviceId: deviceId);
      installApksProgress.complete();
    } catch (error) {
      installApksProgress.fail('$error');
      return ExitCode.software.code;
    }

    final startAppProgress = logger.progress('Starting app');
    try {
      await adb.startApp(package: package, deviceId: deviceId);
      startAppProgress.complete();
    } catch (error) {
      startAppProgress.fail('$error');
      return ExitCode.software.code;
    }

    final process = await adb.logcat(filter: 'flutter', deviceId: deviceId);
    process.stdout.listen((event) {
      logger.info(utf8.decode(event));
    });
    process.stderr.listen((event) {
      logger.err(utf8.decode(event));
    });

    return process.exitCode;
  }

  Future<int> installAndLaunchIos({
    required String appId,
    required Release release,
    required String channel,
    String? deviceId,
  }) async {
    const platform = ReleasePlatform.ios;
    final runnerDirectory = Directory(
      getArtifactPath(
        appId: appId,
        release: release,
        platform: platform,
        extension: 'app',
      ),
    );

    if (!runnerDirectory.existsSync()) {
      final downloadArtifactProgress = logger.progress('Downloading release');
      try {
        final releaseRunnerArtifact =
            await codePushClientWrapper.getReleaseArtifact(
          appId: appId,
          releaseId: release.id,
          arch: 'runner',
          platform: platform,
        );

        final archivePath = await artifactManager.downloadFile(
          Uri.parse(releaseRunnerArtifact.url),
          httpClient: _httpClient,
        );
        await artifactManager.extractZip(
          zipFile: File(archivePath),
          outputDirectory: runnerDirectory,
        );
        downloadArtifactProgress.complete();
      } catch (error) {
        downloadArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final progress = logger.progress('Using channel $channel');
    try {
      await setChannelOnRunner(
        runnerDirectory: runnerDirectory,
        channel: channel,
      );
      progress.complete();
    } catch (error) {
      progress.fail('$error');
      return ExitCode.software.code;
    }

    try {
      final exitCode = await iosDeploy.installAndLaunchApp(
        bundlePath: runnerDirectory.path,
        deviceId: deviceId,
      );
      return exitCode;
    } catch (error) {
      return ExitCode.software.code;
    }
  }

  String getArtifactPath({
    required String appId,
    required Release release,
    required ReleasePlatform platform,
    required String extension,
  }) {
    final previewDirectory = cache.getPreviewDirectory(appId);
    return p.join(
      previewDirectory.path,
      '${platform.name}_${release.version}.$extension',
    );
  }

  /// Sets the channel property in the shorebird.yaml file inside the Runner.app
  Future<void> setChannelOnRunner({
    required Directory runnerDirectory,
    required String channel,
  }) async {
    await Isolate.run(() async {
      final shorebirdYaml = File(
        p.join(
          runnerDirectory.path,
          'Frameworks',
          'App.framework',
          'flutter_assets',
          'shorebird.yaml',
        ),
      );

      if (!shorebirdYaml.existsSync()) {
        throw Exception('Unable to find shorebird.yaml');
      }

      final yaml = YamlEditor(shorebirdYaml.readAsStringSync())
        ..update(['channel'], channel);

      shorebirdYaml.writeAsStringSync(yaml.toString(), flush: true);
    });
  }

  /// Unzips the `.aab` and sets the channel property in the shorebird.yaml
  /// file inside the base module and then re-zips the `.aab`.
  Future<void> setChannelOnAab({
    required File aabFile,
    required String channel,
  }) async {
    // Getting the reference here since we cannot inside the isolate.
    final extractZip = artifactManager.extractZip;

    await Isolate.run(() async {
      final tempDir = Directory.systemTemp.createTempSync();
      final basename = p.basenameWithoutExtension(aabFile.path);
      final outputPath = p.join(tempDir.path, basename);

      await extractZip(
        zipFile: aabFile,
        outputDirectory: Directory(outputPath),
      );

      final shorebirdYaml = File(
        p.join(
          outputPath,
          'base',
          'assets',
          'flutter_assets',
          'shorebird.yaml',
        ),
      );

      if (!shorebirdYaml.existsSync()) {
        throw Exception('Unable to find shorebird.yaml');
      }

      final yaml = YamlEditor(shorebirdYaml.readAsStringSync())
        ..update(['channel'], channel);

      shorebirdYaml.writeAsStringSync(yaml.toString(), flush: true);

      // This is equivalent to `zip --no-dir-entries`
      // Which does NOT create entries in the zip archive for directories.
      // It's important to do this because bundletool expects the
      // .aab not to contain any directories.
      final encoder = ZipFileEncoder()..create(aabFile.path);
      for (final file in Directory(outputPath).listSync(recursive: true)) {
        if (file is File) {
          await encoder.addFile(
            file,
            file.path.replaceFirst('$outputPath/', ''),
          );
        }
      }
      encoder.close();
      tempDir.deleteSync(recursive: true);
    });
  }
}
