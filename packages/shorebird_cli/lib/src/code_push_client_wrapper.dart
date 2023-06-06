import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class UnreachableException implements Exception {
  const UnreachableException();
}

/// Metadata about a patch artifact that we are about to upload.
class PatchArtifactBundle {
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

class CodePushClientWrapper {
  CodePushClientWrapper({
    required this.codePushClient,
    required this.logger,
  });

  final CodePushClient codePushClient;
  final Logger logger;

  Future<App?> getApp({
    required String appId,
    bool failOnNotFound = false,
  }) async {
    final List<App> apps;
    final fetchAppsProgress = logger.progress('Fetching apps');
    try {
      apps = (await codePushClient.getApps())
          .map((a) => App(id: a.appId, displayName: a.displayName))
          .toList();
      fetchAppsProgress.complete();
    } catch (error) {
      fetchAppsProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }

    final app = apps.firstWhereOrNull((a) => a.id == appId);
    if (app == null && failOnNotFound) {
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

  Future<Channel?> getChannel({
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

  Future<Release?> getRelease({
    required String appId,
    required String releaseVersion,
    bool failOnNotFound = false,
  }) async {
    final List<Release> releases;
    final fetchReleaseProgress = logger.progress('Fetching release');
    try {
      releases = await codePushClient.getReleases(appId: appId);
      fetchReleaseProgress.complete();
    } catch (error) {
      fetchReleaseProgress.fail('$error');
      exit(ExitCode.software.code);
      throw const UnreachableException();
    }

    final release =
        releases.firstWhereOrNull((r) => r.version == releaseVersion);
    if (release == null && failOnNotFound) {
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

  Future<Map<Arch, ReleaseArtifact>> getReleaseArtifacts({
    required int releaseId,
    required Map<Arch, ArchMetadata> architectures,
    required String platform,
    bool failOnNotFound = false,
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
        if (failOnNotFound) {
          fetchReleaseArtifactProgress.fail('$error');
          exit(ExitCode.software.code);
          throw const UnreachableException();
        }
      }
    }

    fetchReleaseArtifactProgress.complete();
    return releaseArtifacts;
  }

  Future<ReleaseArtifact?> getReleaseArtifact({
    required int releaseId,
    required String arch,
    required String platform,
    bool failOnNotFound = false,
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
    } catch (error) {
      if (failOnNotFound) {
        fetchReleaseArtifactProgress.fail('$error');
        exit(ExitCode.software.code);
        throw const UnreachableException();
      }

      // Do nothing for now, not all releases will have an associated aab
      // artifact.
      // TODO(bryanoltman): Treat this as an error once all releases have an aab
      fetchReleaseArtifactProgress.complete();
      return null;
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
    required Patch patch,
    required Channel channel,
  }) async {
    final promotePatchProgress = logger.progress(
      'Promoting patch to ${channel.name}',
    );
    try {
      await codePushClient.promotePatch(
        patchId: patch.id,
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

    final channel = await getChannel(
          appId: appId,
          name: channelName,
        ) ??
        await createChannel(
          appId: appId,
          name: channelName,
        );

    await promotePatch(patch: patch, channel: channel);
  }
}
