// ignore_for_file: unused_local_variable

import 'package:shorebird_code_push_api_client/shorebird_code_push_api_client.dart';

Future<void> main() async {
  final client = ShorebirdCodePushApiClient(apiKey: '<API KEY>');

  // Download the latest engine revision.
  final engine = await client.downloadEngine('latest');

  // Create a new Shorebird application.
  await client.createApp(productId: '<PRODUCT-ID>');

  // Create a new patch.
  await client.createPatch(
    artifactPath: '<PATH TO ARTIFACT>', // e.g. 'libapp.so'
    baseVersion: '<BASE VERSION>', // e.g. '1.0.0'
    productId: '<PRODUCT ID>', // e.g. 'shorebird-example'
    channel: '<CHANNEL>', // e.g. 'stable'
  );

  // Close the client.
  client.close();
}
