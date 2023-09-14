import 'dart:io';

import 'package:redis_client/redis_client.dart';
import 'package:test/test.dart';

void main() {
  group(RedisClient, () {
    late RedisClient client;

    setUp(() async {
      client = RedisClient();
      await client.connect();
    });

    tearDown(() async {
      try {
        await client.sendCommand(['RESET']);
        await client.sendCommand(['FLUSHALL']);
        await client.close();
      } catch (_) {
        // ignore
      }
    });

    group('connect', () {
      test('throws SocketException when connection times out', () async {
        final client = RedisClient(
          socket: const RedisSocketOptions(timeout: Duration(microseconds: 1)),
        );
        await expectLater(
          () => client.connect(maxConnectionAttempts: 1),
          throwsA(
            isA<SocketException>().having(
              (e) => e.message,
              'message',
              contains('Connection timed out'),
            ),
          ),
        );
      });

      test('throws SocketException after max connection attempts', () async {
        final client = RedisClient(
          socket: const RedisSocketOptions(port: 1234),
        );
        await expectLater(
          () => client.connect(maxConnectionAttempts: 1),
          throwsA(
            isA<SocketException>().having(
              (e) => e.message,
              'message',
              contains('Connection refused'),
            ),
          ),
        );
      });

      test('throws SocketException after disconnect', () async {
        final client = RedisClient(
          socket: const RedisSocketOptions(port: 1234),
        );
        await expectLater(
          () => client.connect(maxConnectionAttempts: 0),
          throwsA(
            isA<SocketException>().having(
              (e) => '$e',
              'message',
              contains('Connection retry limit exceeded'),
            ),
          ),
        );
      });

      test('throws StateError when closed', () async {
        await client.close();
        await expectLater(
          client.connect(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'RedisClient has been closed.',
            ),
          ),
        );
      });
    });

    group('AUTH', () {
      test('is required', () async {
        await expectLater(
          client.get(key: 'foo'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('-NOAUTH Authentication required.'),
            ),
          ),
        );
      });

      test('fails when username is incorrect', () async {
        await expectLater(
          client.auth(username: 'shorebird', password: 'password'),
          completion(isFalse),
        );
      });

      test('fails when password is incorrect', () async {
        await expectLater(
          client.auth(password: 'oops'),
          completion(isFalse),
        );
      });

      test('succeeds when username/password are correct', () async {
        await expectLater(
          client.auth(password: 'password'),
          completion(isTrue),
        );
      });
    });

    group('GET/SET/DEL', () {
      test('completes', () async {
        const key = 'key';
        const value = 'value';
        await client.auth(password: 'password');
        await expectLater(client.get(key: key), completion(isNull));
        await expectLater(client.set(key: key, value: value), completes);
        await expectLater(client.get(key: key), completion(equals(value)));
        await expectLater(client.delete(key: key), completes);
        await expectLater(client.get(key: key), completion(isNull));
      });

      test(
          'throws SocketException '
          'when command timeout is exceeded', () async {
        final client = RedisClient(
          command: const RedisCommandOptions(timeout: Duration.zero),
        );
        await client.connect();
        await expectLater(
          client.get(key: 'foo'),
          throwsA(
            isA<SocketException>().having(
              (e) => e.message,
              'message',
              contains('Connection timed out'),
            ),
          ),
        );
      });
    });

    group('JSON', () {
      group('GET/SET/DEL', () {
        test('completes', () async {
          const key = 'key';
          const value = {
            'hello': 'world',
            'foo': true,
            'nested': {'bar': 42},
            'array': [1, 2, 3],
          };
          await client.auth(password: 'password');
          await expectLater(client.json.get(key: key), completion(isNull));
          await expectLater(client.json.set(key: key, value: value), completes);
          await expectLater(
            client.json.get(key: key),
            completion(equals(value)),
          );
          await expectLater(client.json.delete(key: key), completes);
          await expectLater(client.json.get(key: key), completion(isNull));
        });
      });
    });
  });
}
