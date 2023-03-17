// ignore_for_file: unused_local_variable

import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

Future<void> main() async {
  final client = CodePushClient(apiKey: '<API KEY>');

  // Download the latest engine revision.
  final engine = await client.downloadEngine('latest');

  // Create a new Shorebird application.
  await client.createApp(appId: '<APP ID>');

  // List all apps.
  final apps = await client.getApps();

  // Create a new patch.
  await client.createPatch(
    artifactPath: '<PATH TO ARTIFACT>', // e.g. 'libapp.so'
    releaseVersion: '<RELEASE VERSION>', // e.g. '1.0.0'
    appId: '<APP ID>', // e.g. 'shorebird-example'
    channel: '<CHANNEL>', // e.g. 'stable'
  );

  // Close the client.
  client.close();
}
