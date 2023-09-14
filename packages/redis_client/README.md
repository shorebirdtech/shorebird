# Redis Client

[![License: MIT][license_badge]][license_link]

A Dart library for interacting with [Redis](https://redis.io).

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT

## Quick Start

```dart
import 'dart:async';

import 'package:redis_client/redis_client.dart';

Future<void> main() async {
  // Create an instance of a RedisClient.
  final client = RedisClient();

  // Connect to the Redis server.
  await client.connect();

  // Set the value of a key.
  await client.set(key: 'HELLO', value: 'WORLD');

  // Get the value of a key.
  final value = await client.get(key: 'HELLO'); // WORLD

  // Delete the key.
  await client.delete(key: 'HELLO');

  // Close the connection to the Redis server.
  await client.close();
}
```

## License

Shorebird packages are licensed for use under either Apache License, Version 2.0
(LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0) MIT license
(LICENSE-MIT or http://opensource.org/licenses/MIT) at your option.

See our license philosophy for more information on why we license files this
way:
https://github.com/shorebirdtech/handbook/blob/main/engineering.md#licensing-philosophy
