import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

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

mixin ShorebirdCodePushClientMixin on ShorebirdConfigMixin {
  Future<App?> getApp({required String appId, String? flavor}) async {
    final shorebirdYaml = getShorebirdYaml()!;
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
      return null;
    }

    final appId = shorebirdYaml.getAppId(flavor: flavor);
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

  Future<Channel?> createChannel({
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
      return null;
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
      return null;
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

  Future<Map<Arch, String>?> downloadReleaseArtifacts({
    required Map<Arch, ReleaseArtifact> releaseArtifacts,
    required http.Client httpClient,
  }) async {
    final releaseArtifactPaths = <Arch, String>{};
    final downloadReleaseArtifactProgress = logger.progress(
      'Downloading release artifacts',
    );
    for (final releaseArtifact in releaseArtifacts.entries) {
      try {
        final releaseArtifactPath = await downloadReleaseArtifact(
          Uri.parse(releaseArtifact.value.url),
          httpClient: httpClient,
        );
        releaseArtifactPaths[releaseArtifact.key] = releaseArtifactPath;
      } catch (error) {
        downloadReleaseArtifactProgress.fail('$error');
        return null;
      }
    }

    downloadReleaseArtifactProgress.complete();
    return releaseArtifactPaths;
  }

  Future<String> downloadReleaseArtifact(
    Uri uri, {
    required http.Client httpClient,
  }) async {
    final request = http.Request('GET', uri);
    final response = await httpClient.send(request);

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

  Future<String> createDiff({
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
