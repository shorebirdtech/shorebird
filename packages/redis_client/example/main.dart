import 'package:shorebird_redis_client/shorebird_redis_client.dart';

Future<void> main() async {
  // Create an instance of a RedisClient.
  final client = RedisClient();

  // Connect to the Redis server.
  await client.connect();

  // Execute a command.
  await client.execute(['PING']); // PONG

  // Close the connection.
  await client.close();
}
