import 'dart:async';
import 'dart:io';

import 'package:shorebird_redis_client/shorebird_redis_client.dart';
import 'package:test/test.dart';

void main() {
  group(RedisClient, () {
    late RedisClient client;

    setUp(() async {
      client = RedisClient(
        socket: const RedisSocketOptions(password: 'password'),
      );
    });

    tearDown(() async {
      await client.close();
    });

    group(RedisException, () {
      test('overrides toString', () {
        const message = 'A RedisException occurred.';
        const exception = RedisException(message);
        expect(exception.toString(), equals(message));
      });
    });

    group('connect', () {
      test('authenticates automatically when credentials are provided',
          () async {
        await expectLater(client.connect(), completes);
        await expectLater(client.execute(['PING']), completion(equals('PONG')));
      });

      test('throws SocketException when connection times out w/retry',
          () async {
        final client = RedisClient(
          socket: const RedisSocketOptions(
            timeout: Duration(microseconds: 1),
            retryAttempts: 1,
          ),
        );
        await expectLater(
          client.connect,
          throwsA(
            isA<SocketException>().having(
              (e) => e.message,
              'message',
              contains('Connection retry limit exceeded'),
            ),
          ),
        );
        await client.close();
      });

      test('throws SocketException after max connection attempts', () async {
        final client = RedisClient(
          socket: const RedisSocketOptions(port: 1234, retryAttempts: 1),
        );
        await expectLater(
          client.connect,
          throwsA(
            isA<SocketException>().having(
              (e) => e.message,
              'message',
              contains('Connection retry limit exceeded'),
            ),
          ),
        );
        await client.close();
      });

      test('throws SocketException after disconnect w/out retry', () async {
        final client = RedisClient(
          socket: const RedisSocketOptions(port: 1234, retryAttempts: 0),
        );
        await expectLater(
          client.connect,
          throwsA(
            isA<SocketException>().having(
              (e) => '$e',
              'message',
              contains('Connection retry limit exceeded'),
            ),
          ),
        );
        await client.close();
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

    group('disconnect', () {
      test('closes the connection and reconnects', () async {
        await client.connect();
        await client.disconnect();
        await expectLater(client.execute(['PING']), completion(equals('PONG')));
      });
    });

    group('AUTH', () {
      setUp(() async {
        await client.connect();
      });

      test('is required', () async {
        final client = RedisClient();
        await client.connect();
        await expectLater(
          client.get(key: 'foo'),
          throwsA(
            isA<RedisException>().having(
              (e) => e.message,
              'message',
              contains('-NOAUTH Authentication required.'),
            ),
          ),
        );
        await client.close();
      });

      test('fails when username is incorrect', () async {
        await expectLater(
          client.auth(username: 'shorebird', password: 'password'),
          throwsA(
            isA<RedisException>().having(
              (e) => e.message,
              'message',
              contains('-WRONGPASS invalid username-password pair'),
            ),
          ),
        );
      });

      test('fails when password is incorrect', () async {
        await expectLater(
          client.auth(password: 'oops'),
          throwsA(
            isA<RedisException>().having(
              (e) => e.message,
              'message',
              contains('-WRONGPASS invalid username-password pair'),
            ),
          ),
        );
      });

      test('succeeds when username/password are correct', () async {
        await expectLater(
          client.auth(password: 'password'),
          completes,
        );
      });
    });

    group('GET/SET/DEL', () {
      setUp(() async {
        await client.connect();
      });

      tearDown(() async {
        try {
          await client.execute(['RESET']);
          await client.execute(['FLUSHALL']);
        } catch (_) {
          // ignore
        }
      });

      test('completes', () async {
        const key = 'key';
        const value = 'value';
        await expectLater(client.get(key: key), completion(isNull));
        await expectLater(client.set(key: key, value: value), completes);
        await expectLater(client.get(key: key), completion(equals(value)));

        await expectLater(client.delete(key: key), completes);
        await expectLater(client.get(key: key), completion(isNull));

        await expectLater(client.set(key: key, value: value), completes);
        await expectLater(client.get(key: key), completion(equals(value)));
        await expectLater(client.unlink(key: key), completes);
        await expectLater(client.get(key: key), completion(isNull));
      });

      test(
          'throws TimeoutException '
          'when command timeout is exceeded', () async {
        final client = RedisClient(
          command: const RedisCommandOptions(timeout: Duration.zero),
        );
        await expectLater(
          client.get(key: 'foo'),
          throwsA(isA<TimeoutException>()),
        );
      });
    });

    group('JSON', () {
      group('GET/SET/DEL/MERGE', () {
        setUp(() async {
          await client.connect();
        });

        tearDown(() async {
          try {
            await client.execute(['RESET']);
            await client.execute(['FLUSHALL']);
          } catch (_) {
            // ignore
          }
        });

        test('completes', () async {
          const key = 'key';
          const value = {
            'string': 'hello',
            'bool': true,
            'map': {'bar': 42},
            'array': [1, 2, 3],
            'nested': {
              '1.0.0+1': {
                'android': {
                  'arch64': {
                    'url': 'http://example.com',
                  },
                },
              },
            },
          };
          const other = {'qux': 'quux'};
          await expectLater(client.json.get(key: key), completion(isNull));
          await expectLater(client.json.set(key: key, value: value), completes);
          await expectLater(
            client.json.get(key: key),
            completion(equals(value)),
          );          
          await expectLater(
            client.json.get(key: key, path: r'$.string'),
            completion(equals('hello')),
          );
          await expectLater(
            client.json.get(key: key, path: r'$.bool'),
            completion(equals(true)),
          );
          await expectLater(
            client.json.get(key: key, path: r'$.nested'),
            completion(
              equals(
                {
                  '1.0.0+1': {
                    'android': {
                      'arch64': {
                        'url': 'http://example.com',
                      },
                    },
                  },
                },
              ),
            ),
          );
          await expectLater(
            client.json.get(
              key: key,
              path: r'$.nested["1.0.0+1"]["android"]["arch64"]["url"]',
            ),
            completion(equals('http://example.com')),
          );
          await expectLater(
            client.json.get(key: key, path: r'$.array'),
            completion(equals([1, 2, 3])),
          );
          await expectLater(
            client.json.get(key: key, path: r'$.array[0]'),
            completion(equals(1)),
          );
          await expectLater(
            client.json.get(key: key, path: r'$.map'),
            completion(equals({'bar': 42})),
          );
          await expectLater(
            client.json.merge(key: key, value: other, path: r'$.map'),
            completes,
          );
          await expectLater(
            client.json.get(key: key, path: r'$.map'),
            completion(
              equals({
                ...{'bar': 42},
                ...other,
              }),
            ),
          );
          await expectLater(
            client.json.delete(key: key, path: r'$.map.qux'),
            completes,
          );
          await expectLater(
            client.json.merge(key: key, value: other),
            completes,
          );
          await expectLater(
            client.json.get(key: key),
            completion(equals({...value, ...other})),
          );
          await expectLater(
            client.json.set(key: key, value: false, path: r'$.bool'),
            completes,
          );
          await expectLater(
            client.json.get(key: key, path: r'$.bool'),
            completion(equals(false)),
          );
          await expectLater(client.json.delete(key: key), completes);
          await expectLater(client.json.get(key: key), completion(isNull));
        });
      });
    });
  });
}
