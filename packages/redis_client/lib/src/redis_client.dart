import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:resp_client/resp_client.dart';
import 'package:resp_client/resp_commands.dart';
import 'package:resp_client/resp_server.dart';

/// {@template redis_exception}
/// An exception thrown by the Redis client.
/// {@endtemplate}
class RedisException implements Exception {
  /// {@macro redis_exception}
  const RedisException(this.message);

  /// The message for the exception.
  final String message;

  @override
  String toString() => message;
}

/// {@template redis_socket_options}
/// Options for connecting to a Redis server.
/// {@endtemplate}
class RedisSocketOptions {
  /// {@macro redis_socket_options}
  const RedisSocketOptions({
    this.host = 'localhost',
    this.port = 6379,
    this.username = 'default',
    this.password,
    this.timeout = const Duration(seconds: 30),
    this.retryInterval = const Duration(seconds: 1),
    this.retryAttempts = 10,
  });

  /// The host of the Redis server.
  /// Defaults to localhost.
  final String host;

  /// The port of the Redis server.
  /// Defaults to 6379.
  final int port;

  /// The timeout for connecting to the Redis server.
  /// Defaults to 30 seconds.
  final Duration timeout;

  /// The username for authenticating to the Redis server.
  /// Defaults to 'default'.
  final String username;

  /// The password for authenticating to the Redis server.
  /// Defaults to null.
  final String? password;

  /// The delay between connection attempts.
  /// Defaults to 1 second.
  final Duration retryInterval;

  /// The maximum number of connection attempts.
  /// Defaults to 10.
  final int retryAttempts;
}

/// {@template redis_command_options}
/// Options for sending commands to a Redis server.
/// {@endtemplate}
class RedisCommandOptions {
  /// {@macro redis_command_options}
  const RedisCommandOptions({
    this.timeout = const Duration(seconds: 10),
    this.retryInterval = const Duration(seconds: 1),
    this.retryAttempts = 3,
  });

  /// The timeout for sending commands to the Redis server.
  /// Defaults to 10 seconds.
  final Duration timeout;

  /// The delay between command attempts.
  /// Defaults to 1 second.
  final Duration retryInterval;

  /// The maximum number of command attempts.
  /// Defaults to 3.
  final int retryAttempts;
}

/// {@template redis_logger}
/// A logger for the Redis client.
/// {@endtemplate}
abstract interface class RedisLogger {
  // coverage:ignore-start
  /// {@macro redis_logger}
  const RedisLogger();
  // coverage:ignore-end

  /// Log a debug message.
  void debug(String message);

  /// Log an info message.
  void info(String message);

  /// Log an error message.
  void error(String message, {Object? error, StackTrace? stackTrace});
}

/// {@template redis_client}
/// A client for interacting with a Redis server.
/// {@endtemplate}
class RedisClient {
  /// {@macro redis_client}
  RedisClient({
    RedisSocketOptions socket = const RedisSocketOptions(),
    RedisCommandOptions command = const RedisCommandOptions(),
    RedisLogger logger = const _NoopRedisLogger(),
  }) : _socketOptions = socket,
       _commandOptions = command,
       _logger = logger;

  /// The socket options for the Redis server.
  final RedisSocketOptions _socketOptions;

  /// The command options for the Redis client.
  final RedisCommandOptions _commandOptions;

  /// The underlying connection to the Redis server.
  RespServerConnection? _connection;

  /// The logger for the Redis client.
  final RedisLogger _logger;

  /// The underlying client for interacting with the Redis server.
  RespClient? _client;

  /// Whether the client has been closed.
  var _closed = false;

  /// A completer which completes when the client establishes a connection.
  var _connected = Completer<void>();

  /// Whether the client is connected.
  var _isConnected = false;

  /// A completer which completes when the client disconnects.
  /// Begins in a completed state since the client is initially disconnected.
  var _disconnected = Completer<void>()..complete();

  /// A future which completes when the client establishes a connection.
  Future<void> get _untilConnected => _connected.future;

  /// A future which completes when the client disconnects.
  Future<void> get _untilDisconnected => _disconnected.future;

  /// The Redis JSON commands.
  RedisJson get json => RedisJson._(client: this);

  /// The Redis Time Series commands.
  RedisTimeSeries get timeSeries => RedisTimeSeries._(client: this);

  /// The Redis T-Digest commands.
  RedisTDigest get tdigest => RedisTDigest._(client: this);

  /// Authenticate to the Redis server.
  /// Equivalent to the `AUTH` command.
  /// https://redis.io/commands/auth
  Future<void> auth({required String password, String username = 'default'}) {
    return execute(['AUTH', username, password]);
  }

  /// Returns all keys matching the given pattern.
  /// Equivalent to the `KEYS` command.
  /// https://redis.io/commands/keys
  Future<List<String>> keys({required String pattern}) async {
    final rawResult = await execute(['KEYS', pattern]) as List<RespType>;
    return rawResult
        .whereType<RespBulkString>()
        .map(
          (result) => result.payload,
        )
        .whereType<String>()
        .toList();
  }

  /// Set the value of a key.
  /// Equivalent to the `SET` command.
  /// https://redis.io/commands/set
  ///
  /// If [ttl] is provided, the key will expire after the specified duration.
  Future<void> set({
    required String key,
    required String value,
    Duration? ttl,
  }) {
    return execute([
      'SET',
      key,
      value,
      if (ttl != null) ...['EX', ttl.inSeconds],
    ]);
  }

  /// Sets the given keys to their respective values. MSET replaces existing
  /// values with new values, just as regular SET.
  /// Equivalent to the `MSET` command.
  /// https://redis.io/commands/mset
  Future<void> mset({required List<({String key, String value})> pairs}) async {
    return execute([
      'MSET',
      for (final pair in pairs) ...[pair.key, pair.value],
    ]);
  }

  /// Gets the value of a key.
  /// Returns null if the key does not exist.
  /// Equivalent to the `GET` command.
  /// https://redis.io/commands/get
  Future<String?> get({required String key}) async {
    return await execute(['GET', key]) as String?;
  }

  /// Returns the values of all specified keys.
  /// For every key that does not hold a string value or does not exist, `null`
  /// is returned.
  /// Equivalent to the `MGET` command.
  /// https://redis.io/commands/mget
  Future<List<dynamic>> mget({required List<String> keys}) async {
    final results = await execute(['MGET', ...keys]) as List<RespType>;
    return results.map((result) => result.payload).toList();
  }

  /// Deletes the specified key.
  /// Equivalent to the `DEL` command.
  /// https://redis.io/commands/del
  Future<void> delete({required String key}) => execute(['DEL', key]);

  /// Unlinks the specified key.
  /// Equivalent to the `UNLINK` command.
  /// https://redis.io/commands/unlink
  Future<void> unlink({required String key}) => execute(['UNLINK', key]);

  /// Increment the floating point number stored at key by one.
  /// Returns the newly incremented value.
  /// Equivalent to the `INCR` command.
  /// https://redis.io/commands/incr
  Future<num> increment({required String key}) async {
    return await execute(['INCR', key]) as num;
  }

  /// Increment the floating point number stored at key by the specified value.
  /// Returns the newly incremented value.
  /// Equivalent to the `INCRBYFLOAT` command.
  /// https://redis.io/commands/incrbyfloat
  Future<num> incrementBy({required String key, required num value}) async {
    final result = await execute(['INCRBYFLOAT', key, value]) as String;
    return num.parse(result);
  }

  /// Send a command to the Redis server.
  Future<dynamic> execute(List<Object?> command) async {
    return _runWithRetry(() async {
      final result = await RespCommandsTier0(_client!).execute(command);
      if (result.isError) throw RedisException(result.toString());
      return result.payload;
    }, command: command.join(' '));
  }

  /// Establish a connection to the Redis server.
  /// The delay between connection attempts.
  Future<void> connect() async {
    if (_closed) throw StateError('RedisClient has been closed.');

    unawaited(_reconnect(retryAttempts: _socketOptions.retryAttempts));

    return _untilConnected;
  }

  /// Terminate the connection to the Redis server.
  Future<void> disconnect() async {
    _logger.info('Disconnecting.');
    await _connection?.close();
    _reset();
    await _untilDisconnected;
    _logger.info('Disconnected.');
  }

  /// Terminate the connection to the Redis server and close the client.
  /// After this method is called, the client instance is no longer usable.
  /// Call this method when you are done using the client and/or wish to
  /// prevent reconnection attempts.
  Future<void> close() {
    _logger.info('Closing connection.');
    _closed = true;
    return disconnect();
  }

  Future<void> _reconnect({required int retryAttempts}) async {
    if (retryAttempts <= 0) {
      _connected.completeError(
        const SocketException('Connection retry limit exceeded'),
        StackTrace.current,
      );
      return;
    }

    Future<void> onConnectionOpened(RespServerConnection connection) async {
      _logger.info('Connection opened.');
      _disconnected = Completer<void>();
      _connection = connection;
      _client = RespClient(connection);
      if (_socketOptions.password != null) {
        _logger.info('Authenticating.');
        final username = _socketOptions.username;
        final password = _socketOptions.password!;
        await RespCommandsTier0(_client!).execute(['AUTH', username, password]);
      }
      _isConnected = true;
      if (!_connected.isCompleted) _connected.complete();
      _logger.info('Connected.');
    }

    void onConnectionClosed([Object? error, StackTrace? stackTrace]) {
      if (error == null) {
        _logger.info('Connection closed.');
      } else {
        _logger.error(
          'Connection closed with error.',
          error: error,
          stackTrace: stackTrace,
        );
      }

      if (_closed) return;

      final wasConnected = _isConnected;
      _isConnected = false;

      final retryInterval = _socketOptions.retryInterval;
      final totalAttempts = _socketOptions.retryAttempts;
      final remainingAttempts = wasConnected
          ? totalAttempts
          : retryAttempts - 1;
      final attemptsMade = totalAttempts - remainingAttempts;
      final attemptInfo = attemptsMade > 0
          ? ' ($attemptsMade/$totalAttempts attempts)'
          : '';

      if (wasConnected) _reset();

      _logger.info(
        'Reconnecting in ${retryInterval.inMilliseconds}ms$attemptInfo.',
      );
      Future<void>.delayed(
        retryInterval,
        () => _reconnect(retryAttempts: remainingAttempts),
      );
    }

    try {
      _logger.info('Connecting to ${_socketOptions.connectionUri}.');
      final uri = _socketOptions.connectionUri;
      final connection = await connectSocket(
        uri.host,
        port: uri.port,
        timeout: _socketOptions.timeout,
      );
      unawaited(onConnectionOpened(connection));
      unawaited(
        connection.outputSink.done
            .then((_) => onConnectionClosed())
            .catchError(onConnectionClosed),
      );
    } on Exception catch (error, stackTrace) {
      onConnectionClosed(error, stackTrace);
    }
  }

  void _reset() {
    _connected = Completer<void>();
    _connection = null;
    _client = null;
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  Future<T> _runWithRetry<T>(
    Future<T> Function() fn, {
    required String command,
    int? remainingAttempts,
  }) async {
    if (_closed) throw StateError('RedisClient has been closed.');

    final totalAttempts = _commandOptions.retryAttempts;
    remainingAttempts ??= _commandOptions.retryAttempts;
    final attemptsMade = totalAttempts - remainingAttempts;
    final attemptInfo = attemptsMade > 0
        ? ' ($attemptsMade/$totalAttempts attempts)'
        : '';

    _logger.debug('Executing "$command"$attemptInfo.');

    try {
      return await Future<T>.sync(() async {
        await _untilConnected;
        return fn();
      }).timeout(_commandOptions.timeout);
    } catch (error, stackTrace) {
      if (error is RedisException) rethrow;
      if (remainingAttempts > 0) {
        _logger.error(
          'Command failed to complete. Retrying.',
          error: error,
          stackTrace: stackTrace,
        );
        return _runWithRetry(
          fn,
          command: command,
          remainingAttempts: remainingAttempts - 1,
        );
      }

      _logger.error(
        'Command failed to complete.',
        error: error,
        stackTrace: stackTrace,
      );
      await _connection?.close();
      rethrow;
    }
  }
}

/// {@template redis_json}
/// An object that adds support for getting and setting JSON values.
/// Backed by the RedisJSON module.
/// https://redis.io/docs/data-types/json/
/// {@endtemplate}
class RedisJson {
  const RedisJson._({required RedisClient client}) : _client = client;

  final RedisClient _client;

  /// Set the value of a key.
  /// Equivalent to the `JSON.SET` command.
  /// https://redis.io/commands/json.set
  Future<void> set({
    required String key,
    required dynamic value,
    String path = r'$',
  }) {
    return _client.execute(['JSON.SET', key, path, json.encode(value)]);
  }

  /// Gets the value of a key.
  /// Returns null if the key does not exist.
  /// Equivalent to the `JSON.GET` command.
  /// https://redis.io/commands/json.get
  Future<dynamic> get({required String key, String path = r'$'}) async {
    final result = await _client.execute(['JSON.GET', key, path]);
    if (result is String) {
      final parts = LineSplitter.split(result);
      if (parts.isNotEmpty) {
        final decoded = json.decode(parts.first) as List;
        if (decoded.isNotEmpty) return decoded.first;
      }
    }
    return null;
  }

  /// Deletes the specified key.
  /// Equivalent to the `JSON.DEL` command.
  /// https://redis.io/commands/json.del
  Future<void> delete({required String key, String path = r'$'}) {
    return _client.execute(['JSON.DEL', key, path]);
  }

  /// Merges the value of a key with the specified value.
  /// Equivalent to the `JSON.MERGE` command.
  /// https://redis.io/commands/json.merge
  Future<void> merge({
    required String key,
    required dynamic value,
    String path = r'$',
  }) {
    return _client.execute(['JSON.MERGE', key, path, json.encode(value)]);
  }
}

/// Specifies the series samples encoding format as one of the following values:
/// `compressed` is almost always the right choice. Compression not only saves
/// memory but usually improves performance due to a lower number of memory
/// accesses. It can result in about 90% memory reduction. The exception are
/// highly irregular timestamps or values, which occur rarely.
/// When not specified, the encoding is set to `compressed`.
enum RedisTimeSeriesEncoding {
  /// Applies compression to the series samples
  compressed,

  /// Keeps the raw samples in memory. Adding this flag keeps data in an
  /// uncompressed form
  uncompressed;

  /// Converts the enum to an argument that can be passed directly to
  /// `execute`.
  String toArgument() => name.toUpperCase();
}

/// The policy for handling insertion (TS.ADD and TS.MADD) of multiple samples
/// with identical timestamps.
/// Defaults to `block` when not specified.
enum RedisTimeSeriesDuplicatePolicy {
  /// Ignore any newly reported value and reply with an error
  block,

  /// Ignore any newly reported value
  first,

  /// Override with the newly reported value
  last,

  /// Only override if the value is lower than the existing value
  min,

  /// Only override if the value is higher than the existing value
  max,

  /// If a previous sample exists, add the new sample to it so that the updated
  /// value is equal to (previous + new). If no previous sample exists, set the
  /// updated value equal to the new value.
  sum;

  /// Converts the enum to an argument that can be passed directly to
  /// `execute`.
  String toArgument() => name.toUpperCase();
}

/// {@template redis_time_series_timestamp}
/// is Unix time (integer, in milliseconds) specifying the sample timestamp or *
/// to set the sample timestamp to the Unix time of the server's clock.
///
/// Unix time is the number of milliseconds that have elapsed since 00:00:00 UTC
/// on 1 January 1970, the Unix epoch, without adjustments made due to leap
/// seconds.
/// {@endtemplate}
class RedisTimeSeriesTimestamp {
  /// Create a timestamp from a specific [dateTime].
  ///
  /// See also:
  /// * [client] for creating timestamps using the client clock.
  /// * [server] for creating timestamps using the server clock.
  /// {@macro redis_time_series_timestamp}
  RedisTimeSeriesTimestamp(DateTime dateTime)
    : this._('${dateTime.millisecondsSinceEpoch}');

  const RedisTimeSeriesTimestamp._(this.value);

  /// The client clock.
  /// Useful for creating a timestamp using the client clock.
  /// ```dart
  /// await redis.timeSeries.add(
  ///   key: 'sensor',
  ///   timestamp: RedisTimeSeriesTimestamp.client.now(),
  ///   value: 42,
  /// );
  /// ```
  static const RedisTimeSeriesClock client = RedisTimeSeriesClientClock();

  /// The server clock.
  /// Useful for creating a timestamp using the server clock.
  /// ```dart
  /// await redis.timeSeries.add(
  ///   key: 'sensor',
  ///   timestamp: RedisTimeSeriesTimestamp.server.now(),
  ///   value: 42,
  /// );
  /// ```
  static const RedisTimeSeriesClock server = RedisTimeSeriesServerClock();

  /// The underlying value of the timestamp.
  final String value;
}

/// {@template redis_time_series_clock}
/// An abstract class which represents the clock
/// in the context of a redis time series instance.
/// {@endtemplate}
// ignore: one_member_abstracts
abstract class RedisTimeSeriesClock {
  /// {@macro redis_time_series_clock}
  const RedisTimeSeriesClock();

  /// Returns a timestamp representing the current moment.
  RedisTimeSeriesTimestamp now();
}

/// {@template redis_time_series_server_clock}
/// A [RedisTimeSeriesClock] that represents time on the server.
/// {@endtemplate}
class RedisTimeSeriesServerClock extends RedisTimeSeriesClock {
  /// {@macro redis_time_series_server_clock}
  const RedisTimeSeriesServerClock();
  @override
  RedisTimeSeriesTimestamp now() => const RedisTimeSeriesTimestamp._('*');
}

/// {@template redis_time_series_client_clock}
/// A [RedisTimeSeriesClock] that represents time on the client.
/// {@endtemplate}
class RedisTimeSeriesClientClock extends RedisTimeSeriesClock {
  /// {@macro redis_time_series_client_clock}
  const RedisTimeSeriesClientClock();
  @override
  RedisTimeSeriesTimestamp now() {
    return RedisTimeSeriesTimestamp(DateTime.timestamp());
  }
}

/// {@template redis_time_series_from_timestamp}
/// The start timestamp for the range query (integer Unix timestamp in
/// milliseconds).
/// {@endtemplate}
class RedisTimeSeriesFromTimestamp {
  /// {@macro redis_time_series_from_timestamp}
  RedisTimeSeriesFromTimestamp(DateTime dateTime)
    : this._('${dateTime.millisecondsSinceEpoch}');

  /// The timestamp of the earliest sample among all the time series
  /// that passes the provided filter.
  const RedisTimeSeriesFromTimestamp.start() : value = '-';

  const RedisTimeSeriesFromTimestamp._(this.value);

  /// The underlying value of the timestamp.
  final String value;
}

/// {@template redis_time_series_to_timestamp}
/// The end timestamp for the range query (integer Unix timestamp in
/// milliseconds).
/// {@endtemplate}
class RedisTimeSeriesToTimestamp {
  /// {@macro redis_time_series_to_timestamp}
  RedisTimeSeriesToTimestamp(DateTime dateTime)
    : this._('${dateTime.millisecondsSinceEpoch}');

  /// The timestamp of the latest sample among all the time series that passes
  /// the provided filter.
  const RedisTimeSeriesToTimestamp.end() : value = '+';

  const RedisTimeSeriesToTimestamp._(this.value);

  /// The underlying value of the timestamp.
  final String value;
}

/// {@template redis_time_series_align}
/// The time bucket alignment control for AGGREGATION. It controls the time
/// bucket timestamps by changing the reference timestamp on which a bucket is
/// defined.
/// {@endtemplate}
class RedisTimeSeriesAlign {
  /// A specific timestamp: align the reference timestamp to a specific time.
  RedisTimeSeriesAlign(DateTime date)
    : this._('${date.millisecondsSinceEpoch}');

  /// The reference timestamp will be the query start interval time
  /// (fromTimestamp) which can't be -.
  RedisTimeSeriesAlign.start() : this._('-');

  /// The reference timestamp will be the query end interval time (toTimestamp)
  /// which can't be +.
  RedisTimeSeriesAlign.end() : this._('+');

  RedisTimeSeriesAlign._(this.value);

  /// The underlying value of the alignment.
  final String value;
}

/// The supported aggregation types.
enum RedisTimeSeriesAggregator {
  /// Arithmetic mean of all values
  average,

  /// Sum of all values
  sum,

  /// Minimum value
  min,

  /// Maximum value
  max,

  /// Difference between the maximum and the minimum value
  range,

  /// Number of values
  count,

  /// Value with lowest timestamp in the bucket
  first,

  /// Value with highest timestamp in the bucket
  last,

  /// Population standard deviation of the values
  populationStandardDeviation,

  /// Sample standard deviation of the values
  sampleStandardDeviation,

  /// Population variance of the values
  populationVariance,

  /// Sample variance of the values
  sampleVariance,

  /// Time-weighted average over the bucket's time frame
  timeWeightedAverage;

  /// Converts the enum to an argument that can be passed directly to
  /// `execute`.
  String toArgument() {
    return switch (this) {
      RedisTimeSeriesAggregator.average => 'avg',
      RedisTimeSeriesAggregator.sum => 'sum',
      RedisTimeSeriesAggregator.min => 'min',
      RedisTimeSeriesAggregator.max => 'max',
      RedisTimeSeriesAggregator.range => 'range',
      RedisTimeSeriesAggregator.count => 'count',
      RedisTimeSeriesAggregator.first => 'first',
      RedisTimeSeriesAggregator.last => 'last',
      RedisTimeSeriesAggregator.populationStandardDeviation => 'std.p',
      RedisTimeSeriesAggregator.sampleStandardDeviation => 'std.s',
      RedisTimeSeriesAggregator.populationVariance => 'var.p',
      RedisTimeSeriesAggregator.sampleVariance => 'var.s',
      RedisTimeSeriesAggregator.timeWeightedAverage => 'twa',
    };
  }
}

/// {@template redis_time_series_aggregation}
/// Aggregates time series samples into time buckets.
/// {@endtemplate}
class RedisTimeSeriesAggregation {
  /// {@macro redis_time_series_aggregation}
  const RedisTimeSeriesAggregation({
    required this.aggregator,
    required this.bucketDuration,
  });

  /// The aggregation type.
  final RedisTimeSeriesAggregator aggregator;

  /// The duration of each bucket.
  final Duration bucketDuration;
}

/// {@template redis_time_series}
/// An object that adds support for storing and querying timestamped data
/// points.
/// Backed by the RedisTimeSeries module.
/// https://redis.io/docs/latest/develop/data-types/timeseries/
/// {@endtemplate}
class RedisTimeSeries {
  const RedisTimeSeries._({required RedisClient client}) : _client = client;

  final RedisClient _client;

  /// Create a new time series.
  /// Equivalent to the `TS.CREATE` command.
  /// https://redis.io/commands/ts.create
  Future<void> create({
    required String key,
    Duration? retention,
    RedisTimeSeriesEncoding? encoding,
    int? chunkSize,
    RedisTimeSeriesDuplicatePolicy? duplicatePolicy,
    List<({String label, String value})>? labels,
  }) {
    return _client.execute([
      'TS.CREATE',
      key,
      if (retention != null) ...['RETENTION', retention.inMilliseconds],
      if (encoding != null) ...['ENCODING', encoding.toArgument()],
      if (chunkSize != null) ...['CHUNK_SIZE', chunkSize],
      if (duplicatePolicy != null) ...[
        'DUPLICATE_POLICY',
        duplicatePolicy.toArgument(),
      ],
      if (labels != null) ...[
        'LABELS',
        for (final label in labels) ...[label.label, label.value],
      ],
    ]);
  }

  /// Append a sample to a time series.
  /// Equivalent to the `TS.ADD` command.
  /// Note: When the specified key does not exist, a new time series is created.
  /// https://redis.io/commands/ts.add
  Future<void> add({
    required String key,
    required RedisTimeSeriesTimestamp timestamp,
    required double value,
    Duration? retention,
    RedisTimeSeriesEncoding? encoding,
    int? chunkSize,
    RedisTimeSeriesDuplicatePolicy? duplicatePolicy,
    RedisTimeSeriesDuplicatePolicy? onDuplicate,
    List<({String label, String value})>? labels,
  }) {
    return _client.execute([
      'TS.ADD',
      key,
      timestamp.value,
      value,
      if (retention != null) ...['RETENTION', retention.inMilliseconds],
      if (encoding != null) ...['ENCODING', encoding.toArgument()],
      if (chunkSize != null) ...['CHUNK_SIZE', chunkSize],
      if (duplicatePolicy != null) ...[
        'DUPLICATE_POLICY',
        duplicatePolicy.toArgument(),
      ],
      if (onDuplicate != null) ...['ON_DUPLICATE', onDuplicate.toArgument()],
      if (labels != null) ...[
        'LABELS',
        for (final label in labels) ...[label.label, label.value],
      ],
    ]);
  }

  /// Get the sample with the highest timestamp from a given time series.
  /// Equivalent to the `TS.GET` command.
  /// Returns a timestamp, value pair of the sample with the highest timestamp.
  /// Throws a [RedisException] if the key does not exist.
  /// Returns null if the time series is empty.
  /// The returned timestamp will always be UTC.
  /// https://redis.io/commands/ts.get
  Future<({DateTime timestamp, double value})?> get({
    required String key,
  }) async {
    final result = await _client.execute(['TS.GET', key]) as List<RespType>;
    if (result.isEmpty) return null;
    final timestamp = result[0] as RespInteger;
    final value = result[1] as RespSimpleString;
    return (
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestamp.payload,
        isUtc: true,
      ),
      value: double.parse(value.payload),
    );
  }

  /// Query a range in forward direction.
  /// Equivalent to the `TS.RANGE` command.
  /// https://redis.io/commands/ts.range
  Future<List<({DateTime timestamp, double value})>> range({
    required String key,
    required RedisTimeSeriesFromTimestamp from,
    required RedisTimeSeriesToTimestamp to,
    List<RedisTimeSeriesTimestamp>? filterByTimestamp,
    ({double min, double max})? filterByValue,
    int? count,
    RedisTimeSeriesAlign? align,
    RedisTimeSeriesAggregation? aggregation,
  }) async {
    final results =
        await _client.execute([
              'TS.RANGE',
              key,
              from.value,
              to.value,
              if (filterByTimestamp != null) ...[
                'FILTER_BY_TS',
                ...filterByTimestamp.map((t) => t.value),
              ],
              if (filterByValue != null) ...[
                'FILTER_BY_VALUE',
                filterByValue.min,
                filterByValue.max,
              ],
              if (count != null) ...['COUNT', count],
              if (align != null) ...['ALIGN', align.value],
              if (aggregation != null) ...[
                'AGGREGATION',
                aggregation.aggregator.toArgument(),
                aggregation.bucketDuration.inMilliseconds,
              ],
            ])
            as List<RespType>;
    return results.map((result) {
      final payload = result.payload as List<RespType>;
      final timestamp = payload[0] as RespInteger;
      final value = payload[1] as RespSimpleString;
      return (
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          timestamp.payload,
          isUtc: true,
        ),
        value: double.parse(value.payload),
      );
    }).toList();
  }
}

/// {@template redis_t_digest}
/// A client for interacting with the Redis T-Digest data type.
/// See https://redis.io/docs/latest/develop/data-types/probabilistic/t-digest
/// {@endtemplate}
class RedisTDigest {
  /// {@macro redis_t_digest}
  const RedisTDigest._({required RedisClient client}) : _client = client;

  final RedisClient _client;

  /// Create a new T-Digest.
  /// Equivalent to the `TDIGEST.CREATE` command.
  /// https://redis.io/commands/tdigest.create
  Future<void> create({required String key, required int compression}) {
    return _client.execute(['TDIGEST.CREATE', key, 'COMPRESSION', compression]);
  }

  /// Add one or more [observations] to the T-Digest specified by [key].
  /// Equivalent to the `TDIGEST.ADD` command.
  /// https://redis.io/commands/tdigest.add
  Future<void> add({
    required String key,
    required List<double> observations,
  }) {
    return _client.execute([
      'TDIGEST.ADD',
      key,
      ...observations.map((observation) => observation.toString()),
    ]);
  }

  /// Reset the T-Digest specified by [key].
  /// Equivalent to the `TDIGEST.RESET` command.
  /// https://redis.io/commands/tdigest.reset
  Future<void> reset({required String key}) {
    return _client.execute(['TDIGEST.RESET', key]);
  }

  /// Compute the [quantiles] of the T-Digest specified by [key].
  /// Returns a list of [quantiles] in the same order as the [quantiles] list.
  /// If the T-Digest is empty, the returned list will contain `null` values.
  /// Equivalent to the `TDIGEST.QUANTILE` command.
  /// https://redis.io/commands/tdigest.quantile
  Future<List<double?>> quantile({
    required String key,
    required List<double> quantiles,
  }) async {
    final results =
        await _client.execute([
              'TDIGEST.QUANTILE',
              key,
              ...quantiles.map((quantile) => quantile.toString()),
            ])
            as List<RespType>;

    return results.map((result) {
      if (result is RespBulkString && result.payload != null) {
        return double.tryParse(result.payload!);
      }
      return null;
    }).toList();
  }
}

extension on RedisSocketOptions {
  /// The connection URI for the Redis server derived from the socket options.
  Uri get connectionUri => Uri.parse('redis://$host:$port');
}

final class _NoopRedisLogger implements RedisLogger {
  const _NoopRedisLogger();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}
}
