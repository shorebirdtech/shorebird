import 'dart:async';

import 'package:redis_client/redis_client.dart';

Future<void> main() async {
  // Create an instance of a RedisClient.
  final client = RedisClient();

  // Connect to the Redis server.
  await client.connect();

  const key = 'HELLO';

  final initialValue = await client.get(key: key); // null
  assert(initialValue == null, 'Key should not exist.');

  // Set the value of a key.
  await client.set(key: key, value: 'WORLD');

  // Get the value of a key.
  final value = await client.get(key: key); // WORLD
  assert(value == 'WORLD', 'Value should be "WORLD".');

  // Delete the key.
  await client.delete(key: key);

  final finalValue = await client.get(key: key); // null
  assert(finalValue == null, 'Key should not exist.');

  // Close the connection to the Redis server.
  await client.close();
}
