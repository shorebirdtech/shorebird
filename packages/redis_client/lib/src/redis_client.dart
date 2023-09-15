import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:resp_client/resp_client.dart';
import 'package:resp_client/resp_commands.dart';
import 'package:resp_client/resp_server.dart';

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
abstract class RedisLogger {
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

final class _NoopRedisLogger implements RedisLogger {
  const _NoopRedisLogger();
  @override
  void debug(String message) {}

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message) {}
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
  })  : _socketOptions = socket,
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

  /// Authenticate to the Redis server.
  /// Returns true if successful, otherwise false.
  /// Equivalent to the `AUTH` command.
  /// https://redis.io/commands/auth
  Future<bool> auth({
    required String password,
    String username = 'default',
  }) async {
    final result = await sendCommand(['AUTH', username, password]);
    if (result is RespSimpleString) return result.payload == 'OK';
    return false;
  }

  /// Set the value of a key.
  /// Equivalent to the `SET` command.
  /// https://redis.io/commands/set
  Future<void> set({required String key, required String value}) {
    _logger.debug('Executing SET command for key: $key, value: $value');
    return _exec(() => RespCommandsTier2(_client!).set(key, value));
  }

  /// Gets the value of a key.
  /// Returns null if the key does not exist.
  /// Equivalent to the `GET` command.
  /// https://redis.io/commands/get
  Future<String?> get({required String key}) {
    _logger.debug('Executing GET command for key: $key');
    return _exec(() => RespCommandsTier2(_client!).get(key));
  }

  /// Deletes the specified key.
  /// Equivalent to the `DEL` command.
  /// https://redis.io/commands/del
  Future<void> delete({required String key}) {
    _logger.debug('Executing DEL command for key: $key');
    return _exec(() => RespCommandsTier2(_client!).del([key]));
  }

  /// Send a command to the Redis server.
  Future<RespType<dynamic>?> sendCommand(List<Object?> command) async {
    _logger.debug('Executing $command');
    return _exec(() => RespCommandsTier0(_client!).execute(command));
  }

  /// Establish a connection to the Redis server.
  /// The delay between connection attempts.
  Future<void> connect() async {
    if (_closed) throw StateError('RedisClient has been closed.');

    unawaited(
      _reconnect(
        retryInterval: _socketOptions.retryInterval,
        retryAttempts: _socketOptions.retryAttempts,
      ),
    );

    return _untilConnected;
  }

  /// Terminate the connection to the Redis server.
  Future<void> disconnect() {
    _logger.info('Disconnecting.');
    _connection?.close();
    _reset();
    return _untilDisconnected;
  }

  /// Terminate the connection to the Redis server and close the client.
  /// After this method is called, the client instance is no longer usable.
  /// Call this method when you are done using the client and/or wish to
  /// prevent reconnection attempts.
  Future<void> close() {
    _logger.info('Closing connection permanently.');
    _closed = true;
    return disconnect();
  }

  Future<void> _reconnect({
    required Duration retryInterval,
    required int retryAttempts,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (_closed) {
      _logger.info('Connection closed permanently.');
      return;
    }

    if (retryAttempts <= 0) {
      _connected.completeError(
        error ?? const SocketException('Connection retry limit exceeded'),
        stackTrace,
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
      _logger.info('Ready.');
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

      final wasConnected = _isConnected;
      _isConnected = false;
      final remainingAttempts =
          wasConnected ? _socketOptions.retryAttempts : retryAttempts - 1;

      if (wasConnected) _reset();

      _logger.info(
        '''Reconnecting in $retryInterval ($remainingAttempts attempts remaining).''',
      );
      Future<void>.delayed(retryInterval, () {
        _reconnect(
          retryInterval: retryInterval,
          retryAttempts: remainingAttempts,
          error: error,
          stackTrace: stackTrace,
        );
      });
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
    } catch (error, stackTrace) {
      onConnectionClosed(error, stackTrace);
    }
  }

  void _reset() {
    _logger.info('Resetting connection.');
    _connected = Completer<void>();
    _connection = null;
    _client = null;
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  Future<T> _exec<T>(
    Future<T> Function() fn, {
    int? remainingAttempts,
  }) async {
    remainingAttempts ??= _commandOptions.retryAttempts;
    _logger.debug('Executing command ($remainingAttempts attempts remaining).');

    if (_closed) throw StateError('RedisClient has been closed.');

    await _untilConnected;

    try {
      return await Future<T>.sync(fn).timeout(_commandOptions.timeout);
    } catch (error, stackTrace) {
      if (remainingAttempts > 0) {
        _logger.error(
          'Command failed to complete. Retrying.',
          error: error,
          stackTrace: stackTrace,
        );
        return _exec(fn, remainingAttempts: remainingAttempts - 1);
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
    required Map<String, dynamic> value,
  }) {
    _client._logger.debug(
      'Executing JSON.SET command for key: $key, value: $value',
    );
    return _client.sendCommand(['JSON.SET', key, r'$', json.encode(value)]);
  }

  /// Gets the value of a key.
  /// Returns null if the key does not exist.
  /// Equivalent to the `JSON.GET` command.
  /// https://redis.io/commands/json.get
  Future<Map<String, dynamic>?> get({required String key}) async {
    _client._logger.debug('Executing JSON.GET command for key: $key');
    final result = await _client.sendCommand([
      'JSON.GET',
      key,
      r'$',
    ]);
    if (result is RespBulkString) {
      final parts = LineSplitter.split(result.payload ?? '');
      if (parts.isNotEmpty) {
        final decoded = json.decode(parts.first) as List;
        if (decoded.isNotEmpty) return decoded.first as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// Deletes the specified key.
  /// Equivalent to the `JSON.DEL` command.
  /// https://redis.io/commands/json.del
  Future<void> delete({required String key}) {
    _client._logger.debug('Executing JSON.DEL command for key: $key');
    return _client.sendCommand(['JSON.DEL', key, r'$']);
  }
}

extension on RedisSocketOptions {
  /// The connection URI for the Redis server derived from the socket options.
  Uri get connectionUri => Uri.parse('redis://$host:$port');
}
