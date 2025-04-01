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

  /// Authenticate to the Redis server.
  /// Equivalent to the `AUTH` command.
  /// https://redis.io/commands/auth
  Future<void> auth({required String password, String username = 'default'}) {
    return execute(['AUTH', username, password]);
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
      final remainingAttempts =
          wasConnected ? totalAttempts : retryAttempts - 1;
      final attemptsMade = totalAttempts - remainingAttempts;
      final attemptInfo =
          attemptsMade > 0 ? ' ($attemptsMade/$totalAttempts attempts)' : '';

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
    final attemptInfo =
        attemptsMade > 0 ? ' ($attemptsMade/$totalAttempts attempts)' : '';

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
  RedisJson._({required RedisClient client}) : _client = client;

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

/// {@template redis_time_series}
/// An object that adds support for storing and querying timestamped data
/// points.
/// Backed by the RedisTimeSeries module.
/// https://redis.io/docs/latest/develop/data-types/timeseries/
/// {@endtemplate}
class RedisTimeSeries {
  RedisTimeSeries._({required RedisClient client}) : _client = client;

  final RedisClient _client;

  /// Create a new time series.
  /// Equivalent to the `TS.CREATE` command.
  Future<void> create({
    required String key,
    Duration? retention,
    RedisTimeSeriesEncoding? encoding,
    int? chunkSize,
    RedisTimeSeriesDuplicatePolicy? duplicatePolicy,
    List<({String label, String value})>? labels,
  }) async {
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
