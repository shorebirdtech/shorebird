import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';

/// An http client that records each request as a `network`-category trace
/// event on the ambient [ShorebirdTracer]. Wraps another [http.Client];
/// intended to sit at the outermost layer so retries, logging, and any
/// other middleware roll up into the same span.
///
/// The span covers the *whole* transfer, not just the handshake.
/// [http.BaseClient.send] resolves as soon as response headers arrive, so
/// timing it alone measures time-to-first-byte and reports a 150 MB
/// artifact download as a few hundred milliseconds. To measure what a
/// user actually waits for, the response body is wrapped and the span is
/// closed when the last byte is drained (or the stream errors or is
/// cancelled). Time-to-first-byte is kept alongside it in `ttfbMs`, so a
/// slow origin and a slow pipe remain distinguishable.
class TracingClient extends http.BaseClient {
  /// Wraps [httpClient], recording a span per request.
  TracingClient({required http.Client httpClient}) : _baseClient = httpClient;

  final http.Client _baseClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final start = DateTime.now();

    final http.StreamedResponse response;
    try {
      response = await _baseClient.send(request);
    } catch (_) {
      _record(request, start: start, ttfb: DateTime.now().difference(start));
      rethrow;
    }

    final ttfb = DateTime.now().difference(start);

    // Only success responses carry a body worth timing, and only they are
    // reliably drained. Callers routinely abandon an error response
    // without reading it (see `Cache.update`, which throws on a non-200
    // without touching `response.stream`); waiting for a drain that never
    // comes would silently drop the event. So close the span here.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _record(
        request,
        start: start,
        ttfb: ttfb,
        statusCode: response.statusCode,
      );
      return response;
    }

    var byteCount = 0;
    var recorded = false;
    void recordOnce() {
      if (recorded) return;
      recorded = true;
      _record(
        request,
        start: start,
        ttfb: ttfb,
        statusCode: response.statusCode,
        responseBytes: byteCount,
      );
    }

    // Mirrored through an explicit controller rather than an `async*`
    // generator: a generator can only observe cancellation at its next
    // `yield`, so cancelling a download that is stalled mid-transfer
    // would not take effect until the next chunk arrived. Forwarding
    // `onCancel` straight to the upstream subscription keeps aborts
    // immediate, and gives one place to close the span on done, error,
    // and cancel alike.
    //
    // A 2xx body that is never listened to records nothing — no such
    // caller exists today, and inventing a duration for bytes nobody
    // waited on would be worse than a gap.
    final controller = StreamController<List<int>>();
    late final StreamSubscription<List<int>> subscription;
    controller
      ..onListen = () {
        subscription = response.stream.listen(
          (chunk) {
            byteCount += chunk.length;
            controller.add(chunk);
          },
          onError: controller.addError,
          onDone: () {
            recordOnce();
            unawaited(controller.close());
          },
        );
      }
      ..onPause = () {
        subscription.pause();
      }
      ..onResume = () {
        subscription.resume();
      }
      ..onCancel = () {
        recordOnce();
        return subscription.cancel();
      };

    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  void _record(
    http.BaseRequest request, {
    required DateTime start,
    required Duration ttfb,
    int? statusCode,
    int? responseBytes,
  }) {
    shorebirdTracer.addNetworkEvent(
      name: '${request.method} ${request.url.host}',
      start: start,
      duration: DateTime.now().difference(start),
      args: {
        'method': request.method,
        'host': request.url.host,
        'status': ?statusCode,
        'contentLength': ?request.contentLength,
        'ttfbMs': ttfb.inMilliseconds,
        'responseBytes': ?responseBytes,
      },
    );
  }
}
