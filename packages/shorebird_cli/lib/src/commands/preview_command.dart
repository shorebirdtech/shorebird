// cspell:words devicectl endtemplate bryanoltman sideloadable previewable apks
// cspell:words bundletool
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
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
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.releaseVersionArg.description,
      )
      ..addOption(
        'platform',
        allowed: ReleasePlatform.values.map((e) => e.name),
        allowedHelp: {
          for (final p in ReleasePlatform.values) p.name: p.displayName,
        },
        help: 'The platform of the release.',
      )
      ..addOption(
        'ks',
        help: '''
Specifies the path to the deployment keystore used to sign the APKs.
If you don't include this flag, bundletool attempts to sign your APKs with a debug signing key.
This is only applicable when previewing Android releases.''',
      )
      ..addOption(
        'ks-pass',
        help: '''
Specifies your keystore password.
If you specify a password in plain text, qualify it with pass:.
If you pass the path to a file that contains the password, qualify it with file:.
If you specify a keystore using the --ks flag you must also specify a password.
This is only applicable when previewing Android releases.''',
      )
      ..addOption(
        'ks-key-pass',
        help: '''
Specifies the password for the signing key. If you specify a password in plain text, qualify it with pass:.
If you pass the path to a file that contains the password, qualify it with file:.
If this password is identical to the one for the keystore itself, you can omit this flag.
This is only applicable when previewing Android releases.''',
      )
      ..addOption(
        'ks-key-alias',
        help: '''
Specifies the alias of the signing key you want to use.
This is only applicable when previewing Android releases.''',
      )
      ..addFlag(
        'staging',
        negatable: false,
        help:
            '''[DEPRECATED] Preview the release on the staging environment. Use --track=staging instead.''',
        hide: true,
      )
      ..addOption(
        'track',
        help: 'The track to preview.',
        defaultsTo: DeploymentTrack.stable.channel,
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

  /// The deployment track to publish the patch to.
  DeploymentTrack get track => DeploymentTrack(results['track'] as String);

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

    if (results.wasParsed('staging')) {
      logger.err(
        '''The --staging flag is deprecated and will be removed in a future release. Use --track=staging instead.''',
      );
      return ExitCode.usage.code;
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
      final chosenFlavor = logger.chooseOne<String>(
        'Which app flavor?',
        choices: flavorOptions,
      );
      appId = flavors[chosenFlavor];
    } else {
      appId = await promptForApp();
    }

    if (appId == null) {
      logger.info('No apps found');
      return ExitCode.success.code;
    }

    // The information if a platform is previewable or not is on
    // the artifacts, we would need to query for the artifacts for all platforms
    // in a release to be able to know if a platform is previewable or not.
    //
    // To avoid making too many requests, we instead ask for all releases two
    // times.
    //
    // When querying for releases, we can ask for sideloadable only
    //
    // When sideloadableOnly is true, the API will only return releases that
    // have at least one platform that is previewable, and will not return
    // platforms that are not previewable.
    //
    // But when sideloadableOnly is false, the API will return all releases
    // with all platforms, including those that are not previewable.
    //
    // With these two lists, we can now determine if a platform is previewable
    // or not, by making a difference between the two lists.
    final (allReleases, sideloadableReleases) = await (
      codePushClientWrapper.getReleases(appId: appId),
      codePushClientWrapper.getReleases(appId: appId, sideloadableOnly: true),
    ).wait;

    final maybePlatform = results['platform'] != null
        ? ReleasePlatform.values.byName(results['platform'] as String)
        : null;
    final platformReleases = sideloadableReleases
        .where(
          (r) =>
              maybePlatform == null ||
              r.activePlatforms.contains(maybePlatform),
        )
        .toList();

    if (platformReleases.isEmpty) {
      if (maybePlatform != null) {
        logger.err(
          '''No previewable ${maybePlatform.displayName} releases found''',
        );
      } else {
        logger.err('No previewable releases found for this app');
      }
      return ExitCode.usage.code;
    }

    final releaseVersion =
        results['release-version'] as String? ??
        await promptForReleaseVersion(platformReleases);

    final release = platformReleases.firstWhereOrNull(
      (r) => r.version == releaseVersion,
    );

    if (release == null) {
      logger.err('No previewable releases found for version $releaseVersion');
      return ExitCode.usage.code;
    }

    final availablePlatforms = release.activePlatforms
        .where((p) => supportedReleasePlatforms.contains(p))
        .toList();

    if (availablePlatforms.isEmpty) {
      final activePlatformsString = release.activePlatforms
          .map((p) => p.displayName)
          .join(', ');
      logger.err(
        '''This release can only be previewed on platforms that support $activePlatformsString''',
      );
      return ExitCode.usage.code;
    }

    final releaseWithAllPlatforms = allReleases.firstWhere(
      (r) => r.id == release.id,
    );
    assertPreviewableReleases(
      releaseWithAllPlatforms: releaseWithAllPlatforms,
      release: release,
      targetPlatform: maybePlatform,
    );

    final ReleasePlatform releasePlatform;
    if (maybePlatform != null) {
      final matchedPlatform = release.activePlatforms.firstWhere(
        (p) => p == maybePlatform,
      );

      releasePlatform = matchedPlatform;
    } else if (availablePlatforms.length == 1) {
      releasePlatform = availablePlatforms.first;
    } else {
      releasePlatform = await promptForPlatform(availablePlatforms);
    }

    final deviceId = results['device-id'] as String?;

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
      ReleasePlatform.linux => installAndLaunchLinux(
        appId: appId,
        release: release,
        track: track,
      ),
      ReleasePlatform.macos => installAndLaunchMacos(
        appId: appId,
        release: release,
        track: track,
      ),
      ReleasePlatform.windows => installAndLaunchWindows(
        appId: appId,
        release: release,
        track: track,
      ),
    };
  }

  /// Prompts the user to choose an app to preview.
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

  /// Prompts the user to choose a release version to preview.
  Future<String> promptForReleaseVersion(List<Release> releases) async {
    final release = logger.chooseOne(
      'Which release would you like to preview?',
      choices: releases,
      display: (release) => release.version,
    );
    return release.version;
  }

  /// Prompts the user to choose a platform to preview.
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

  /// Downloads and runs the given [release] the given [appId] on Linux.
  Future<int> installAndLaunchLinux({
    required String appId,
    required Release release,
    required DeploymentTrack track,
  }) async {
    const platform = ReleasePlatform.linux;
    late Directory appDirectory;
    late ReleaseArtifact releaseArtifact;

    try {
      releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
        appId: appId,
        releaseId: release.id,
        arch: 'bundle',
        platform: platform,
      );
    } on Exception catch (e, s) {
      logger
        ..err('Error getting release artifact: $e')
        ..detail('Stack trace: $s');
      return ExitCode.software.code;
    }

    appDirectory = Directory(
      getArtifactPath(
        appId: appId,
        release: release,
        artifact: releaseArtifact,
        platform: platform,
      ),
    );

    if (!appDirectory.existsSync()) {
      try {
        if (!appDirectory.existsSync()) {
          appDirectory.createSync(recursive: true);
        }

        final archiveFile = await artifactManager.downloadWithProgressUpdates(
          Uri.parse(releaseArtifact.url),
          message: 'Downloading ${releaseArtifact.arch}',
        );
        await artifactManager.extractZip(
          zipFile: archiveFile,
          outputDirectory: appDirectory,
        );
      } on Exception catch (error) {
        logger.err('$error');
        return ExitCode.software.code;
      }
    }

    final progress = logger.progress('Using $track track');
    try {
      await setChannelOnLinuxApp(
        channel: track.channel,
        bundleDirectory: appDirectory,
      );
      progress.complete();
    } on Exception catch (error) {
      progress.fail('$error');
      return ExitCode.software.code;
    }

    final executableFile = appDirectory.listSync().whereType<File>().first;

    await process.run('chmod', ['+x', executableFile.path]);

    final proc = await process.start(executableFile.path, []);
    proc.stdout.listen((log) => logger.info(utf8.decode(log)));
    proc.stderr.listen((log) => logger.err(utf8.decode(log)));
    return proc.exitCode;
  }

  /// Downloads and runs the given [release] the given [appId] on Windows.
  Future<int> installAndLaunchWindows({
    required String appId,
    required Release release,
    required DeploymentTrack track,
  }) async {
    const platform = ReleasePlatform.windows;
    late Directory appDirectory;
    late ReleaseArtifact releaseExeArtifact;

    try {
      releaseExeArtifact = await codePushClientWrapper.getReleaseArtifact(
        appId: appId,
        releaseId: release.id,
        arch: primaryWindowsReleaseArtifactArch,
        platform: platform,
      );
    } on Exception catch (e, s) {
      logger
        ..err('Error getting release artifact: $e')
        ..detail('Stack trace: $s');
      return ExitCode.software.code;
    }

    appDirectory = Directory(
      getArtifactPath(
        appId: appId,
        release: release,
        artifact: releaseExeArtifact,
        platform: platform,
        fileExtension: 'exe',
      ),
    );

    if (!appDirectory.existsSync()) {
      try {
        if (!appDirectory.existsSync()) {
          appDirectory.createSync(recursive: true);
        }

        final archiveFile = await artifactManager.downloadWithProgressUpdates(
          Uri.parse(releaseExeArtifact.url),
          message: 'Downloading ${releaseExeArtifact.arch}',
        );
        await artifactManager.extractZip(
          zipFile: archiveFile,
          outputDirectory: appDirectory,
        );
      } on Exception catch (error) {
        logger.err('$error');
        return ExitCode.software.code;
      }
    }

    await setChannelOnWindowsApp(
      appDirectory: appDirectory,
      channel: track.channel,
    );

    final exeFile = appDirectory.listSync().whereType<File>().firstWhere(
      (file) => file.path.endsWith('.exe'),
    );

    final proc = await process.start(exeFile.path, []);
    proc.stdout.listen((log) => logger.info(utf8.decode(log)));
    proc.stderr.listen((log) => logger.err(utf8.decode(log)));
    return proc.exitCode;
  }

  /// Installs and launches the release on macOS.
  Future<int> installAndLaunchMacos({
    required String appId,
    required Release release,
    required DeploymentTrack track,
  }) async {
    const platform = ReleasePlatform.macos;
    late Directory appDirectory;
    late ReleaseArtifact releaseRunnerArtifact;

    try {
      releaseRunnerArtifact = await codePushClientWrapper.getReleaseArtifact(
        appId: appId,
        releaseId: release.id,
        arch: 'app',
        platform: platform,
      );
    } on Exception catch (e, s) {
      logger
        ..err('Error getting release artifact: $e')
        ..detail('Stack trace: $s');
      return ExitCode.software.code;
    }

    appDirectory = Directory(
      getArtifactPath(
        appId: appId,
        release: release,
        artifact: releaseRunnerArtifact,
        platform: platform,
        fileExtension: 'app',
      ),
    );

    if (!appDirectory.existsSync()) {
      try {
        if (!appDirectory.existsSync()) {
          appDirectory.createSync(recursive: true);
        }

        final archiveFile = await artifactManager.downloadWithProgressUpdates(
          Uri.parse(releaseRunnerArtifact.url),
          message: 'Downloading ${releaseRunnerArtifact.arch}',
        );
        await ditto.extract(
          source: archiveFile.path,
          destination: appDirectory.path,
        );
      } on Exception catch (error) {
        logger.err('$error');
        return ExitCode.software.code;
      }
    }

    await setChannelOnMacosApp(
      appDirectory: appDirectory,
      channel: track.channel,
    );

    final logs = await open.newApplication(path: appDirectory.path);
    final completer = Completer<void>();

    // Filter out extra noise from the logs.
    final logFilters = [
      RegExp(r'\[com\.apple.*\]'),
      RegExp(r'\(RunningBoardServices\)'),
      RegExp(r'\(CoreFoundation\)'),
      RegExp(r'\(TCC\)'),
      RegExp(r'\(Metal\)'),
      RegExp('^Timestamp'),
      RegExp('^Filtering the log data'),
    ];

    // Removes the log prefix from the log line.
    // Example log line:
    // ignore: lines_longer_than_80_chars
    // 2025-01-31 09:53:22.889 Df macos_sandbox[22535:1d268] [dev.shorebird:updater::cache::patch_manager] [shorebird] No public key provided, skipping signature verification
    final prefixRegex = RegExp(
      r'^[\d-]+\W+[\d:\.]+\W+\w+\W+\w+\[[\da-f]+:[\da-f]+\]',
    );
    String removeLogPrefix(String line) {
      return line.trim().replaceFirst(prefixRegex, '').trim();
    }

    logs.listen((log) {
      final logLine = utf8.decode(log);
      if (logFilters.any((filter) => filter.hasMatch(logLine))) {
        return;
      }

      logger.info(removeLogPrefix(logLine));
    }, onDone: completer.complete);

    return completer.future.then((_) => ExitCode.success.code);
  }

  /// Installs and launches the release on Android.
  Future<int> installAndLaunchAndroid({
    required String appId,
    required Release release,
    required DeploymentTrack track,
    String? deviceId,
  }) async {
    const platform = ReleasePlatform.android;

    final keystore = results['ks'] as String?;
    final keystorePassword = results['ks-pass'] as String?;
    final keyPassword = results['ks-key-pass'] as String?;
    final keyAlias = results['ks-key-alias'] as String?;

    // Ensure keystore options are valid.
    if (keystore != null) {
      if (keystorePassword == null) {
        logger.err('You must provide a keystore password.');
        return ExitCode.usage.code;
      }
      if (keyAlias == null) {
        logger.err('You must provide a key alias.');
        return ExitCode.usage.code;
      }

      if (!keystorePassword.startsWith('pass:') &&
          !keystorePassword.startsWith('file:')) {
        logger.err('Keystore password must start with "pass:" or "file:".');
        return ExitCode.usage.code;
      }

      if (keyPassword != null &&
          !keyPassword.startsWith('pass:') &&
          !keyPassword.startsWith('file:')) {
        logger.err('Key password must start with "pass:" or "file:".');
        return ExitCode.usage.code;
      }
    }

    late File aabFile;
    late ReleaseArtifact releaseAabArtifact;

    try {
      releaseAabArtifact = await codePushClientWrapper.getReleaseArtifact(
        appId: appId,
        releaseId: release.id,
        arch: 'aab',
        platform: platform,
      );
    } on Exception catch (e, s) {
      logger
        ..err('Error getting release artifact: $e')
        ..detail('Stack trace: $s');
      return ExitCode.software.code;
    }

    try {
      aabFile = File(
        getArtifactPath(
          appId: appId,
          release: release,
          artifact: releaseAabArtifact,
          platform: platform,
          fileExtension: 'aab',
        ),
      );

      if (!aabFile.existsSync()) {
        aabFile.createSync(recursive: true);

        await artifactManager.downloadWithProgressUpdates(
          Uri.parse(releaseAabArtifact.url),
          message: 'Downloading ${releaseAabArtifact.arch}',
          outputPath: aabFile.path,
        );
      }
    } on Exception catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    final apksPath = getArtifactPath(
      appId: appId,
      release: release,
      artifact: releaseAabArtifact,
      platform: platform,
      fileExtension: 'apks',
    );

    if (File(apksPath).existsSync()) File(apksPath).deleteSync();
    final progress = logger.progress('Using $track track');
    try {
      await setChannelOnAab(aabFile: aabFile, channel: track.channel);
      progress.complete();
    } on Exception catch (error) {
      progress.fail('$error');
      return ExitCode.software.code;
    }

    final extractMetadataProgress = logger.progress('Extracting metadata');
    late String package;
    try {
      package = await bundletool.getPackageName(aabFile.path);
      extractMetadataProgress.complete();
    } on Exception catch (error) {
      extractMetadataProgress.fail('$error');
      return ExitCode.software.code;
    }

    final buildApksProgress = logger.progress('Building apks');
    try {
      await bundletool.buildApks(
        bundle: aabFile.path,
        output: apksPath,
        keystore: keystore,
        keystorePassword: keystorePassword,
        keyPassword: keyPassword,
        keyAlias: keyAlias,
      );
      final apksLink = link(uri: Uri.parse(apksPath));
      buildApksProgress.complete('Built apks: ${cyan.wrap(apksLink)}');
    } on Exception catch (error) {
      buildApksProgress.fail('$error');
      return ExitCode.software.code;
    }

    final installApksProgress = logger.progress('Installing apks');
    try {
      await bundletool.installApks(apks: apksPath, deviceId: deviceId);
      installApksProgress.complete();
    } on Exception catch (error) {
      installApksProgress.fail('$error');
      return ExitCode.software.code;
    }

    final startAppProgress = logger.progress('Starting app');
    try {
      await adb.clearAppData(package: package, deviceId: deviceId);
      await adb.startApp(package: package, deviceId: deviceId);
      startAppProgress.complete();
    } on Exception catch (error) {
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

  /// Installs and launches the release on iOS.
  Future<int> installAndLaunchIos({
    required String appId,
    required Release release,
    required DeploymentTrack track,
    String? deviceId,
  }) async {
    await iosDeploy.installIfNeeded();

    const platform = ReleasePlatform.ios;
    late Directory runnerDirectory;
    late ReleaseArtifact releaseRunnerArtifact;

    try {
      releaseRunnerArtifact = await codePushClientWrapper.getReleaseArtifact(
        appId: appId,
        releaseId: release.id,
        arch: 'runner',
        platform: platform,
      );
    } on Exception catch (e, s) {
      logger
        ..err('Error getting release artifact: $e')
        ..detail('Stack trace: $s');
      return ExitCode.software.code;
    }

    runnerDirectory = Directory(
      getArtifactPath(
        appId: appId,
        release: release,
        artifact: releaseRunnerArtifact,
        platform: platform,
        fileExtension: 'app',
      ),
    );

    if (!runnerDirectory.existsSync()) {
      try {
        if (!runnerDirectory.existsSync()) {
          runnerDirectory.createSync(recursive: true);
        }

        final archiveFile = await artifactManager.downloadWithProgressUpdates(
          Uri.parse(releaseRunnerArtifact.url),
          message: 'Downloading ${releaseRunnerArtifact.arch}',
        );
        await artifactManager.extractZip(
          zipFile: archiveFile,
          outputDirectory: runnerDirectory,
        );
      } on Exception catch (error) {
        logger.err('$error');
        return ExitCode.software.code;
      }
    }

    final progress = logger.progress('Using $track track');
    try {
      await setChannelOnRunner(
        runnerDirectory: runnerDirectory,
        channel: track.channel,
      );
      progress.complete();
    } on Exception catch (error) {
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
    } on Exception catch (error, stackTrace) {
      logger.detail('Error launching app. $error $stackTrace');
      return ExitCode.software.code;
    }
  }

  /// Resolves the artifact path for the given parameters.
  String getArtifactPath({
    required String appId,
    required Release release,
    required ReleaseArtifact artifact,
    required ReleasePlatform platform,
    String? fileExtension,
  }) {
    final previewDirectory = cache.getPreviewDirectory(appId);
    final ext = fileExtension != null ? '.$fileExtension' : '';
    return p.join(
      previewDirectory.path,
      '${platform.name}_${release.version}_${artifact.id}$ext',
    );
  }

  /// Sets the channel property in the shorebird.yaml file inside the Windows
  /// app whose root directory is [appDirectory].
  Future<void> setChannelOnWindowsApp({
    required Directory appDirectory,
    required String channel,
  }) async {
    final shorebirdYamlFile = File(
      p.join(appDirectory.path, 'data', 'flutter_assets', 'shorebird.yaml'),
    );

    await _maybeSetChannelInShorebirdYaml(
      channel: channel,
      shorebirdYamlFile: shorebirdYamlFile,
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

      await _maybeSetChannelInShorebirdYaml(
        channel: channel,
        shorebirdYamlFile: shorebirdYaml,
      );
    });
  }

  /// Sets the channel property in the shorebird.yaml file inside a macOS app.
  Future<void> setChannelOnMacosApp({
    required Directory appDirectory,
    required String channel,
  }) async {
    final shorebirdYamlFile = File(
      p.join(
        appDirectory.path,
        'Contents',
        'Frameworks',
        'App.framework',
        'Resources',
        'flutter_assets',
        'shorebird.yaml',
      ),
    );

    await _maybeSetChannelInShorebirdYaml(
      channel: channel,
      shorebirdYamlFile: shorebirdYamlFile,
    );
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

      final didUpdateShorebirdYaml = await _maybeSetChannelInShorebirdYaml(
        channel: channel,
        shorebirdYamlFile: shorebirdYamlFile,
      );

      if (!didUpdateShorebirdYaml) {
        return;
      }

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
      await encoder.close();

      // Replace the existing preview artifact with the updated one.
      tmpAabFile.copySync(aabFile.path);
      tempDir.deleteSync(recursive: true);
    });
  }

  /// Sets the channel property in the shorebird.yaml file if none is set.
  Future<void> setChannelOnLinuxApp({
    required String channel,
    required Directory bundleDirectory,
  }) async {
    final shorebirdYamlFile = File(
      p.join(bundleDirectory.path, 'data', 'flutter_assets', 'shorebird.yaml'),
    );

    await _maybeSetChannelInShorebirdYaml(
      channel: channel,
      shorebirdYamlFile: shorebirdYamlFile,
    );
  }

  /// Sets the channel property in the shorebird.yaml file if none is set or
  /// different from the provided channel.
  static Future<bool> _maybeSetChannelInShorebirdYaml({
    required String channel,
    required File shorebirdYamlFile,
  }) async {
    if (!shorebirdYamlFile.existsSync()) {
      throw Exception('Unable to find shorebird.yaml');
    }

    final yamlText = shorebirdYamlFile.readAsStringSync();
    final yaml = loadYaml(yamlText) as YamlMap;
    final yamlChannel = yaml['channel'];

    if (yamlChannel == null && channel == DeploymentTrack.stable.channel) {
      // We would be updating the channel to the default value.
      return false;
    }

    if (yamlChannel == channel) {
      // Updating this channel would be a no-op.
      return false;
    }

    final yamlEditor = YamlEditor(yamlText)..update(['channel'], channel);
    shorebirdYamlFile.writeAsStringSync(yamlEditor.toString(), flush: true);
    return true;
  }
}

/// Extension on [Release] that exposes the active platforms (e.g. platforms
/// that can be previewed).
extension Previewable on Release {
  /// Returns the platforms that can be previewed.
  List<ReleasePlatform> get activePlatforms => platformStatuses.entries
      .where((e) => e.value == ReleaseStatus.active)
      .map((e) => e.key)
      .toList();
}

/// Given two [Release]s, one with all the platforms, previewable or not,
/// and one with only the previewable platforms, this method will check for
/// platforms that are not previewable.
///
/// If any non-previewable platforms are found, we will:
/// - Warn the user about the platform if that platform is not the one
///    the user specified with `--platform`.
/// - Error out if the user specified a platform that is not previewable.
void assertPreviewableReleases({
  required Release releaseWithAllPlatforms,
  required Release release,
  required ReleasePlatform? targetPlatform,
}) {
  final nonPreviewablePlatforms = releaseWithAllPlatforms.activePlatforms.where(
    (p) => !release.activePlatforms.contains(p),
  );

  for (final platform in nonPreviewablePlatforms) {
    final message =
        '''The ${platform.displayName} artifact for this release is not previewable.''';

    // If the user explicitly specified a platform and it matches a non
    // previewable platform, we early exit to avoid duplicated warnings/errors.
    if (targetPlatform?.name == platform.name) {
      logger.err(message);
      throw ProcessExit(ExitCode.software.code);
      // We only WARN if the user didn't specify a platform.
    } else if (targetPlatform == null) {
      logger.warn(message);
    }
  }
}
