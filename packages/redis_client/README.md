# 🐦 Shorebird Redis Client

[![pub package](https://img.shields.io/pub/v/shorebird_redis_client.svg)](https://pub.dev/packages/shorebird_redis_client)
[![ci](https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml/badge.svg)](https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml)
[![codecov](https://codecov.io/gh/shorebirdtech/shorebird/branch/main/graph/badge.svg)](https://codecov.io/gh/shorebirdtech/shorebird)
[![License: MIT][license_badge]][license_link]

A Dart library for interacting with a [Redis](https://redis.io) server.

Built with 💙 by [Shorebird](https://shorebird.dev).

## Quick Start 🚀

```dart
import 'package:shorebird_redis_client/shorebird_redis_client.dart';

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

## Testing 🧪

To run the tests locally, ensure you have [Docker](https://www.docker.com) installed and pull the redis-stack-server image:

```sh
docker pull redis/redis-stack-server
```

Then, start the server:

```sh
docker run -p 6379:6379 --rm -e REDIS_ARGS="--requirepass password" redis/redis-stack-server
```

Now you can run the tests locally:

```sh
dart test
```

## License 📃

Shorebird packages are licensed for use under either Apache License, Version 2.0
(LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0) MIT license
(LICENSE-MIT or http://opensource.org/licenses/MIT) at your option.

See our license philosophy for more information on why we license files this
way:
https://github.com/shorebirdtech/handbook/blob/main/engineering.md#licensing-philosophy

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
