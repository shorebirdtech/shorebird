import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_engine_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template publish_command}
///
/// `shorebird publish <path/to/artifact>`
/// Publish new releases to the Shorebird CodePush server.
/// {@endtemplate}
class PublishCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdEngineMixin, ShorebirdBuildMixin {
  /// {@macro publish_command}
  PublishCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.runProcess,
  });

  @override
  String get description => 'Publish an update.';

  @override
  String get name => 'publish';

  // TODO(felangel): make these configurable.
  static const String _arch = 'aarch64';
  static const String _platform = 'android';
  static const String _channel = 'stable';

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

    final pubspecYaml = getPubspecYaml()!;
    final shorebirdYaml = getShorebirdYaml()!;
    final codePushClient = buildCodePushClient(
      apiKey: session.apiKey,
      hostedUri: hostedUri,
    );
    final version = pubspecYaml.version!;
    final versionString = '${version.major}.${version.minor}.${version.patch}';

    logger.info(
      '''
Ready to publish the following patch:
App: ${pubspecYaml.name} (${shorebirdYaml.appId})
Release Version: $versionString
Patch Number: [NEW]
''',
    );

    final confirm = logger.confirm('Are you sure you want to continue?');

    if (!confirm) {
      logger.info('Aborting.');
      return ExitCode.success.code;
    }

    late final List<Release> releases;
    final fetchReleasesProgress = logger.progress('Fetching releases');
    try {
      releases = await codePushClient.getReleases(
        appId: shorebirdYaml.appId,
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
          appId: shorebirdYaml.appId,
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
        hash: '#',
      );
      createArtifactProgress.complete();
    } catch (error) {
      createArtifactProgress.fail('$error');
      return ExitCode.software.code;
    }

    Channel? channel;
    final fetchChannelsProgress = logger.progress('Fetching channels');
    try {
      final channels = await codePushClient.getChannels(
        appId: shorebirdYaml.appId,
      );
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
          appId: shorebirdYaml.appId,
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

    logger.success('Published!');
    return ExitCode.success.code;
  }
}
