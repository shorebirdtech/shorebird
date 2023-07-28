import 'package:http/http.dart' as http;
import 'package:shorebird_cli/src/logger.dart';

/// An http client that logs request at the verbose level.
class LoggingClient extends http.BaseClient {
  LoggingClient({required http.Client httpClient}) : _baseClient = httpClient;

  final http.Client _baseClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    logger.detail('[HTTP] $request');
    return _baseClient.send(request);
  }
}
