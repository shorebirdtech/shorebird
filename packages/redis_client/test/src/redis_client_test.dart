import 'package:redis_client/redis_client.dart';
import 'package:test/test.dart';

void main() {
  group(RedisClient, () {
    test('can be instantiated', () {
      expect(const RedisClient(), isNotNull);
    });
  });
}
