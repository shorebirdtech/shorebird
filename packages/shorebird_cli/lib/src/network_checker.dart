import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';

/// A reference to a [NetworkChecker] instance.
final networkCheckerRef = create(NetworkChecker.new);

/// The [NetworkChecker] instance available in the current zone.
NetworkChecker get networkChecker => read(networkCheckerRef);

/// {@template network_checker}
/// Checks reachability of various Shorebird-related endpoints and logs the
/// results.
/// {@endtemplate}
class NetworkChecker {
  /// The URLs to check for network reachability.
  static final urlsToCheck = [
    'https://api.shorebird.dev',
    'https://console.shorebird.dev',
    'https://oauth2.googleapis.com',
    'https://storage.googleapis.com',
    'https://cdn.shorebird.cloud',
  ].map(Uri.parse).toList();

  /// Verify that each of [urlsToCheck] responds to an HTTP GET request.
  Future<void> checkReachability() async {
    for (final url in urlsToCheck) {
      final progress = logger.progress('Checking reachability of $url');

      try {
        await httpClient.get(url);
        progress.complete('$url OK');
      } catch (e) {
        progress.fail('$url unreachable');
        logger.detail('Failed to reach $url: $e');
      }
    }
  }

  /// Uploads a file to GCP to measure upload speed.
  Future<void> performGCPSpeedTest() async {
    // Test with a 5MB file.
    const uploadMBs = 5;
    const fileSize = uploadMBs * 1000 * 1000;

    // If they can't upload the file in two minutes, we can just say it's slow.
    const uploadTimeout = Duration(minutes: 2);

    final tempDir = Directory.systemTemp.createTempSync();
    final testFile = File(p.join(tempDir.path, 'speed_test_file'))
      ..writeAsBytesSync(ByteData(fileSize).buffer.asUint8List());

    final progress = logger.progress('Performing GCP speed test');

    final uri = await codePushClientWrapper.getGCPSpeedTestUrl();
    final start = DateTime.now();
    final file = await http.MultipartFile.fromPath('file', testFile.path);
    final uploadRequest = http.MultipartRequest('POST', uri)..files.add(file);
    final uploadResponse = await httpClient.send(uploadRequest).timeout(
      uploadTimeout,
      onTimeout: () {
        progress.fail('GCP speed test aborted: upload timed out');
        throw Exception('GCP speed test aborted: upload timed out');
      },
    );
    if (uploadResponse.statusCode != HttpStatus.noContent) {
      final body = await uploadResponse.stream.bytesToString();
      progress.fail('Failed to upload file');
      throw Exception(
        'Failed to upload file: $body ${uploadResponse.statusCode}',
      );
    }

    final end = DateTime.now();
    final uploadRate = fileSize / (end.difference(start).inMilliseconds * 1000);
    progress.complete(
      'GCP Upload Speed: ${uploadRate.toStringAsFixed(2)} MB/s',
    );
  }
}
