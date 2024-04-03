import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// {@template preview_command}
/// `shorebird preview` command.
/// {@endtemplate}
class PreviewCommand extends ShorebirdCommand {
  /// {@macro preview_command}
  PreviewCommand() {
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
        allowed: ReleasePlatform.values.map((e) => e.name),
        allowedHelp: {
          for (final p in ReleasePlatform.values) p.name: p.displayName,
        },
        help: 'The platform of the release.',
      )
      ..addFlag(
        'staging',
        negatable: false,
        help: 'Preview the release on the staging environment.',
      );
  }

  /// Returns the platforms that can be previewed on the current OS.
  static List<ReleasePlatform> get supportedReleasePlatforms {
    if (platform.isMacOS) {
      return ReleasePlatform.values;
    } else {
      return ReleasePlatform.values
          .where((p) => p != ReleasePlatform.ios)
          .toList();
    }
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
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final shorebirdYaml = shorebirdEnv.getShorebirdYaml();
    final String? appId;

    final flavors = shorebirdYaml?.flavors;

    if (results.wasParsed('app-id')) {
      appId = results['app-id'] as String;
    } else if (shorebirdYaml != null && flavors == null) {
      appId = shorebirdYaml.appId;
    } else if (shorebirdYaml != null && flavors != null) {
      final flavorOptions = flavors.keys.toList();
      final choosenFlavor = logger.chooseOne<String>(
        'Which app flavor?',
        choices: flavorOptions,
      );
      appId = flavors[choosenFlavor];
    } else {
      appId = await promptForApp();
    }

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
      logger.info('No previewable releases found');
      return ExitCode.success.code;
    }

    final availablePlatforms = release.activePlatforms
        .where((p) => supportedReleasePlatforms.contains(p))
        .toList();
    if (availablePlatforms.isEmpty) {
      final activePlatformsString =
          release.activePlatforms.map((p) => p.displayName).join(', ');
      logger.err(
        '''This release can only be previewed on platforms that support $activePlatformsString''',
      );
      return ExitCode.software.code;
    }

    final ReleasePlatform releasePlatform;
    if (availablePlatforms.length == 1) {
      releasePlatform = availablePlatforms.first;
    } else if (results['platform'] != null) {
      releasePlatform =
          ReleasePlatform.values.byName(results['platform'] as String);
    } else {
      releasePlatform = await promptForPlatform(availablePlatforms);
    }

    final deviceId = results['device-id'] as String?;
    final isStaging = results['staging'] == true;
    final track =
        isStaging ? DeploymentTrack.staging : DeploymentTrack.production;

    return switch (releasePlatform) {
      ReleasePlatform.android => installAndLaunchAndroid(
          appId: appId,
          release: release,
          deviceId: deviceId,
          track: track,
        ),
      ReleasePlatform.ios => installAndLaunchIos(
          appId: appId,
          release: release,
          deviceId: deviceId,
          track: track,
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

  Future<ReleasePlatform> promptForPlatform(
    List<ReleasePlatform> platforms,
  ) async {
    final platformNames = platforms.map((p) => p.displayName).toList();
    final platform = logger.chooseOne(
      'Which platform would you like to preview?',
      choices: platformNames,
    );
    return ReleasePlatform.values.firstWhere((p) => p.displayName == platform);
  }

  Future<int> installAndLaunchAndroid({
    required String appId,
    required Release release,
    required DeploymentTrack track,
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
    final progress = logger.progress('Using ${track.name} track');
    try {
      await setChannelOnAab(aabFile: aabFile, channel: track.channel);
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
      await adb.clearAppData(package: package, deviceId: deviceId);
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
    required DeploymentTrack track,
    String? deviceId,
  }) async {
    await iosDeploy.installIfNeeded();

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

        final archiveFile = await artifactManager.downloadFile(
          Uri.parse(releaseRunnerArtifact.url),
        );
        await artifactManager.extractZip(
          zipFile: archiveFile,
          outputDirectory: runnerDirectory,
        );
        downloadArtifactProgress.complete();
      } catch (error) {
        downloadArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final progress = logger.progress('Using ${track.name} track');
    try {
      await setChannelOnRunner(
        runnerDirectory: runnerDirectory,
        channel: track.channel,
      );
      progress.complete();
    } catch (error) {
      progress.fail('$error');
      return ExitCode.software.code;
    }

    try {
      final deviceLocateProgress = logger.progress('Locating device for run');
      final AppleDevice? deviceForLaunch;
      // Try to find a device using devicectl first. If that fails, fall back to
      // ios-deploy.
      if (deviceId != null) {
        final deviceCtlDevices = await devicectl.listAvailableIosDevices();
        deviceForLaunch = deviceCtlDevices.firstWhereOrNull(
          (device) => device.udid == deviceId,
        );
      } else {
        deviceForLaunch = await devicectl.deviceForLaunch();
      }

      final shouldUseDeviceCtl = deviceForLaunch != null;
      final progressCompleteMessage = deviceForLaunch != null
          ? 'Using device ${deviceForLaunch.name}'
          : '''No iOS 17+ device found, looking for devices running iOS 16 or lower''';
      deviceLocateProgress.complete(progressCompleteMessage);

      final int installExitCode;
      if (shouldUseDeviceCtl) {
        logger.detail(
          '''Using devicectl to install and launch on device ${deviceForLaunch.udid}.''',
        );
        installExitCode = await devicectl.installAndLaunchApp(
          runnerAppDirectory: runnerDirectory,
          device: deviceForLaunch,
        );
      } else {
        logger.detail('Using ios-deploy to install and launch.');
        installExitCode = await iosDeploy.installAndLaunchApp(
          bundlePath: runnerDirectory.path,
          deviceId: deviceId,
        );
      }

      return installExitCode;
    } catch (error, stackTrace) {
      logger.detail('Error launching app. $error $stackTrace');
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
      final outputPath = p.join(tempDir.path, 'tmp.aab');

      await extractZip(
        zipFile: aabFile,
        outputDirectory: Directory(outputPath),
      );

      final shorebirdYamlFile = File(
        p.join(
          outputPath,
          'base',
          'assets',
          'flutter_assets',
          'shorebird.yaml',
        ),
      );

      if (!shorebirdYamlFile.existsSync()) {
        throw Exception('Unable to find shorebird.yaml');
      }

      final yamlText = shorebirdYamlFile.readAsStringSync();
      final yaml = loadYaml(yamlText) as YamlMap;
      final yamlChannel = yaml['channel'];

      if (yamlChannel == null &&
          channel == DeploymentTrack.production.channel) {
        // We would be updating the channel to the default value.
        return;
      }

      if (yamlChannel == channel) {
        // Updating this channel would be a no-op.
        return;
      }

      final yamlEditor = YamlEditor(yamlText)..update(['channel'], channel);
      shorebirdYamlFile.writeAsStringSync(yamlEditor.toString(), flush: true);

      // This is equivalent to `zip --no-dir-entries`
      // Which does NOT create entries in the zip archive for directories.
      // It's important to do this because bundletool expects the
      // .aab not to contain any directories.
      final tmpAabFile = File(p.join(tempDir.path, p.basename(aabFile.path)));
      final encoder = ZipFileEncoder()..create(tmpAabFile.path);
      for (final file in Directory(outputPath).listSync(recursive: true)) {
        if (file is File) {
          await encoder.addFile(
            file,
            file.path.replaceFirst('$outputPath${p.separator}', ''),
          );
        }
      }
      encoder.close();

      // Replace the existing preview artifact with the updated one.
      tmpAabFile.copySync(aabFile.path);
      tempDir.deleteSync(recursive: true);
    });
  }
}

extension Previewable on Release {
  List<ReleasePlatform> get activePlatforms => platformStatuses.entries
      .where((e) => e.value == ReleaseStatus.active)
      .map((e) => e.key)
      .toList();
}
