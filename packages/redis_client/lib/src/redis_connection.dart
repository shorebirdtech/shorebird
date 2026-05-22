part of 'redis_client.dart';

/// {@template redis_connection}
/// A single transport-level connection to a Redis server.
///
/// Owns the socket lifecycle: opening, authenticating, reconnect-on-drop,
/// and graceful close. Commands sent through [execute] wait for the socket
/// to be ready before being written to the wire.
///
/// This type is internal to the package today and is not exported. A future
/// release will expose it so callers can pin a connection for transactions
/// and pipelining.
/// {@endtemplate}
class RedisConnection {
  /// {@macro redis_connection}
  RedisConnection({required this.options, required this.logger});

  /// The socket-level options used to dial and re-dial the server.
  final RedisSocketOptions options;

  /// The logger used for connection-lifecycle events.
  final RedisLogger logger;

  /// The underlying connection to the Redis server.
  RespServerConnection? _connection;

  /// The underlying RESP client for the active connection.
  RespClient? _client;

  /// Whether the connection has been permanently closed.
  var _closed = false;

  /// A completer which completes when the socket is established.
  var _connected = Completer<void>();

  /// Whether the socket is currently established.
  var _isConnected = false;

  /// A completer which completes when the socket is torn down.
  /// Begins in a completed state since the connection is initially down.
  var _disconnected = Completer<void>()..complete();

  /// A future which completes when the socket is established.
  Future<void> get _untilConnected => _connected.future;

  /// A future which completes when the socket is torn down.
  Future<void> get _untilDisconnected => _disconnected.future;

  /// Whether [close] has been called. After this returns true the connection
  /// is no longer usable.
  bool get isClosed => _closed;

  /// Open the socket. Returns once the connection is established.
  Future<void> connect() async {
    if (_closed) throw StateError('RedisClient has been closed.');

    unawaited(_reconnect(retryAttempts: options.retryAttempts));

    return _untilConnected;
  }

  /// Tear down the current socket without closing the connection logically.
  /// The reconnect loop will recreate the socket on subsequent use unless
  /// [close] has been called.
  Future<void> disconnect() async {
    logger.info('Disconnecting.');
    await _connection?.close();
    _reset();
    await _untilDisconnected;
    logger.info('Disconnected.');
  }

  /// Permanently close the connection. After this method is called, the
  /// instance is not usable.
  Future<void> close() {
    logger.info('Closing connection.');
    _closed = true;
    return disconnect();
  }

  /// Send a single command to the server. Waits for the socket to be ready
  /// before writing. Throws [RedisException] on a server-side error reply.
  /// Throws [StateError] if the connection has been closed.
  Future<dynamic> execute(List<Object?> command) async {
    if (_closed) throw StateError('RedisClient has been closed.');
    await _untilConnected;
    final result = await RespCommandsTier0(_client!).execute(command);
    if (result.isError) throw RedisException(result.toString());
    return result.payload;
  }

  /// Close the underlying socket without closing the connection logically.
  /// The reconnect loop will recreate the socket on next [execute].
  ///
  /// Used by [RedisClient]'s retry policy to recover from a wedged socket
  /// after the retry budget is exhausted.
  Future<void> recycle() async {
    await _connection?.close();
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
      logger.info('Connection opened.');
      _disconnected = Completer<void>();
      _connection = connection;
      _client = RespClient(connection);
      if (options.password != null) {
        logger.info('Authenticating.');
        final username = options.username;
        final password = options.password!;
        await RespCommandsTier0(_client!).execute(['AUTH', username, password]);
      }
      _isConnected = true;
      if (!_connected.isCompleted) _connected.complete();
      logger.info('Connected.');
    }

    void onConnectionClosed([Object? error, StackTrace? stackTrace]) {
      if (error == null) {
        logger.info('Connection closed.');
      } else {
        logger.error(
          'Connection closed with error.',
          error: error,
          stackTrace: stackTrace,
        );
      }

      if (_closed) return;

      final wasConnected = _isConnected;
      _isConnected = false;

      final retryInterval = options.retryInterval;
      final totalAttempts = options.retryAttempts;
      final remainingAttempts = wasConnected
          ? totalAttempts
          : retryAttempts - 1;
      final attemptsMade = totalAttempts - remainingAttempts;
      final attemptInfo = attemptsMade > 0
          ? ' ($attemptsMade/$totalAttempts attempts)'
          : '';

      if (wasConnected) _reset();

      logger.info(
        'Reconnecting in ${retryInterval.inMilliseconds}ms$attemptInfo.',
      );
      Future<void>.delayed(
        retryInterval,
        () => _reconnect(retryAttempts: remainingAttempts),
      );
    }

    try {
      logger.info('Connecting to ${options._connectionUri}.');
      final uri = options._connectionUri;
      final connection = await connectSocket(
        uri.host,
        port: uri.port,
        timeout: options.timeout,
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
}

extension on RedisSocketOptions {
  /// The connection URI for the Redis server derived from the socket options.
  Uri get _connectionUri => Uri.parse('redis://$host:$port');
}
