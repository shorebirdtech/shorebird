// ignore_for_file: unused_local_variable

import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

Future<void> main() async {
  final client = CodePushClient(apiKey: '<API KEY>');

  // Download the latest stable engine revision.
  final engine = await client.downloadEngine('1837b5be5f');

  // Create a new Shorebird application.
  final app = await client.createApp(
    displayName: '<DISPLAY NAME>', // e.g. 'Shorebird Example'
  );

  // List all apps.
  final apps = await client.getApps();

  // Create a new patch.
  await client.createPatch(
    artifactPath: '<PATH TO ARTIFACT>', // e.g. 'libapp.so'
    releaseVersion: '<RELEASE VERSION>', // e.g. '1.0.0'
    appId: app.id, // e.g. '30370f27-dbf1-4673-8b20-fb096e38dffa'
    channel: '<CHANNEL>', // e.g. 'stable'
  );

  // Close the client.
  client.close();
}
