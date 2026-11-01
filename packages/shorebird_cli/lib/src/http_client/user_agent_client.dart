import 'package:http/http.dart' as http;
import 'package:shorebird_cli/src/abi.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/version.dart';

/// The `User-Agent` the CLI sends with every request, such as
/// `shorebird-cli/1.6.0 (macos; arm64; dart 3.9.0)`: the CLI version, the
/// operating system, the machine's CPU architecture
/// ([LocalAbi.hostArchitecture]) and the Dart version.
///
/// Without it, requests carry `dart:io`'s default, `Dart/<version> (dart:io)`,
/// which does not say which tool, version or operating system sent them.
String get shorebirdUserAgent {
  // Platform.version reads like `3.9.0 (stable) (...) on "macos_arm64"`.
  final dartVersion = platform.version.split(' ').first;
  return 'shorebird-cli/$packageVersion '
      '(${platform.operatingSystem}; ${abi.hostArchitecture}; '
      'dart $dartVersion)';
}

/// An http client that sets [shorebirdUserAgent] as the `User-Agent` of each
/// request that does not already set one.
class UserAgentClient extends http.BaseClient {
  /// Creates a new [UserAgentClient] wrapping [httpClient].
  UserAgentClient({required http.Client httpClient}) : _baseClient = httpClient;

  final http.Client _baseClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Header names are case-insensitive in package:http, so this keeps a
    // caller's `user-agent` too.
    request.headers.putIfAbsent('User-Agent', () => shorebirdUserAgent);
    return _baseClient.send(request);
  }

  @override
  void close() => _baseClient.close();
}
