import 'package:jwt/jwt.dart' as jwt;

Future<void> main() async {
  final token = await jwt.verify(
    '<TOKEN>',
    issuer: '<ISSUER>',
    audience: {'<AUDIENCE>'},
    publicKeysUrl: '<PUBLIC_KEYS_URL>',
    jwksFormat: jwt.JwksFormat.keyValue,
  );
  print(token);
}
