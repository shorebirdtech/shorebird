// cspell:words devicectl endtemplate bryanoltman sideloadable previewable apks
// cspell:words bundletool
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_chooser.dart';
import 'package:shorebird_cli/src/release_type.dart';
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
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(CommonArguments.flavorArg.name, help: appScopedFlavorHelp)
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
  static List<ReleasePlatform> get supportedReleasePlatforms =>
      ReleasePlatform.values.where(_isPreviewableHere).toList();

  /// Whether a release built for [releasePlatform] can be launched from the
  /// machine running this command.
  ///
  /// A desktop preview runs the release's own executable, so only its own OS
  /// can launch it -- this used to exclude iOS alone, which left macOS in the
  /// list on Windows and Linux and let `--platform macos` past the guard
  /// there. Android is the exception: `adb` talks to the device from any host.
  static bool _isPreviewableHere(ReleasePlatform releasePlatform) =>
      switch (releasePlatform) {
        ReleasePlatform.android => true,
        ReleasePlatform.ios || ReleasePlatform.macos => platform.isMacOS,
        ReleasePlatform.linux => platform.isLinux,
        ReleasePlatform.windows => platform.isWindows,
      };

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
      return reportPreconditionFailure(error);
    }

    _assertArgsAreValid();

    final (:appId, :errorCode) = await _resolveAppId();
    if (errorCode != null) return errorCode;
    if (appId == null) {
      logger.info('No apps found');
      return ExitCode.success.code;
    }

    final requestedPlatform = _requestedPlatform;
    final resolved = await _resolveRelease(
      appId: appId,
      requestedPlatform: requestedPlatform,
    );
    if (resolved == null) return ExitCode.usage.code;

    final releasePlatform = _resolvePlatform(
      release: resolved.release,
      allReleases: resolved.allReleases,
      requestedPlatform: requestedPlatform,
    );
    if (releasePlatform == null) return ExitCode.usage.code;

    return _installAndLaunch(
      appId: appId,
      release: resolved.release,
      releasePlatform: releasePlatform,
    );
  }

  /// The platform passed with `--platform`, if any.
  ReleasePlatform? get _requestedPlatform {
    final platformName = results['platform'] as String?;
    return platformName != null
        ? ReleasePlatform.values.byName(platformName)
        : null;
  }

  /// Rejects invalid argument combinations before anything is fetched.
  void _assertArgsAreValid() {
    if (results.wasParsed('staging')) {
      usageException(
        'The --staging flag has been removed. Use --track=staging instead.',
      );
    }
    _assertKeystoreArgsAreValid();
  }

  /// Validates the Android signing options (`--ks` and friends).
  void _assertKeystoreArgsAreValid() {
    final keystore = results['ks'] as String?;
    if (keystore == null) return;

    final keystorePassword = results['ks-pass'] as String?;
    final keyPassword = results['ks-key-pass'] as String?;
    final keyAlias = results['ks-key-alias'] as String?;

    if (keystorePassword == null) {
      usageException(
        '--ks requires --ks-pass (e.g. --ks-pass=pass:<password> or '
        '--ks-pass=file:<path>).',
      );
    }
    if (keyAlias == null) {
      usageException('--ks requires --ks-key-alias=<alias>.');
    }

    if (!keystorePassword.startsWith('pass:') &&
        !keystorePassword.startsWith('file:')) {
      usageException(
        '--ks-pass must start with "pass:" or "file:" '
        '(e.g. --ks-pass=pass:<password> or --ks-pass=file:<path>).',
      );
    }

    if (keyPassword != null &&
        !keyPassword.startsWith('pass:') &&
        !keyPassword.startsWith('file:')) {
      usageException(
        '--ks-key-pass must start with "pass:" or "file:" '
        '(e.g. --ks-key-pass=pass:<password> or --ks-key-pass=file:<path>).',
      );
    }
  }

  /// Determines which app to preview from `--app-id`, `--flavor` and
  /// shorebird.yaml, or a prompt.
  ///
  /// Returns a null `appId` if the user has no apps, and a non-null
  /// `errorCode` if `--flavor` can't be used.
  Future<({String? appId, int? errorCode})> _resolveAppId() async {
    final explicitAppId = results[CommonArguments.appIdArg.name] as String?;
    if (explicitAppId != null) return (appId: explicitAppId, errorCode: null);

    final flavor = results[CommonArguments.flavorArg.name] as String?;
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml();
    if (shorebirdYaml == null) {
      if (flavor != null) {
        return (
          appId: null,
          errorCode: reportError(
            message:
                '--flavor needs a shorebird.yaml to read the app ID from. '
                'Run this from your Shorebird project, or pass --app-id '
                'instead.',
          ),
        );
      }
      return (appId: await promptForApp(), errorCode: null);
    }

    final flavorError = shorebirdYaml.unknownFlavorError(flavor);
    if (flavorError != null) {
      return (appId: null, errorCode: reportError(message: flavorError));
    }
    if (flavor != null) {
      return (appId: shorebirdYaml.getAppId(flavor: flavor), errorCode: null);
    }

    final flavors = shorebirdYaml.flavors;
    if (flavors == null) return (appId: shorebirdYaml.appId, errorCode: null);

    final chosenFlavor = logger.chooseOne<String>(
      'Which app flavor?',
      choices: flavors.keys.toList(),
      hint:
          'Pass --flavor=<flavor> to preview a specific flavor without '
          'prompting.',
    );
    return (appId: flavors[chosenFlavor], errorCode: null);
  }

  /// Chooses the release of [appId] to preview, from `--release-version` or a
  /// prompt, limited to releases previewable on [requestedPlatform] if one
  /// was passed.
  ///
  /// Also returns every release of [appId], including platforms that cannot
  /// be previewed, for [_resolvePlatform]. Logs why and returns null when no
  /// previewable release matches the arguments.
  Future<({Release release, List<Release> allReleases})?> _resolveRelease({
    required String appId,
    required ReleasePlatform? requestedPlatform,
  }) async {
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

    final platformReleases = sideloadableReleases
        .where(
          (r) =>
              requestedPlatform == null ||
              r.activePlatforms.contains(requestedPlatform),
        )
        .toList();

    if (platformReleases.isEmpty) {
      if (requestedPlatform != null) {
        logger.err(
          '''No previewable ${requestedPlatform.displayName} releases found for app $appId.''',
        );
        if (sideloadableReleases.isNotEmpty) {
          final otherPlatforms = sideloadableReleases
              .expand((r) => r.activePlatforms)
              .toSet()
              .map((p) => p.name)
              .join(', ');
          logger.info(
            '''Previewable releases exist for: $otherPlatforms. Pass --platform=<one of those> or omit --platform to choose interactively.''',
          );
        } else {
          logger.info(
            '''Create one with ${lightCyan.wrap('shorebird release ${requestedPlatform.name}')}.''',
          );
        }
      } else {
        logger
          ..err('No previewable releases found for app $appId.')
          ..info(
            '''Create one with ${lightCyan.wrap('shorebird release <platform>')}, or pass --app-id=<app-id> to preview a different app.''',
          );
      }
      return null;
    }

    final releaseVersion =
        results['release-version'] as String? ??
        promptForReleaseVersion(platformReleases);

    final release = platformReleases.firstWhereOrNull(
      (r) => r.version == releaseVersion,
    );

    if (release == null) {
      final versions = platformReleases.map((r) => r.version).join(', ');
      logger
        ..err('No previewable release found for version $releaseVersion.')
        ..info(
          '''Previewable versions: $versions. Pass one with --release-version=<version> or omit it to choose interactively.''',
        );
      return null;
    }

    return (release: release, allReleases: allReleases);
  }

  /// Chooses the platform of [release] to preview: [requestedPlatform] if one
  /// was passed, the only previewable platform, or a prompt.
  ///
  /// Logs why and returns null when none of the release's platforms can be
  /// previewed from this machine.
  ReleasePlatform? _resolvePlatform({
    required Release release,
    required List<Release> allReleases,
    required ReleasePlatform? requestedPlatform,
  }) {
    final availablePlatforms = release.activePlatforms
        .where((p) => supportedReleasePlatforms.contains(p))
        .toList();

    if (availablePlatforms.isEmpty) {
      final activePlatformsString = release.activePlatforms
          .map((p) => p.displayName)
          .join(', ');
      final supportedString = supportedReleasePlatforms
          .map((p) => p.displayName)
          .join(', ');
      logger
        ..err(
          '''Release ${release.version} only has $activePlatformsString artifacts, which cannot be previewed from ${platform.operatingSystem}.''',
        )
        ..info(
          '''Platforms previewable from this machine: $supportedString. iOS releases can only be previewed from macOS.''',
        );
      return null;
    }

    final releaseWithAllPlatforms = allReleases.firstWhere(
      (r) => r.id == release.id,
    );
    assertPreviewableReleases(
      releaseWithAllPlatforms: releaseWithAllPlatforms,
      release: release,
      targetPlatform: requestedPlatform,
    );

    // A --platform was already checked against the release's active
    // platforms when choosing the release in _resolveRelease.
    if (requestedPlatform != null) return requestedPlatform;
    if (availablePlatforms.length == 1) return availablePlatforms.first;
    return promptForPlatform(availablePlatforms);
  }

  /// Installs and launches [release] of [appId] on [releasePlatform].
  Future<int> _installAndLaunch({
    required String appId,
    required Release release,
    required ReleasePlatform releasePlatform,
  }) {
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
      hint:
          'Pass --app-id=<app-id> to preview a specific app without '
          'prompting.',
    );
    return app.appId;
  }

  /// Prompts the user to choose a release version to preview.
  String promptForReleaseVersion(List<Release> releases) {
    final release = chooseRelease(
      releases: releases,
      action: 'preview',
    );
    return release.version;
  }

  /// Prompts the user to choose a platform to preview.
  ReleasePlatform promptForPlatform(List<ReleasePlatform> platforms) {
    final platformNames = platforms.map((p) => p.displayName).toList();
    final platform = logger.chooseOne(
      'Which platform would you like to preview?',
      choices: platformNames,
      hint:
          'Pass --platform=<android|ios|...> to preview a specific platform '
          'without prompting.',
    );
    return ReleasePlatform.values.firstWhere((p) => p.displayName == platform);
  }

  /// Downloads and runs the given [release] the given [appId] on Linux.
  // TODO(eseidel): Unlike mobile, desktop preview doesn't clear app state
  // or previously downloaded patches. Consider clearing state to match
  // the mobile behavior.
  Future<int> installAndLaunchLinux({
    required String appId,
    required Release release,
    required DeploymentTrack track,
  }) async {
    const platform = ReleasePlatform.linux;
    final appDirectory = await _downloadReleaseApp(
      appId: appId,
      release: release,
      platform: platform,
      arch: ReleaseType.linux.primaryArtifactArch,
    );

    if (!await _useTrackOnApp(
      platform: platform,
      appDirectory: appDirectory,
      track: track,
    )) {
      return ExitCode.software.code;
    }

    final executableFile = appDirectory.listSync().whereType<File>().first;

    await process.run('chmod', ['+x', executableFile.path]);

    return startAndForwardOutput(executableFile.path);
  }

  /// Downloads and runs the given [release] the given [appId] on Windows.
  // TODO(eseidel): Unlike mobile, desktop preview doesn't clear app state
  // or previously downloaded patches. Consider clearing state to match
  // the mobile behavior.
  Future<int> installAndLaunchWindows({
    required String appId,
    required Release release,
    required DeploymentTrack track,
  }) async {
    const platform = ReleasePlatform.windows;
    final appDirectory = await _downloadReleaseApp(
      appId: appId,
      release: release,
      platform: platform,
      arch: ReleaseType.windows.primaryArtifactArch,
      fileExtension: 'exe',
    );

    if (!await _useTrackOnApp(
      platform: platform,
      appDirectory: appDirectory,
      track: track,
    )) {
      return ExitCode.software.code;
    }

    final exeFile = windows.findExecutable(
      releaseDirectory: appDirectory,
    );

    return startAndForwardOutput(exeFile.path);
  }

  /// Installs and launches the release on macOS.
  // TODO(eseidel): Unlike mobile, desktop preview doesn't clear app state
  // or previously downloaded patches. Consider clearing state to match
  // the mobile behavior.
  Future<int> installAndLaunchMacos({
    required String appId,
    required Release release,
    required DeploymentTrack track,
  }) async {
    const platform = ReleasePlatform.macos;
    final appDirectory = await _downloadReleaseApp(
      appId: appId,
      release: release,
      platform: platform,
      arch: ReleaseType.macos.primaryArtifactArch,
      fileExtension: 'app',
      extract: (archive, outputDirectory) => ditto.extract(
        source: archive.path,
        destination: outputDirectory.path,
      ),
    );

    if (!await _useTrackOnApp(
      platform: platform,
      appDirectory: appDirectory,
      track: track,
    )) {
      return ExitCode.software.code;
    }

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

    // TODO(eseidel): Use startAndForwardOutput instead?
    // This doesn't seem to handle stderr, maybe it should?
    // Use allowMalformed to handle non-UTF8 bytes in log stream output.
    const decoder = Utf8Decoder(allowMalformed: true);
    logs.listen((log) {
      final logLine = decoder.convert(log);
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

    // getReleaseArtifact reports its own failure and throws ProcessExit.
    final releaseAabArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: ReleaseType.android.primaryArtifactArch,
      platform: platform,
    );

    final aabFile = File(
      getArtifactPath(
        appId: appId,
        release: release,
        artifact: releaseAabArtifact,
        platform: platform,
        fileExtension: 'aab',
      ),
    );

    if (!aabFile.existsSync()) {
      try {
        aabFile.createSync(recursive: true);
        await artifactManager.downloadWithProgressUpdates(
          Uri.parse(releaseAabArtifact.url),
          message: 'Downloading ${releaseAabArtifact.arch}',
          outputPath: aabFile.path,
        );
      } on Exception catch (error) {
        // Remove the partial file so the next run does not treat it as cached.
        if (aabFile.existsSync()) aabFile.deleteSync();
        reportDownloadFailure(releaseAabArtifact, error);
      }
    }

    final apksPath = getArtifactPath(
      appId: appId,
      release: release,
      artifact: releaseAabArtifact,
      platform: platform,
      fileExtension: 'apks',
    );

    if (File(apksPath).existsSync()) File(apksPath).deleteSync();
    if (!await _useTrack(
      track,
      () => setChannelOnAab(aabFile: aabFile, channel: track.channel),
    )) {
      return ExitCode.software.code;
    }

    late String package;
    if (!await _runStep('Extracting metadata', () async {
      package = await bundletool.getPackageName(aabFile.path);
    })) {
      return ExitCode.software.code;
    }

    final apksLink = link(uri: Uri.parse(apksPath));
    if (!await _runStep(
      'Building apks',
      () => bundletool.buildApks(
        bundle: aabFile.path,
        output: apksPath,
        keystore: keystore,
        keystorePassword: keystorePassword,
        keyPassword: keyPassword,
        keyAlias: keyAlias,
      ),
      completeMessage: 'Built apks: ${cyan.wrap(apksLink)}',
    )) {
      return ExitCode.software.code;
    }

    logger.info(
      'This will reinstall the app and clear its data on the device.',
    );
    if (!await _runStep(
      'Installing apks',
      () => bundletool.installApks(apks: apksPath, deviceId: deviceId),
    )) {
      return ExitCode.software.code;
    }

    if (!await _runStep('Starting app', () async {
      await adb.clearAppData(package: package, deviceId: deviceId);
      await adb.startApp(package: package, deviceId: deviceId);
    })) {
      return ExitCode.software.code;
    }

    final process = await adb.logcat(filter: 'flutter', deviceId: deviceId);
    // adb logcat sometimes lets non-utf8 characters through, so we need to
    // not crash when it does.
    const decoder = Utf8Decoder(allowMalformed: true);
    process.stdout.listen((event) {
      logger.info(decoder.convert(event));
    });
    process.stderr.listen((event) {
      logger.err(decoder.convert(event));
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
    final runnerDirectory = await _downloadReleaseApp(
      appId: appId,
      release: release,
      platform: platform,
      arch: 'runner',
      fileExtension: 'app',
    );

    if (!await _useTrackOnApp(
      platform: platform,
      appDirectory: runnerDirectory,
      track: track,
    )) {
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

      // Before falling back to ios-deploy, check if devicectl knows about a
      // matching iOS 17+ device that is paired but currently unreachable
      // (locked, screen off, or off the local network when wireless debugging
      // is in use). ios-deploy does not work with iOS 17 or later, so the
      // fallback would just produce an opaque failure. Surface a hint
      // instead.
      if (!shouldUseDeviceCtl) {
        final unreachable = await _findUnreachableIos17OrLaterDevice(
          deviceId: deviceId,
        );
        if (unreachable != null) {
          deviceLocateProgress.fail(
            '${unreachable.name} (iOS '
            '${unreachable.osVersionString ?? 'unknown'}) is paired but '
            'currently unreachable.',
          );
          logger.info(
            '''
This usually means the device is locked, or that wireless debugging dropped because the screen turned off.

To preview on this device:
  • Connect it via USB, or
  • Unlock the device and make sure it is on the same Wi-Fi network as this Mac.

Skipping the ios-deploy fallback because it does not support iOS 17 or later.''',
          );
          return ExitCode.software.code;
        }
      }

      final progressCompleteMessage = deviceForLaunch != null
          ? 'Using device ${deviceForLaunch.name}'
          : '''No iOS 17+ device found, looking for devices running iOS 16 or lower''';
      deviceLocateProgress.complete(progressCompleteMessage);

      logger.info(
        'This will reinstall the app and clear its data on the device.',
      );
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

  /// Returns a paired iOS 17+ device that devicectl knows about but cannot
  /// currently reach (e.g. locked, screen off, off Wi-Fi while wireless
  /// debugging), or `null` if no such device exists. When [deviceId] is
  /// provided, only a device with that UDID is considered.
  ///
  /// If devicectl can't be queried for any reason, returns `null` so the
  /// caller can fall through to its existing behavior rather than surface a
  /// hint based on partial information.
  Future<AppleDevice?> _findUnreachableIos17OrLaterDevice({
    String? deviceId,
  }) async {
    final List<AppleDevice> all;
    try {
      all = await devicectl.listAllIosDevices();
    } on Exception catch (error, stackTrace) {
      logger.detail('listAllIosDevices failed: $error $stackTrace');
      return null;
    }

    final unreachableModern = all.where((device) {
      if (device.isAvailable) return false;
      final version = device.osVersion;
      return version != null && version.major >= 17;
    });

    if (deviceId != null) {
      return unreachableModern.firstWhereOrNull((d) => d.udid == deviceId);
    }
    return unreachableModern.firstOrNull;
  }

  /// Resolves the artifact path for the given parameters, and records the
  /// artifact as used so [Cache.pruneUnusedPreviews] keeps it. Every preview
  /// reaches its cached artifact through this path.
  String getArtifactPath({
    required String appId,
    required Release release,
    required ReleaseArtifact artifact,
    required ReleasePlatform platform,
    String? fileExtension,
  }) {
    final previewDirectory = cache.getPreviewDirectory(appId);
    final ext = fileExtension != null ? '.$fileExtension' : '';
    final path = p.join(
      previewDirectory.path,
      '${platform.name}_${release.version}_${artifact.id}$ext',
    );
    cache.markPreviewUsed(path);
    return path;
  }

  /// Downloads the app artifact [arch] of [release] for [platform] into the
  /// preview cache, unless it is already there, and returns its directory.
  ///
  /// Throws [ProcessExit] if the artifact can't be fetched or downloaded.
  Future<Directory> _downloadReleaseApp({
    required String appId,
    required Release release,
    required ReleasePlatform platform,
    required String arch,
    String? fileExtension,
    Future<void> Function(File archive, Directory outputDirectory)? extract,
  }) async {
    // getReleaseArtifact reports its own failure and throws ProcessExit.
    final artifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: arch,
      platform: platform,
    );

    final appDirectory = Directory(
      getArtifactPath(
        appId: appId,
        release: release,
        artifact: artifact,
        platform: platform,
        fileExtension: fileExtension,
      ),
    );

    await downloadAndExtractIfNeeded(
      artifact: artifact,
      outputDirectory: appDirectory,
      extract: extract,
    );
    return appDirectory;
  }

  /// Runs [body] under a progress labeled [message], completing it with
  /// [completeMessage] on success. On an exception, fails the progress with
  /// the error and returns false.
  Future<bool> _runStep(
    String message,
    Future<void> Function() body, {
    String? completeMessage,
  }) async {
    final progress = logger.progress(message);
    try {
      await body();
      progress.complete(completeMessage);
      return true;
    } on Exception catch (error) {
      progress.fail('$error');
      return false;
    }
  }

  /// Points the app at [track]'s channel via [setChannel], under a
  /// "Using <track> track" progress. Every platform goes through here so they
  /// report the track, and fail, the same way.
  Future<bool> _useTrack(
    DeploymentTrack track,
    Future<void> Function() setChannel,
  ) => _runStep('Using $track track', setChannel);

  /// [_useTrack] for an extracted [platform] app, see [setChannelOnApp].
  Future<bool> _useTrackOnApp({
    required ReleasePlatform platform,
    required Directory appDirectory,
    required DeploymentTrack track,
  }) => _useTrack(
    track,
    () => setChannelOnApp(
      platform: platform,
      appDirectory: appDirectory,
      channel: track.channel,
    ),
  );

  /// The path of shorebird.yaml inside an extracted app, relative to the
  /// app's root directory. Android is not listed: its shorebird.yaml lives
  /// inside the .aab, see [setChannelOnAab].
  static const _shorebirdYamlPaths = <ReleasePlatform, List<String>>{
    ReleasePlatform.linux: ['data', 'flutter_assets', 'shorebird.yaml'],
    ReleasePlatform.windows: ['data', 'flutter_assets', 'shorebird.yaml'],
    ReleasePlatform.ios: [
      'Frameworks',
      'App.framework',
      'flutter_assets',
      'shorebird.yaml',
    ],
    ReleasePlatform.macos: [
      'Contents',
      'Frameworks',
      'App.framework',
      'Resources',
      'flutter_assets',
      'shorebird.yaml',
    ],
  };

  /// Sets the channel property in the shorebird.yaml file inside the
  /// extracted [platform] app whose root directory is [appDirectory].
  Future<void> setChannelOnApp({
    required ReleasePlatform platform,
    required Directory appDirectory,
    required String channel,
  }) async {
    await _maybeSetChannelInShorebirdYaml(
      channel: channel,
      shorebirdYamlFile: File(
        p.joinAll([appDirectory.path, ..._shorebirdYamlPaths[platform]!]),
      ),
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

  /// Downloads the zipped [artifact] and extracts it into [outputDirectory]
  /// (with [extract], defaulting to [ArtifactManager.extractZip]) unless the
  /// directory already exists.
  ///
  /// Removes [outputDirectory] if the download or extraction fails so the
  /// next run does not treat the partial download as a cached artifact.
  /// Throws [ProcessExit] on failure.
  @visibleForTesting
  Future<void> downloadAndExtractIfNeeded({
    required ReleaseArtifact artifact,
    required Directory outputDirectory,
    Future<void> Function(File archive, Directory outputDirectory)? extract,
  }) async {
    if (outputDirectory.existsSync()) return;
    try {
      outputDirectory.createSync(recursive: true);
      final archiveFile = await artifactManager.downloadWithProgressUpdates(
        Uri.parse(artifact.url),
        message: 'Downloading ${artifact.arch}',
      );
      if (extract != null) {
        await extract(archiveFile, outputDirectory);
      } else {
        await artifactManager.extractZip(
          zipFile: archiveFile,
          outputDirectory: outputDirectory,
        );
      }
    } on Exception catch (error) {
      if (outputDirectory.existsSync()) {
        outputDirectory.deleteSync(recursive: true);
      }
      reportDownloadFailure(artifact, error);
    }
  }

  /// Logs a failed download of [artifact] and throws [ProcessExit].
  Never reportDownloadFailure(ReleaseArtifact artifact, Object error) {
    logger
      ..err('Failed to download the ${artifact.arch} artifact: $error')
      ..info('Re-run the command to try the download again.');
    throw ProcessExit(ExitCode.software.code);
  }

  /// Starts a process and forwards its stdout/stderr to the logger.
  ///
  /// Returns the process exit code.
  Future<int> startAndForwardOutput(String executable) async {
    final proc = await process.start(executable, []);
    // Use allowMalformed to handle non-UTF8 bytes in process output.
    const decoder = Utf8Decoder(allowMalformed: true);
    proc.stdout.listen((log) => logger.info(decoder.convert(log)));
    proc.stderr.listen((log) => logger.err(decoder.convert(log)));
    return proc.exitCode;
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
      logger
        ..err(message)
        ..info(
          '''iOS releases built with --no-codesign and add-to-app releases (aar, ios-framework) cannot be previewed. Create a new release with ${lightCyan.wrap('shorebird release ${platform.name}')}, or pick another with --release-version.''',
        );
      throw ProcessExit(ExitCode.software.code);
      // We only WARN if the user didn't specify a platform.
    } else if (targetPlatform == null) {
      logger.warn(message);
    }
  }
}
