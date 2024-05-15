import 'package:http/retry.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:test/test.dart';

void main() {
  group('scoped', () {
    test('creates instance with default constructor', () {
      final instance = runScoped(
        () => httpClient,
        values: {httpClientRef},
      );
      expect(instance, isA<RetryClient>());
    });
  });
}
