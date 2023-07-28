import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group(LoggingClient, () {
    late http.Client httpClient;
    late Logger logger;
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
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      logger = _MockLogger();
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
