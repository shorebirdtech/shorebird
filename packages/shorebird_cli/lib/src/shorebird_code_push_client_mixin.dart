import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

mixin ShorebirdCodePushClientMixin on ShorebirdConfigMixin {
  Future<App?> getApp({required String appId, String? flavor}) async {
    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final List<App> apps;
    final fetchAppsProgress = logger.progress('Fetching apps');
    try {
      apps = (await codePushClient.getApps())
          .map((a) => App(id: a.appId, displayName: a.displayName))
          .toList();
      fetchAppsProgress.complete();
    } catch (error) {
      fetchAppsProgress.fail('$error');
      rethrow;
    }

    return apps.firstWhereOrNull((a) => a.id == appId);
  }

  Future<Channel?> getChannel({
    required String appId,
    required String name,
  }) async {
    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );
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
      rethrow;
    }
  }

  Future<Channel> createChannel({
    required String appId,
    required String name,
  }) async {
    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

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
      rethrow;
    }
  }

  Future<Release?> getRelease({
    required String appId,
    required String releaseVersion,
  }) async {
    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final List<Release> releases;
    final fetchReleaseProgress = logger.progress('Fetching release');
    try {
      releases = await codePushClient.getReleases(appId: appId);
      fetchReleaseProgress.complete();
    } catch (error) {
      fetchReleaseProgress.fail('$error');
      rethrow;
    }

    return releases.firstWhereOrNull((r) => r.version == releaseVersion);
  }

  Future<Map<Arch, ReleaseArtifact>?> getReleaseArtifacts({
    required Release release,
    required Map<Arch, ArchMetadata> architectures,
    required String platform,
  }) async {
    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

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
        return null;
      }
    }

    fetchReleaseArtifactProgress.complete();
    return releaseArtifacts;
  }
}
