import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../mocks.dart';

void main() {
  group(LoggingClient, () {
    late http.Client httpClient;
    late ShorebirdLogger logger;
    late LoggingClient loggingClient;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      loggingClient = LoggingClient(httpClient: httpClient);

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          HttpStatus.ok,
        ),
      );
    });

    test('logs request', () async {
      final uri = Uri.parse('https://example.com');
      final request = http.Request('GET', uri);

      await runWithOverrides(() => loggingClient.send(request));

      verify(() => logger.detail('[HTTP] $request'));
    });
  });
}
