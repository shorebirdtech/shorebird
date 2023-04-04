import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_engine_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patch_command}
/// `shorebird patch`
/// Publish new patches for a specific release to the Shorebird CodePush server.
/// {@endtemplate}
class PatchCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdEngineMixin,
        ShorebirdBuildMixin,
        ShorebirdCreateAppMixin {
  /// {@macro patch_command}
  PatchCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.runProcess,
    HashFunction? hashFn,
    http.Client? httpClient,
  })  : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()),
        _httpClient = httpClient ?? http.Client() {
    argParser
      ..addOption(
        'release-version',
        help: 'The version of the release (e.g. "1.0.0").',
      )
      ..addOption(
        'platform',
        help: 'The platform of the release (e.g. "android").',
        allowed: ['android'],
        allowedHelp: {'android': 'The Android platform.'},
        defaultsTo: 'android',
      )
      ..addOption(
        'arch',
        help: 'The architecture of the release (e.g. "aarch64").',
        allowed: ['aarch64'],
        allowedHelp: {'aarch64': 'The 64-bit ARM architecture.'},
        defaultsTo: 'aarch64',
      )
      ..addOption(
        'channel',
        help: 'The channel the patch should be promoted to (e.g. "stable").',
        allowed: ['stable'],
        allowedHelp: {
          'stable': 'The stable channel which is consumed by production apps.'
        },
        defaultsTo: 'stable',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Patch without confirmation if there are no errors.',
        negatable: false,
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Validate but do not upload the patch.',
      );
  }

  @override
  String get description =>
      'Publish new patches for a specific release to Shorebird.';

  @override
  String get name => 'patch';

  final HashFunction _hashFn;
  final http.Client _httpClient;

  @override
  Future<int> run() async {
    if (!isShorebirdInitialized) {
      logger.err(
        'Shorebird is not initialized. Did you run "shorebird init"?',
      );
      return ExitCode.config.code;
    }

    if (!auth.isAuthenticated) {
      logger.err('You must be logged in to publish.');
      return ExitCode.noUser.code;
    }

    try {
      await ensureEngineExists();
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;

    if (force && dryRun) {
      logger.err('Cannot use both --force and --dry-run.');
      return ExitCode.usage.code;
    }

    final buildProgress = logger.progress('Building patch');
    try {
      await buildRelease();
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    final patchArtifactPath = p.join(
      Directory.current.path,
      'build',
      'app',
      'intermediates',
      'stripped_native_libs',
      'release',
      'out',
      'lib',
      'arm64-v8a',
      'libapp.so',
    );

    final patchArtifact = File(patchArtifactPath);

    if (!patchArtifact.existsSync()) {
      logger.err('Artifact not found: "${patchArtifact.path}"');
      return ExitCode.software.code;
    }

    final hash = _hashFn(await patchArtifact.readAsBytes());
    final pubspecYaml = getPubspecYaml()!;
    final shorebirdYaml = getShorebirdYaml()!;
    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );
    final version = pubspecYaml.version!;
    final versionString = '${version.major}.${version.minor}.${version.patch}';

    final List<App> apps;
    final fetchAppsProgress = logger.progress('Fetching apps');
    try {
      apps = (await codePushClient.getApps())
          .map((a) => App(id: a.appId, displayName: a.displayName))
          .toList();
      fetchAppsProgress.complete();
    } catch (error) {
      fetchAppsProgress.fail('$error');
      return ExitCode.software.code;
    }

    final app = apps.firstWhereOrNull((a) => a.id == shorebirdYaml.appId);
    if (app == null) {
      logger.err(
        '''
Could not find app with id: "${shorebirdYaml.appId}".
Did you forget to run "shorebird init"?''',
      );
      return ExitCode.software.code;
    }

    final releaseVersionArg = results['release-version'] as String?;
    final pubspecVersion = pubspecYaml.version!;
    final pubspecVersionString =
        '''${pubspecVersion.major}.${pubspecVersion.minor}.${pubspecVersion.patch}''';

    if (dryRun) {
      logger
        ..info('No issues detected.')
        ..info('The server may enforce additional checks.');
      return ExitCode.success.code;
    }

    if (releaseVersionArg == null) logger.info('');

    final releaseVersion = releaseVersionArg ??
        logger.prompt(
          'Which release is this patch for?',
          defaultValue: pubspecVersionString,
        );
    final arch = results['arch'] as String;
    final platform = results['platform'] as String;
    final channelArg = results['channel'] as String;

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.id})')}
📦 Release Version: ${lightCyan.wrap(releaseVersion)}
⚙️  Architecture: ${lightCyan.wrap(arch)}
🕹️  Platform: ${lightCyan.wrap(platform)}
📺 Channel: ${lightCyan.wrap(channelArg)}
#️⃣  Hash: ${lightCyan.wrap(hash)}
''',
    );

    final needsConfirmation = !force;
    if (needsConfirmation) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        return ExitCode.success.code;
      }
    }

    final List<Release> releases;
    final fetchReleasesProgress = logger.progress('Fetching releases');
    try {
      releases = await codePushClient.getReleases(
        appId: app.id,
      );
      fetchReleasesProgress.complete();
    } catch (error) {
      fetchReleasesProgress.fail('$error');
      return ExitCode.software.code;
    }

    final release = releases.firstWhereOrNull(
      (r) => r.version == versionString,
    );

    if (release == null) {
      logger.err(
        '''
Release not found: "$versionString"

Patches can only be published for existing releases.
Please create a release using "shorebird release" and try again.
''',
      );
      return ExitCode.software.code;
    }

    final ReleaseArtifact releaseArtifact;
    final fetchReleaseArtifactProgress = logger.progress(
      'Fetching release artifact',
    );
    try {
      releaseArtifact = await codePushClient.getReleaseArtifact(
        releaseId: release.id,
        arch: arch,
        platform: platform,
      );
      fetchReleaseArtifactProgress.complete();
    } catch (error) {
      fetchReleaseArtifactProgress.fail('$error');
      return ExitCode.software.code;
    }

    final String releaseArtifactPath;
    final downloadReleaseArtifactProgress = logger.progress(
      'Downloading release artifact',
    );
    try {
      releaseArtifactPath = await _downloadReleaseArtifact(
        Uri.parse(releaseArtifact.url),
      );
      downloadReleaseArtifactProgress.complete();
    } catch (error) {
      downloadReleaseArtifactProgress.fail('$error');
      return ExitCode.software.code;
    }

    final String diffPath;
    final createDiffProgress = logger.progress('Creating diff');
    try {
      diffPath = await _createDiff(
        releaseArtifactPath: releaseArtifactPath,
        patchArtifactPath: patchArtifactPath,
      );
      createDiffProgress.complete();
    } catch (error) {
      createDiffProgress.fail('$error');
      return ExitCode.software.code;
    }

    final Patch patch;
    final createPatchProgress = logger.progress('Creating patch');
    try {
      patch = await codePushClient.createPatch(releaseId: release.id);
      createPatchProgress.complete();
    } catch (error) {
      createPatchProgress.fail('$error');
      return ExitCode.software.code;
    }

    final createArtifactProgress = logger.progress('Creating artifact');
    try {
      await codePushClient.createPatchArtifact(
        patchId: patch.id,
        artifactPath: diffPath,
        arch: arch,
        platform: platform,
        hash: hash,
      );
      createArtifactProgress.complete();
    } catch (error) {
      createArtifactProgress.fail('$error');
      return ExitCode.software.code;
    }

    Channel? channel;
    final fetchChannelsProgress = logger.progress('Fetching channels');
    try {
      final channels = await codePushClient.getChannels(appId: app.id);
      channel = channels.firstWhereOrNull(
        (channel) => channel.name == channelArg,
      );
      fetchChannelsProgress.complete();
    } catch (error) {
      fetchChannelsProgress.fail('$error');
      return ExitCode.software.code;
    }

    if (channel == null) {
      final createChannelProgress = logger.progress('Creating channel');
      try {
        channel = await codePushClient.createChannel(
          appId: app.id,
          channel: channelArg,
        );
        createChannelProgress.complete();
      } catch (error) {
        createChannelProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final publishPatchProgress = logger.progress('Publishing patch');
    try {
      await codePushClient.promotePatch(
        patchId: patch.id,
        channelId: channel.id,
      );
      publishPatchProgress.complete();
    } catch (error) {
      publishPatchProgress.fail('$error');
      return ExitCode.software.code;
    }

    logger.success('\n✅ Published Patch!');
    return ExitCode.success.code;
  }

  Future<String> _downloadReleaseArtifact(Uri uri) async {
    final request = http.Request('GET', uri);
    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        '''Failed to download release artifact: ${response.statusCode} ${response.reasonPhrase}''',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp();
    final releaseArtifact = File(p.join(tempDir.path, 'artifact.so'));
    await releaseArtifact.openWrite().addStream(response.stream);

    return releaseArtifact.path;
  }

  Future<String> _createDiff({
    required String releaseArtifactPath,
    required String patchArtifactPath,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp();
    final diffPath = p.join(tempDir.path, 'diff.patch');

    final diffExecutable = p.join(shorebirdEnginePath, 'patch');
    final diffArguments = [
      releaseArtifactPath,
      patchArtifactPath,
      diffPath,
    ];

    final result = await runProcess(
      diffExecutable,
      diffArguments,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to create diff: ${result.stderr}');
    }

    return diffPath;
  }
}
