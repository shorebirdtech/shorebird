# 🐦 Shorebird Redis Client

[![Discord][discord_badge]][discord_link]

[![pub package][pub_badge]][pub_link]
[![ci][ci_badge]][ci_link]
[![codecov][codecov_badge]][codecov_link]
[![License: MIT][license_badge]][license_link]

A Dart library for interacting with a [Redis][redis_link] server.

Built with 💙 by [Shorebird][shorebird_link].

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

## Join us on Discord! 💬

We have an active [Discord server][discord_link] where you can
ask questions and get help.

## Contributing 🤝

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License 📃

Shorebird packages are licensed for use under either of the following at your option:

- [Apache License, Version 2.0][apache_link]
- [MIT license][mit_link]

See our [license philosophy](https://github.com/shorebirdtech/handbook/blob/main/engineering.md#licensing-philosophy) for more information on why we license files this way.

[apache_link]: http://www.apache.org/licenses/LICENSE-2.0
[ci_badge]: https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml/badge.svg
[ci_link]: https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml
[codecov_badge]: https://codecov.io/gh/shorebirdtech/shorebird/branch/main/graph/badge.svg
[codecov_link]: https://codecov.io/gh/shorebirdtech/shorebird
[discord_badge]: https://dcbadge.vercel.app/api/server/shorebird
[discord_link]: https://discord.gg/shorebird
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[mit_link]: http://opensource.org/licenses/MIT
[pub_badge]: https://img.shields.io/pub/v/shorebird_redis_client.svg
[pub_link]: https://pub.dev/packages/shorebird_redis_client
[redis_link]: https://redis.io
[shorebird_link]: https://shorebird.dev
