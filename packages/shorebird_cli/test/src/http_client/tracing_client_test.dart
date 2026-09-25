import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';
import 'package:shorebird_cli/src/http_client/tracing_client.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeBaseRequest());
  });

  group(TracingClient, () {
    late http.Client inner;
    late ShorebirdTracer tracer;
    late TracingClient client;

    R runWithTracer<R>(R Function() body) => runScoped(
      body,
      values: {shorebirdTracerRef.overrideWith(() => tracer)},
    );

    setUp(() {
      inner = _MockHttpClient();
      tracer = ShorebirdTracer();
      client = TracingClient(httpClient: inner);
    });

    http.StreamedResponse streamed({
      int statusCode = 200,
      String body = 'ok',
    }) => http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
    );

    test('records a network event on success', () async {
      when(() => inner.send(any())).thenAnswer((_) async => streamed());

      await runWithTracer(() async {
        final req = http.Request(
          'GET',
          Uri.parse('https://api.example.com/v1'),
        );
        final response = await client.send(req);
        await response.stream.drain<void>();
      });

      expect(tracer.events, hasLength(1));
      final event = tracer.events.single;
      expect(event['name'], 'GET api.example.com');
      expect(event['cat'], 'network');
      expect((event['args']! as Map)['method'], 'GET');
      expect((event['args']! as Map)['host'], 'api.example.com');
      expect((event['args']! as Map)['status'], 200);
    });

    test('records a network event even when inner throws', () async {
      when(() => inner.send(any())).thenThrow(http.ClientException('boom'));

      await runWithTracer(() async {
        final req = http.Request(
          'POST',
          Uri.parse('https://api.example.com/v1'),
        );
        await expectLater(
          client.send(req),
          throwsA(isA<http.ClientException>()),
        );
      });

      expect(tracer.events, hasLength(1));
      final event = tracer.events.single;
      expect(event['name'], 'POST api.example.com');
      expect(event['cat'], 'network');
      // Status is omitted when the request didn't complete.
      expect((event['args']! as Map).containsKey('status'), isFalse);
      expect((event['args']! as Map)['method'], 'POST');
    });

    test('measures until the body is drained, not until headers', () async {
      // The regression this guards: `send()` resolves on headers, so
      // timing it alone reports a large, slow download as a few
      // milliseconds.
      final controller = StreamController<List<int>>();
      when(() => inner.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(controller.stream, 200),
      );

      await runWithTracer(() async {
        final req = http.Request(
          'GET',
          Uri.parse('https://storage.example.com/artifact.zip'),
        );
        final response = await client.send(req);
        // Headers have arrived; not a single body byte has.
        final drained = response.stream.drain<void>();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        controller.add(utf8.encode('payload'));
        await controller.close();
        await drained;
      });

      final event = tracer.events.single;
      expect(
        event['dur'],
        greaterThanOrEqualTo(const Duration(milliseconds: 50).inMicroseconds),
      );
      final args = event['args']! as Map;
      expect(args['responseBytes'], 7);
      // Time-to-first-byte stays separable from transfer time.
      expect(args['ttfbMs'], lessThan(50));
    });

    test('propagates pause and resume to the upstream body', () async {
      // Backpressure has to reach the socket: without this the wrapper
      // would buffer a whole artifact in memory while the consumer
      // (a file write) is paused.
      final controller = StreamController<List<int>>();
      when(() => inner.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(controller.stream, 200),
      );

      await runWithTracer(() async {
        final req = http.Request(
          'GET',
          Uri.parse('https://storage.example.com/artifact.zip'),
        );
        final response = await client.send(req);
        final received = <int>[];
        final subscription = response.stream.listen(received.addAll);

        subscription.pause();
        controller.add(utf8.encode('ab'));
        await Future<void>.delayed(Duration.zero);
        expect(received, isEmpty, reason: 'paused: nothing delivered');

        subscription.resume();
        await Future<void>.delayed(Duration.zero);
        expect(received, utf8.encode('ab'));

        await controller.close();
        await subscription.asFuture<void>();
      });

      expect((tracer.events.single['args']! as Map)['responseBytes'], 2);
    });

    test('records a cancelled response stream', () async {
      final controller = StreamController<List<int>>();
      when(() => inner.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(controller.stream, 200),
      );

      await runWithTracer(() async {
        final req = http.Request(
          'GET',
          Uri.parse('https://storage.example.com/artifact.zip'),
        );
        final response = await client.send(req);
        await response.stream.listen(null).cancel();
      });

      expect(tracer.events, hasLength(1));
      expect((tracer.events.single['args']! as Map)['status'], 200);
    });

    test('records a non-2xx response without waiting for a drain', () async {
      // `Cache.update` throws on a non-200 without reading the body, so
      // a drain-only span would never be emitted for these.
      when(
        () => inner.send(any()),
      ).thenAnswer((_) async => streamed(statusCode: 404, body: 'nope'));

      await runWithTracer(() async {
        final req = http.Request(
          'GET',
          Uri.parse('https://storage.example.com/missing.zip'),
        );
        await client.send(req);
      });

      expect(tracer.events, hasLength(1));
      final args = tracer.events.single['args']! as Map;
      expect(args['status'], 404);
      expect(args.containsKey('responseBytes'), isFalse);
    });

    test('passes response metadata through the wrapper', () async {
      when(
        () => inner.send(any()),
      ).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode('body')),
          200,
          contentLength: 4,
          headers: const {'content-type': 'application/zip'},
          reasonPhrase: 'OK',
        ),
      );

      await runWithTracer(() async {
        final req = http.Request(
          'GET',
          Uri.parse('https://storage.example.com/artifact.zip'),
        );
        final response = await client.send(req);
        expect(response.contentLength, 4);
        expect(response.headers['content-type'], 'application/zip');
        expect(response.reasonPhrase, 'OK');
        expect(await response.stream.bytesToString(), 'body');
      });
    });

    test(
      'records contentLength when the request provides one',
      () async {
        when(() => inner.send(any())).thenAnswer((_) async => streamed());

        await runWithTracer(() async {
          final req = http.Request(
            'POST',
            Uri.parse('https://api.example.com/v1'),
          )..body = 'hello';
          final response = await client.send(req);
          await response.stream.drain<void>();
        });

        expect(
          (tracer.events.single['args']! as Map)['contentLength'],
          5,
        );
      },
    );
  });
}
