// ignore_for_file: unused_local_variable

import 'package:shorebird_code_push_api_client/src/shorebird_code_push_api_client.dart';

Future<void> main() async {
  final client = ShorebirdCodePushApiClient(apiKey: '<API KEY>');

  // Download the latest engine revision.
  final engine = await client.downloadEngine('latest');

  // Create a new release.
  await client.createRelease('path/to/release/libapp.so');
}
