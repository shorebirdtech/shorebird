import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/flutter_validation_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Metadata about a patch artifact that we are about to upload.
class PatchArtifactBundle {
  const PatchArtifactBundle({
    required this.arch,
    required this.path,
    required this.hash,
  });

  /// The corresponding architecture.
  final String arch;

  /// The path to the artifact.
  final String path;

  /// The artifact hash.
  final String hash;
}

/// {@template patch_command}
/// `shorebird patch`
/// Publish new patches for a specific release to the Shorebird CodePush server.
/// {@endtemplate}
class PatchCommand extends ShorebirdCommand
    with
        ShorebirdValidationMixin,
        ShorebirdConfigMixin,
        ShorebirdBuildMixin,
        ShorebirdCreateAppMixin {
  /// {@macro patch_command}
  PatchCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.cache,
    super.validators,
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

    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;

    if (force && dryRun) {
      logger.err('Cannot use both --force and --dry-run.');
      return ExitCode.usage.code;
    }

    await logValidationIssues();

    await cache.updateAll();

    final buildProgress = logger.progress('Building patch');
    try {
      await buildAppBundle();
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

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
    final platform = results['platform'] as String;
    final channelArg = results['channel'] as String;

    final List<Release> releases;
    final fetchReleaseProgress = logger.progress('Fetching release');
    try {
      releases = await codePushClient.getReleases(appId: app.id);
      fetchReleaseProgress.complete();
    } catch (error) {
      fetchReleaseProgress.fail('$error');
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

    final releaseArtifacts = <Arch, ReleaseArtifact>{};
    final fetchReleaseArtifactProgress = logger.progress(
      'Fetching release artifacts',
    );
    for (final entry in architectures.entries) {
      try {
        final releaseArtifact = await codePushClient.getReleaseArtifact(
          releaseId: release.id,
          arch: entry.value.arch,
          platform: platform,
        );
        releaseArtifacts[entry.key] = releaseArtifact;
      } catch (error) {
        fetchReleaseArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }
    fetchReleaseArtifactProgress.complete();

    final releaseArtifactPaths = <Arch, String>{};
    final downloadReleaseArtifactProgress = logger.progress(
      'Downloading release artifacts',
    );
    for (final releaseArtifact in releaseArtifacts.entries) {
      try {
        final releaseArtifactPath = await _downloadReleaseArtifact(
          Uri.parse(releaseArtifact.value.url),
        );
        releaseArtifactPaths[releaseArtifact.key] = releaseArtifactPath;
      } catch (error) {
        downloadReleaseArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }
    downloadReleaseArtifactProgress.complete();

    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};
    final createDiffProgress = logger.progress('Creating artifacts');

    for (final releaseArtifactPath in releaseArtifactPaths.entries) {
      final archMetadata = architectures[releaseArtifactPath.key]!;
      final patchArtifactPath = p.join(
        Directory.current.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        archMetadata.path,
        'libapp.so',
      );
      final patchArtifact = File(patchArtifactPath);
      final hash = _hashFn(await patchArtifact.readAsBytes());
      try {
        final diffPath = await _createDiff(
          releaseArtifactPath: releaseArtifactPath.value,
          patchArtifactPath: patchArtifactPath,
        );
        patchArtifactBundles[releaseArtifactPath.key] = PatchArtifactBundle(
          arch: archMetadata.arch,
          path: diffPath,
          hash: hash,
        );
      } catch (error) {
        createDiffProgress.fail('$error');
        return ExitCode.software.code;
      }
    }
    createDiffProgress.complete();

    final archNames = patchArtifactBundles.keys.map((arch) => arch.name);

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.id})')}
📦 Release Version: ${lightCyan.wrap(releaseVersion)}
📺 Channel: ${lightCyan.wrap(channelArg)}
🕹️  Platform: ${lightCyan.wrap(platform)} ${lightCyan.wrap('(${archNames.join(', ')})')}
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

    final Patch patch;
    final createPatchProgress = logger.progress('Creating patch');
    try {
      patch = await codePushClient.createPatch(releaseId: release.id);
      createPatchProgress.complete();
    } catch (error) {
      createPatchProgress.fail('$error');
      return ExitCode.software.code;
    }

    final createArtifactProgress = logger.progress('Uploading artifacts');
    for (final artifact in patchArtifactBundles.values) {
      try {
        await codePushClient.createPatchArtifact(
          patchId: patch.id,
          artifactPath: artifact.path,
          arch: artifact.arch,
          platform: platform,
          hash: artifact.hash,
        );
      } catch (error) {
        createArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }
    createArtifactProgress.complete();

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

    final publishPatchProgress = logger.progress(
      'Promoting patch to ${channel.name}',
    );
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
    final diffExecutable = p.join(
      cache.getArtifactDirectory('patch').path,
      'patch',
    );
    final diffArguments = [
      releaseArtifactPath,
      patchArtifactPath,
      diffPath,
    ];

    final result = await process.run(
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
