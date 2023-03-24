// ignore_for_file: unused_local_variable

import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

Future<void> main() async {
  final client = CodePushClient(apiKey: '<API KEY>');

  // Download the latest stable engine revision.
  final engine = await client.downloadEngine(
    revision: '<ENGINE REVISION>', // e.g. '9aa7816315'
  );

  // List all apps.
  final apps = await client.getApps();

  // Create a new Shorebird application.
  final app = await client.createApp(
    displayName: '<DISPLAY NAME>', // e.g. 'Shorebird Example'
  );

  // Create a channel.
  final channel = await client.createChannel(
    appId: app.id,
    channel: '<CHANNEL>', // e.g. 'stable'
  );

  // Create a release.
  final release = await client.createRelease(
    appId: app.id,
    version: '<VERSION>', // e.g. '1.0.0'
    displayName: '<DISPLAY NAME>', // e.g. 'v1.0.0'
  );

  // Create a new patch.
  final patch = await client.createPatch(releaseId: release.id);

  // Create an artifact.
  final artifact = await client.createArtifact(
    patchId: patch.id,
    artifactPath: '<PATH TO ARTIFACT>', // e.g. 'libapp.so'
    platform: '<PLATFORM>', // e.g. 'android'
    arch: '<ARCHITECTURE>', // e.g. 'aarch64'
    hash: '<HASH>', // 'sha256 hash of the artifact'
  );

  // Promote a patch to a channel.
  await client.promotePatch(patchId: patch.id, channelId: channel.id);

  // Close the client.
  client.close();
}
