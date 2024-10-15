import 'package:scoped_deps/scoped_deps.dart';
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
}
