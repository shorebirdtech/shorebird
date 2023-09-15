import 'package:redis_client/redis_client.dart';

Future<void> main() async {
  // Create an instance of a RedisClient.
  final client = RedisClient();

  // Connect to the Redis server.
  await client.connect();

  // Send a command to the Redis server.
  await client.sendCommand(['PING']); // PONG

  // Close the connection.
  await client.close();
}
