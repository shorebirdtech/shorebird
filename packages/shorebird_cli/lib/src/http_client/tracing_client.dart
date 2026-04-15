import 'package:http/http.dart' as http;
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';

/// An http client that records each request as a `network`-category trace
/// event on the ambient [ShorebirdTracer]. Wraps another [http.Client];
/// intended to sit at the outermost layer so retries, logging, and any
/// other middleware roll up into the same span.
class TracingClient extends http.BaseClient {
  /// Wraps [httpClient], recording a span per request.
  TracingClient({required http.Client httpClient}) : _baseClient = httpClient;

  final http.Client _baseClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final start = DateTime.now().microsecondsSinceEpoch;
    int? statusCode;
    try {
      final response = await _baseClient.send(request);
      statusCode = response.statusCode;
      return response;
    } finally {
      final end = DateTime.now().microsecondsSinceEpoch;
      shorebirdTracer.addEvent(
        ShorebirdTraceEvent(
          name: '${request.method} ${request.url.host}',
          category: 'network',
          startMicros: start,
          durationMicros: end - start,
          args: {
            'method': request.method,
            'host': request.url.host,
            'status': ?statusCode,
            'contentLength': ?request.contentLength,
          },
        ),
      );
    }
  }
}
