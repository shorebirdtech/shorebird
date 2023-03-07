import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';

http.Client? _httpClient;

Middleware httpClientProvider() {
  return provider<http.Client>((_) => _httpClient ??= http.Client());
}
