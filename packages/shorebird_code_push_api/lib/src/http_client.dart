import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

const _scopes = [
  // Cloud Storage
  'https://www.googleapis.com/auth/devstorage.read_write',
];

Future<http.Client> createClient(String key) async {
  try {
    // coverage:ignore-start
    final serviceAccount = ServiceAccountCredentials.fromJson(key);
    final client = await clientViaServiceAccount(serviceAccount, _scopes);
    return client;
    // coverage:ignore-end
  } catch (_) {
    return http.Client();
  }
}
