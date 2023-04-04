# jwt

[![License: MIT][license_badge]][license_link]

A Dart JWT Library.

```dart
import 'package:jwt/jwt.dart' as jwt;

Future<void> main() async {
  // Verify and extract a JWT token.
  final Jwt token = await jwt.verify(
    '<TOKEN>',
    issuer: '<ISSUER>',
    audience: '<AUDIENCE>',
    publicKeysUrl: '<PUBLIC_KEYS_URL>',
  );
}

```

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
