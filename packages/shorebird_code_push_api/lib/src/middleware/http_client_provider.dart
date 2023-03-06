import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/http_client.dart';
import 'package:shorebird_code_push_api/src/provider.dart';

Middleware httpClientProvider(String key) {
  return provider<Future<http.Client>>(
    (_) async => _httpClient ??= createClient(key),
  );
}

Future<http.Client>? _httpClient;
