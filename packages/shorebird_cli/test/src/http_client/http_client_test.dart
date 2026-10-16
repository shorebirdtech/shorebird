import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';
import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group('scoped', () {
    test('creates instance with default constructor', () {
      final instance = runScoped(() => httpClient, values: {httpClientRef});
      expect(instance, isA<TracingClient>());
    });

    test('creates a non-retrying instance', () {
      final instance = runScoped(
        () => nonRetryingHttpClient,
        values: {nonRetryingHttpClientRef},
      );
      expect(instance, isA<TracingClient>());
    });

    group('sends the shorebird User-Agent', () {
      late HttpServer server;
      late List<String?> userAgents;

      setUp(() async {
        userAgents = [];
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
          ..listen((request) async {
            userAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
            await request.response.close();
          });
      });

      tearDown(() => server.close(force: true));

      Uri serverUri() => Uri.parse('http://127.0.0.1:${server.port}/');

      R runWithOverrides<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            httpClientRef,
            nonRetryingHttpClientRef,
            loggerRef.overrideWith(MockShorebirdLogger.new),
            shorebirdTracerRef.overrideWith(ShorebirdTracer.new),
          },
        );
      }

      test('from the retrying client', () async {
        await runWithOverrides(() => httpClient.get(serverUri()));
        expect(userAgents, equals([runScoped(() => shorebirdUserAgent)]));
      });

      test('from the non-retrying client', () async {
        await runWithOverrides(() => nonRetryingHttpClient.get(serverUri()));
        expect(userAgents, equals([runScoped(() => shorebirdUserAgent)]));
      });
    });
  });
}
