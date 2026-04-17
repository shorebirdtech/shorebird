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

    R runWithTracer<R>(R Function() body) =>
        runScoped(body, values: {shorebirdTracerRef.overrideWith(() => tracer)});

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
        final req = http.Request('GET', Uri.parse('https://api.example.com/v1'));
        final response = await client.send(req);
        await response.stream.drain<void>();
      });

      expect(tracer.events, hasLength(1));
      final event = tracer.events.single;
      expect(event.name, 'GET api.example.com');
      expect(event.category, 'network');
      expect(event.args?['method'], 'GET');
      expect(event.args?['host'], 'api.example.com');
      expect(event.args?['status'], 200);
    });

    test('records a network event even when inner throws', () async {
      when(() => inner.send(any())).thenThrow(http.ClientException('boom'));

      await runWithTracer(() async {
        final req = http.Request(
          'POST',
          Uri.parse('https://api.example.com/v1'),
        );
        await expectLater(client.send(req), throwsA(isA<http.ClientException>()));
      });

      expect(tracer.events, hasLength(1));
      final event = tracer.events.single;
      expect(event.name, 'POST api.example.com');
      expect(event.category, 'network');
      // Status is omitted when the request didn't complete.
      expect(event.args?.containsKey('status'), isFalse);
      expect(event.args?['method'], 'POST');
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

        expect(tracer.events.single.args?['contentLength'], 5);
      },
    );
  });
}
