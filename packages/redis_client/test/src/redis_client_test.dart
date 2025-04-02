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
      test(
        'authenticates automatically when credentials are provided',
        () async {
          await expectLater(client.connect(), completes);
          await expectLater(
            client.execute(['PING']),
            completion(equals('PONG')),
          );
        },
      );

      test(
        'throws SocketException when connection times out w/retry',
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
        },
      );

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
        await expectLater(client.auth(password: 'password'), completes);
      });
    });

    group('GET/SET/DEL', () {
      setUp(() async {
        await client.connect();
      });

      tearDown(() async {
        try {
          await client.execute(['FLUSHALL SYNC']);
        } on Exception {
          // ignore
        }
      });

      test('completes', () async {
        const key = 'key';
        const value = 'value';
        const ttl = Duration(seconds: 1);

        await expectLater(client.get(key: key), completion(isNull));
        await expectLater(client.set(key: key, value: value), completes);
        await expectLater(client.get(key: key), completion(equals(value)));

        await expectLater(client.delete(key: key), completes);
        await expectLater(client.get(key: key), completion(isNull));

        await expectLater(client.set(key: key, value: value), completes);
        await expectLater(client.get(key: key), completion(equals(value)));
        await expectLater(client.unlink(key: key), completes);
        await expectLater(client.get(key: key), completion(isNull));
        await expectLater(
          client.set(key: key, value: value, ttl: ttl),
          completes,
        );
        await expectLater(client.get(key: key), completion(equals(value)));
        await Future<void>.delayed(ttl);
        await expectLater(client.get(key: key), completion(isNull));
      });

      test('throws TimeoutException '
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

    group('INCR/INCRBYFLOAT', () {
      setUp(() async {
        await client.connect();
      });

      tearDown(() async {
        try {
          await client.execute(['FLUSHALL SYNC']);
        } on Exception {
          // ignore
        }
      });

      test('completes', () async {
        const key = 'key';
        const value = '10';
        await expectLater(client.increment(key: key), completion(equals(1)));
        await expectLater(client.set(key: key, value: value), completes);
        await expectLater(
          client.incrementBy(key: key, value: 42.2),
          completion(equals(52.2)),
        );
        await expectLater(
          client.incrementBy(key: key, value: -52.2),
          completion(equals(0.0)),
        );
        await expectLater(client.delete(key: key), completes);
      });
    });

    group('MGET/MSET', () {
      final kvPairs = [
        for (var i = 0; i < 10; i++) (key: 'key_$i', value: 'value_$i'),
      ];

      setUp(() async {
        await client.connect();
      });

      tearDown(() async {
        try {
          for (final pair in kvPairs) {
            await expectLater(client.delete(key: pair.key), completes);
          }
          await client.execute(['FLUSHALL SYNC']);
        } on Exception {
          // ignore
        }
      });

      test('completes', () async {
        await expectLater(client.mset(pairs: kvPairs), completes);
        await expectLater(
          client.mget(keys: kvPairs.map((pair) => pair.key).toList()),
          completion(equals(kvPairs.map((pair) => pair.value).toList())),
        );
        await expectLater(
          client.mget(keys: ['foo', 'key_0', 'baz']),
          completion(equals([null, 'value_0', null])),
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
            await client.execute(['FLUSHALL SYNC']);
          } on Exception {
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
                  'arch64': {'url': 'http://example.com'},
                },
              },
            },
          };
          const other = {'qux': 'quux'}; // cspell:disable-line
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
              equals({
                '1.0.0+1': {
                  'android': {
                    'arch64': {'url': 'http://example.com'},
                  },
                },
              }),
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

    group('TimeSeries', () {
      group('CREATE/ADD/GET', () {
        const key = 'sensor';

        setUp(() async {
          await client.connect();
          await expectLater(client.delete(key: key), completes);
        });

        tearDown(() async {
          try {
            await client.execute(['FLUSHALL SYNC']);
          } on Exception {
            // ignore
          }
        });

        test('completes', () async {
          final date = DateTime(2025).toUtc();
          await expectLater(
            client.timeSeries.create(
              key: key,
              chunkSize: 128,
              duplicatePolicy: RedisTimeSeriesDuplicatePolicy.sum,
              encoding: RedisTimeSeriesEncoding.compressed,
              retention: const Duration(days: 30),
              labels: [(label: 'city', value: 'chicago')],
            ),
            completes,
          );
          await expectLater(
            client.timeSeries.get(key: key),
            completion(isNull), // Empty series
          );
          await expectLater(
            client.timeSeries.add(
              key: key,
              timestamp: RedisTimeSeriesTimestamp(date),
              value: 42,
              chunkSize: 128,
              duplicatePolicy: RedisTimeSeriesDuplicatePolicy.sum,
              onDuplicate: RedisTimeSeriesDuplicatePolicy.sum,
              encoding: RedisTimeSeriesEncoding.compressed,
              retention: const Duration(days: 30),
              labels: [(label: 'city', value: 'chicago')],
            ),
            completes,
          );
          await expectLater(
            client.timeSeries.get(key: key),
            completion(equals((timestamp: date, value: 42))),
          );
          await expectLater(
            client.timeSeries.add(
              key: key,
              timestamp: RedisTimeSeriesTimestamp(date),
              value: 42,
              chunkSize: 128,
              duplicatePolicy: RedisTimeSeriesDuplicatePolicy.sum,
              encoding: RedisTimeSeriesEncoding.compressed,
              retention: const Duration(days: 30),
              labels: [(label: 'city', value: 'chicago')],
            ),
            completes,
          );
          await expectLater(
            client.timeSeries.get(key: key),
            completion(equals((timestamp: date, value: 84))),
          );
          await expectLater(
            client.timeSeries.add(
              key: key,
              timestamp:
                  RedisTimeSeriesTimestamp.client.now(), // Use client clock
              value: 56,
            ),
            completes,
          );
          await expectLater(
            client.timeSeries.get(key: key),
            completion(
              isA<({DateTime timestamp, double value})>()
                  .having(
                    (r) => r.timestamp.millisecondsSinceEpoch,
                    'timestamp',
                    closeTo(DateTime.timestamp().millisecondsSinceEpoch, 1000),
                  )
                  .having((r) => r.value, 'value', equals(56)),
            ),
          );
          await expectLater(
            client.timeSeries.add(
              key: key,
              timestamp:
                  RedisTimeSeriesTimestamp.server.now(), // Use server clock
              value: 99,
            ),
            completes,
          );
          await expectLater(
            client.timeSeries.get(key: key),
            completion(
              isA<({DateTime timestamp, double value})>()
                  .having(
                    (r) => r.timestamp.millisecondsSinceEpoch,
                    'timestamp',
                    closeTo(DateTime.timestamp().millisecondsSinceEpoch, 1000),
                  )
                  .having((r) => r.value, 'value', equals(99)),
            ),
          );
          await expectLater(client.delete(key: key), completes);
          await expectLater(
            client.timeSeries.get(key: key),
            throwsA(isA<RedisException>()), // No key exists
          );
        });
      });

      group('RANGE', () {
        const key = 'sensor';
        final data = [
          (timestamp: DateTime(2020).toUtc(), value: 1.0),
          (timestamp: DateTime(2021).toUtc(), value: 2.0),
          (timestamp: DateTime(2022).toUtc(), value: 3.0),
          (timestamp: DateTime(2023).toUtc(), value: 4.0),
        ];

        setUp(() async {
          await client.connect();
          await expectLater(client.delete(key: key), completes);
          for (final tuple in data) {
            await expectLater(
              client.timeSeries.add(
                key: key,
                timestamp: RedisTimeSeriesTimestamp(tuple.timestamp),
                value: tuple.value,
              ),
              completes,
            );
          }
        });

        test('completes', () async {
          await expectLater(
            client.timeSeries.range(
              key: key,
              from: const RedisTimeSeriesFromTimestamp.start(),
              to: const RedisTimeSeriesToTimestamp.end(),
            ),
            completion(containsAllInOrder(data)),
          );

          await expectLater(
            client.timeSeries.range(
              key: key,
              from: const RedisTimeSeriesFromTimestamp.start(),
              to: const RedisTimeSeriesToTimestamp.end(),
              count: 3,
            ),
            completion(containsAllInOrder(data.sublist(0, 2))),
          );

          await expectLater(
            client.timeSeries.range(
              key: key,
              from: const RedisTimeSeriesFromTimestamp.start(),
              to: const RedisTimeSeriesToTimestamp.end(),
              filterByTimestamp: [
                RedisTimeSeriesTimestamp(DateTime(2023).toUtc()),
              ],
            ),
            completion(containsAllInOrder([data.last])),
          );

          await expectLater(
            client.timeSeries.range(
              key: key,
              from: const RedisTimeSeriesFromTimestamp.start(),
              to: const RedisTimeSeriesToTimestamp.end(),
              filterByValue: (min: 0, max: 1),
            ),
            completion(containsAllInOrder(data.sublist(0, 1))),
          );

          await expectLater(
            client.timeSeries.range(
              key: key,
              from: RedisTimeSeriesFromTimestamp(data.first.timestamp),
              to: const RedisTimeSeriesToTimestamp.end(),
              aggregation: const RedisTimeSeriesAggregation(
                aggregator: RedisTimeSeriesAggregator.count,
                bucketDuration: Duration(days: 365 * 3),
              ),
              align: RedisTimeSeriesAlign.start(),
            ),
            completion(
              containsAllInOrder([
                (timestamp: DateTime(2020).toUtc(), value: 3.0),
                (timestamp: DateTime(2022, 12, 31).toUtc(), value: 1.0),
              ]),
            ),
          );
        });
      });
    });
  });
}
