import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template unreachable_exception}
/// Exception thrown when a code path is unreachable.
/// {@endtemplate}
class UnreachableException implements Exception {
  /// {@macro unreachable_exception}
  const UnreachableException();
}

/// {@template patch_artifact_bundle}
/// Metadata about a patch artifact that we are about to upload.
/// {@endtemplate}
class PatchArtifactBundle {
  /// {@macro patch_artifact_bundle}
  const PatchArtifactBundle({
    required this.arch,
    required this.path,
    required this.hash,
    required this.size,
  });

  /// The corresponding architecture.
  final String arch;

  /// The path to the artifact.
  final String path;

  /// The artifact hash.
  final String hash;

  /// The size in bytes of the artifact.
  final int size;
}

/// {@template code_push_client_wrapper}
/// Wraps [CodePushClient] interaction with logging and error handling to
/// reduce the amount of command and command test code.
/// {@endtemplate}
class CodePushClientWrapper {
  /// {@macro code_push_client_wrapper}
  CodePushClientWrapper({
    required this.codePushClient,
    required this.logger,
  });

  final CodePushClient codePushClient;
  final Logger logger;

  Future<AppMetadata> getApp({required String appId}) async {
    final app = await maybeGetApp(appId: appId);
    if (app == null) {
      logger.err(
        '''
Could not find app with id: "$appId".
Did you forget to run "shorebird init"?''',
      );
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }

    return app;
  }

  Future<AppMetadata?> maybeGetApp({required String appId}) async {
    final fetchAppsProgress = logger.progress('Fetching apps');
    try {
      final apps = (await codePushClient.getApps())
          // .map((a) => App(id: a.appId, displayName: a.displayName))
          .toList();
      fetchAppsProgress.complete();
      return apps.firstWhereOrNull((a) => a.appId == appId);
    } catch (error) {
      fetchAppsProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }
  }

  Future<Channel?> maybeGetChannel({
    required String appId,
    required String name,
  }) async {
    final fetchChannelsProgress = logger.progress('Fetching channels');
    try {
      final channels = await codePushClient.getChannels(appId: appId);
      final channel = channels.firstWhereOrNull(
        (channel) => channel.name == name,
      );
      fetchChannelsProgress.complete();
      return channel;
    } catch (error) {
      fetchChannelsProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }
  }

  Future<Channel> createChannel({
    required String appId,
    required String name,
  }) async {
    final createChannelProgress = logger.progress('Creating channel');
    try {
      final channel = await codePushClient.createChannel(
        appId: appId,
        channel: name,
      );
      createChannelProgress.complete();
      return channel;
    } catch (error) {
      createChannelProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }
  }

  Future<Release> getRelease({
    required String appId,
    required String releaseVersion,
  }) async {
    final release = await maybeGetRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    if (release == null) {
      logger.err(
        '''
Release not found: "$releaseVersion"

Patches can only be published for existing releases.
Please create a release using "shorebird release" and try again.
''',
      );
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }

    return release;
  }

  Future<Release?> maybeGetRelease({
    required String appId,
    required String releaseVersion,
  }) async {
    final List<Release> releases;
    final fetchReleaseProgress = logger.progress('Fetching release');
    try {
      releases = await codePushClient.getReleases(appId: appId);
      fetchReleaseProgress.complete();
      return releases.firstWhereOrNull((r) => r.version == releaseVersion);
    } catch (error) {
      fetchReleaseProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }
  }

  Future<Map<Arch, ReleaseArtifact>> getReleaseArtifacts({
    required int releaseId,
    required Map<Arch, ArchMetadata> architectures,
    required String platform,
  }) async {
    final releaseArtifacts = <Arch, ReleaseArtifact>{};
    final fetchReleaseArtifactProgress = logger.progress(
      'Fetching release artifacts',
    );
    for (final entry in architectures.entries) {
      try {
        final releaseArtifact = await codePushClient.getReleaseArtifact(
          releaseId: releaseId,
          arch: entry.value.arch,
          platform: platform,
        );
        releaseArtifacts[entry.key] = releaseArtifact;
      } catch (error) {
        fetchReleaseArtifactProgress.fail('$error');
        exit(ExitCode.software.code);
        throw const UnreachableException();
      }
    }

    fetchReleaseArtifactProgress.complete();
    return releaseArtifacts;
  }

  Future<ReleaseArtifact?> maybeGetReleaseArtifact({
    required int releaseId,
    required String arch,
    required String platform,
  }) async {
    final fetchReleaseArtifactProgress = logger.progress(
      'Fetching $arch artifact',
    );
    try {
      final artifact = await codePushClient.getReleaseArtifact(
        releaseId: releaseId,
        arch: arch,
        platform: platform,
      );
      fetchReleaseArtifactProgress.complete();
      return artifact;
    } on CodePushNotFoundException {
      fetchReleaseArtifactProgress.complete();
      return null;
    } catch (error) {
      fetchReleaseArtifactProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }
  }

  Future<Patch> createPatch({required int releaseId}) async {
    final createPatchProgress = logger.progress('Creating patch');
    try {
      final patch = await codePushClient.createPatch(releaseId: releaseId);
      createPatchProgress.complete();
      return patch;
    } catch (error) {
      createPatchProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }
  }

  Future<void> createPatchArtifacts({
    required Patch patch,
    required String platform,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
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
        exit(ExitCode.software.code);
        throw const UnreachableException();
      }
    }
    createArtifactProgress.complete();
  }

  Future<void> promotePatch({
    required int patchId,
    required Channel channel,
  }) async {
    final promotePatchProgress = logger.progress(
      'Promoting patch to ${channel.name}',
    );
    try {
      await codePushClient.promotePatch(
        patchId: patchId,
        channelId: channel.id,
      );
      promotePatchProgress.complete();
    } catch (error) {
      promotePatchProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }
  }

  Future<void> publishPatch({
    required String appId,
    required int releaseId,
    required String platform,
    required String channelName,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final patch = await createPatch(
      releaseId: releaseId,
    );

    await createPatchArtifacts(
      patch: patch,
      platform: platform,
      patchArtifactBundles: patchArtifactBundles,
    );

    final channel = await maybeGetChannel(
          appId: appId,
          name: channelName,
        ) ??
        await createChannel(
          appId: appId,
          name: channelName,
        );

    await promotePatch(patchId: patch.id, channel: channel);
  }
}
