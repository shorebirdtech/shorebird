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
    this.timeout = const Duration(seconds: 30),
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
}

/// {@template redis_command_options}
/// Options for sending commands to a Redis server.
/// {@endtemplate}
class RedisCommandOptions {
  /// {@macro redis_command_options}
  const RedisCommandOptions({
    this.timeout = const Duration(seconds: 10),
  });

  /// The timeout for sending commands to the Redis server.
  /// Defaults to 10 seconds.
  final Duration timeout;
}

/// {@template redis_client}
/// A client for interacting with a Redis server.
/// {@endtemplate}
class RedisClient {
  /// {@macro redis_client}
  RedisClient({
    RedisSocketOptions socket = const RedisSocketOptions(),
    RedisCommandOptions command = const RedisCommandOptions(),
  })  : _socketOptions = socket,
        _commandOptions = command;

  /// The socket options for the Redis server.
  final RedisSocketOptions _socketOptions;

  /// The command options for the Redis client.
  final RedisCommandOptions _commandOptions;

  /// The underlying connection to the Redis server.
  RespServerConnection? _connection;

  /// The underlying client for interacting with the Redis server.
  RespClient? _client;

  /// Whether the client has been closed.
  var _closed = false;

  /// A completer which completes when the client establishes a connection.
  var _connected = Completer<void>();

  /// A completer which completes when the client disconnects.
  /// Begins in a completed state since the client is initially disconnected.
  var _disconnected = Completer<void>()..complete();

  /// A future which completes when the client establishes a connection.
  Future<void> get connected => _connected.future;

  /// A future which completes when the client disconnects.
  Future<void> get disconnected => _disconnected.future;

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
    final result = await _exec(
      () => sendCommand(['AUTH', username, password]),
    );
    if (result is RespSimpleString) return result.payload == 'OK';
    return false;
  }

  /// Set the value of a key.
  /// Equivalent to the `SET` command.
  /// https://redis.io/commands/set
  Future<void> set({required String key, required String value}) {
    return _exec(() => RespCommandsTier2(_client!).set(key, value));
  }

  /// Gets the value of a key.
  /// Returns null if the key does not exist.
  /// Equivalent to the `GET` command.
  /// https://redis.io/commands/get
  Future<String?> get({required String key}) {
    return _exec(() => RespCommandsTier2(_client!).get(key));
  }

  /// Deletes the specified key.
  /// Equivalent to the `DEL` command.
  /// https://redis.io/commands/del
  Future<void> delete({required String key}) {
    return _exec(() => RespCommandsTier2(_client!).del([key]));
  }

  /// Send a command to the Redis server.
  Future<RespType<dynamic>> sendCommand(List<Object?> command) async {
    return _exec(() => RespCommandsTier0(_client!).execute(command));
  }

  /// Establish a connection to the Redis server.
  /// The delay between connection attempts.
  Future<void> connect({
    Duration connectionRetryDelay = const Duration(milliseconds: 100),
    int maxConnectionAttempts = 100,
  }) async {
    if (_closed) throw StateError('RedisClient has been closed.');

    unawaited(
      _reconnect(
        connectionRetryDelay: connectionRetryDelay,
        remainingConnectionAttempts: maxConnectionAttempts,
      ),
    );

    return connected;
  }

  /// Terminate the connection to the Redis server.
  Future<void> disconnect() {
    _connection?.close();
    _reset();
    return disconnected;
  }

  /// Terminate the connection to the Redis server and close the client.
  /// After this method is called, the client instance is no longer usable.
  /// Call this method when you are done using the client and/or wish to
  /// prevent reconnection attempts.
  Future<void> close() {
    _closed = true;
    return disconnect();
  }

  Future<void> _reconnect({
    required Duration connectionRetryDelay,
    required int remainingConnectionAttempts,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (_closed) return;

    if (remainingConnectionAttempts <= 0) {
      _connected.completeError(
        error ?? const SocketException('Connection retry limit exceeded'),
        stackTrace,
      );
      return;
    }

    void onConnectionOpened(RespServerConnection connection) {
      _disconnected = Completer<void>();
      _connection = connection;
      _client = RespClient(connection);
      _connected.complete();
    }

    void onConnectionClosed([Object? error, StackTrace? stackTrace]) {
      _reset();
      _reconnect(
        connectionRetryDelay: connectionRetryDelay,
        remainingConnectionAttempts: remainingConnectionAttempts - 1,
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      final uri = _socketOptions.connectionUri;
      final connection = await connectSocket(
        uri.host,
        port: uri.port,
        timeout: _socketOptions.timeout,
      );

      onConnectionOpened(connection);

      unawaited(
        connection.outputSink.done
            .then((_) => onConnectionClosed())
            .catchError(onConnectionClosed),
      );
    } catch (error, stackTrace) {
      Future<void>.delayed(
        connectionRetryDelay,
        () => _reconnect(
          connectionRetryDelay: connectionRetryDelay,
          remainingConnectionAttempts: remainingConnectionAttempts - 1,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _reset() {
    _connected = Completer<void>();
    _connection = null;
    _client = null;
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  Future<T> _exec<T>(FutureOr<T> Function() fn) async {
    if (_closed) throw StateError('RedisClient has been closed.');
    await connected;
    return Future<T>.sync(fn).timeout(
      _commandOptions.timeout,
      onTimeout: () {
        _connection?.close();
        throw const SocketException('Connection timed out');
      },
    );
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
    return _client.sendCommand(['JSON.SET', key, r'$', json.encode(value)]);
  }

  /// Gets the value of a key.
  /// Returns null if the key does not exist.
  /// Equivalent to the `JSON.GET` command.
  /// https://redis.io/commands/json.get
  Future<Map<String, dynamic>?> get({required String key}) async {
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
    return _client.sendCommand(['JSON.DEL', key, r'$']);
  }
}

extension on RedisSocketOptions {
  /// The connection URI for the Redis server derived from the socket options.
  Uri get connectionUri => Uri.parse('redis://$host:$port');
}
