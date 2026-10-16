import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:test/test.dart';
import '../helpers.dart';

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
  });
}
