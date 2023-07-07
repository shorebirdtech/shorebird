// ignore_for_file: avoid_print
import 'package:jwt/jwt.dart' as jwt;

Future<void> main() async {
  final token = await jwt.verify(
    '<TOKEN>',
    issuer: '<ISSUER>',
    audience: {'<AUDIENCE>'},
    publicKeysUrl: '<PUBLIC_KEYS_URL>',
  );
  print(token);
}
