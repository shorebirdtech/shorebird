import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_engine_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Signature for a function which takes a list of bytes and returns a hash.
typedef HashFunction = String Function(List<int> bytes);

/// {@template publish_command}
///
/// `shorebird publish <path/to/artifact>`
/// Publish new releases to the Shorebird CodePush server.
/// {@endtemplate}
class PublishCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdEngineMixin,
        ShorebirdBuildMixin,
        ShorebirdCreateAppMixin {
  /// {@macro publish_command}
  PublishCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.runProcess,
    HashFunction? hashFn,
  }) : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString());

  @override
  String get description => 'Publish an update.';

  @override
  String get name => 'publish';

  // TODO(felangel): make these configurable.
  static const String _arch = 'aarch64';
  static const String _platform = 'android';
  static const String _channel = 'stable';

  final HashFunction _hashFn;

  @override
  Future<int> run() async {
    if (!isShorebirdInitialized) {
      logger.err(
        'Shorebird is not initialized. Did you run "shorebird init"?',
      );
      return ExitCode.config.code;
    }

    final session = auth.currentSession;
    if (session == null) {
      logger.err('You must be logged in to publish.');
      return ExitCode.noUser.code;
    }

    try {
      await ensureEngineExists();
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    final buildProgress = logger.progress('Building release');
    try {
      await buildRelease();
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    final artifactPath = p.join(
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

    final artifact = File(artifactPath);

    if (!artifact.existsSync()) {
      logger.err('Artifact not found: "${artifact.path}"');
      return ExitCode.software.code;
    }

    final hash = _hashFn(await artifact.readAsBytes());
    final pubspecYaml = getPubspecYaml()!;
    final shorebirdYaml = getShorebirdYaml()!;
    final codePushClient = buildCodePushClient(
      apiKey: session.apiKey,
      hostedUri: hostedUri,
    );
    final version = pubspecYaml.version!;
    final versionString = '${version.major}.${version.minor}.${version.patch}';

    late final List<App> apps;
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

    var app = apps.firstWhereOrNull((a) => a.id == shorebirdYaml.appId);
    if (app == null) {
      logger.info(
        lightCyan.wrap("\nIt looks like this is a new app. Let's get started!"),
      );
      try {
        app = await createApp();
        addShorebirdYamlToProject(app.id);
        addShorebirdYamlToPubspecAssets();
        logger.info('''

${lightGreen.wrap('🐦 Shorebird initialized successfully!')}

✅ A shorebird app has been created.
✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.''');
      } catch (error) {
        logger.err('$error');
        return ExitCode.software.code;
      }
    }

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.id})')}
📦 Release Version: ${lightCyan.wrap(versionString)}
#️⃣ Hash: ${lightCyan.wrap(hash)}
''',
    );

    final confirm = logger.confirm('Would you like to continue?');

    if (!confirm) {
      logger.info('Aborting.');
      return ExitCode.success.code;
    }

    late final List<Release> releases;
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

    var release = releases.firstWhereOrNull(
      (r) => r.version == versionString,
    );

    if (release == null) {
      final createReleaseProgress = logger.progress('Creating release');
      try {
        release = await codePushClient.createRelease(
          appId: app.id,
          version: versionString,
        );
        createReleaseProgress.complete();
      } catch (error) {
        createReleaseProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    late final Patch patch;
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
      await codePushClient.createArtifact(
        patchId: patch.id,
        artifactPath: artifact.path,
        arch: _arch,
        platform: _platform,
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
        (channel) => channel.name == _channel,
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
          channel: _channel,
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

    logger.success('\n✅ Published Successfully!');
    return ExitCode.success.code;
  }
}
