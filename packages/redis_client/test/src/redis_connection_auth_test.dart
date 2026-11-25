// cspell:words newkey keyout Acreateserial extfile
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shorebird_redis_client/shorebird_redis_client.dart';
import 'package:test/test.dart';

/// A minimal in-process RESP server: replies `+OK` to `AUTH` (or the reply
/// [authReply] chooses) and `+PONG` to `PING`, and records every `AUTH`.
///
/// Hermetic, so these tests need no Redis and no TLS-enabled Redis, and can
/// drop a connection on demand to exercise reconnects.
class _FakeRedisServer {
  _FakeRedisServer._(this._server);

  static Future<_FakeRedisServer> plain() async => _FakeRedisServer._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  static Future<_FakeRedisServer> secure(SecurityContext context) async =>
      _FakeRedisServer._(
        await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context),
      );

  final Stream<Socket> _server;
  final auths = <List<String>>[];
  final _sockets = <Socket>[];
  String Function(List<String> auth) authReply = (_) => '+OK\r\n';
  final handshakeErrors = <Object>[];

  int get port => switch (_server) {
    final ServerSocket s => s.port,
    final SecureServerSocket s => s.port,
    _ => throw StateError('unreachable'),
  };

  void start() {
    _server.listen(
      (socket) {
        _sockets.add(socket);
        final buffer = <int>[];
        socket.listen((data) {
          buffer.addAll(data);
          List<String>? command;
          while ((command = _takeCommand(buffer)) != null) {
            final name = command![0].toUpperCase();
            if (name == 'AUTH') {
              auths.add(command.sublist(1));
              socket.write(authReply(command.sublist(1)));
            } else if (name == 'PING') {
              socket.write('+PONG\r\n');
            } else {
              socket.write('-ERR unknown command\r\n');
            }
          }
        }, onError: (_) {});
      },
      onError: handshakeErrors.add,
    );
  }

  /// Drops every open client connection, as a server restart would.
  ///
  /// Closes with a FIN before destroying, so the client sees an orderly
  /// close rather than, on macOS, an RST from [Socket.destroy]. Resets have
  /// their own tests, through [_ResetProxy].
  Future<void> dropClients() async {
    final sockets = List.of(_sockets);
    _sockets.clear();
    for (final socket in sockets) {
      await socket.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      socket.destroy();
    }
  }

  Future<void> close() async {
    await dropClients();
    switch (_server) {
      case final ServerSocket s:
        await s.close();
      case final SecureServerSocket s:
        await s.close();
    }
  }

  /// Parses one RESP array of bulk strings off the front of [buffer].
  static List<String>? _takeCommand(List<int> buffer) {
    // resp_client ends each command with an extra CRLF, which Redis skips as
    // an empty inline command.
    while (buffer.length >= 2 && buffer[0] == 13 && buffer[1] == 10) {
      buffer.removeRange(0, 2);
    }
    final text = latin1.decode(buffer);
    if (!text.startsWith('*')) return null;
    var index = text.indexOf('\r\n');
    if (index < 0) return null;
    final count = int.parse(text.substring(1, index));
    var cursor = index + 2;
    final parts = <String>[];
    for (var i = 0; i < count; i++) {
      index = text.indexOf('\r\n', cursor);
      if (index < 0) return null;
      final length = int.parse(text.substring(cursor + 1, index));
      final start = index + 2;
      if (text.length < start + length + 2) return null;
      parts.add(text.substring(start, start + length));
      cursor = start + length + 2;
    }
    buffer.removeRange(0, cursor);
    return parts;
  }
}

/// Throwaway CA and server certificates, generated with `openssl` so no
/// private key is committed.
class _Pki {
  _Pki(this.dir);

  final Directory dir;

  String path(String name) => '${dir.path}/$name';

  static Future<_Pki> generate() async {
    final pki = _Pki(await Directory.systemTemp.createTemp('redis_tls_'));
    Future<void> openssl(List<String> args) async {
      final result = await Process.run(
        'openssl',
        args,
        workingDirectory: pki.dir.path,
      );
      if (result.exitCode != 0) {
        throw StateError('openssl ${args.join(' ')}: ${result.stderr}');
      }
    }

    for (final ca in ['ca', 'other_ca']) {
      await openssl([
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', //
        '-keyout', '$ca.key', '-out', '$ca.pem', '-subj', '/CN=$ca',
      ]);
    }
    await openssl([
      'req', '-newkey', 'rsa:2048', '-nodes', //
      '-keyout', 'server.key', '-out', 'server.csr', '-subj', '/CN=server',
    ]);
    // macOS refuses a TLS server certificate without the serverAuth EKU.
    File(pki.path('san.cnf')).writeAsStringSync(
      'subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n',
    );
    await openssl([
      'x509', '-req', '-in', 'server.csr', '-CA', 'ca.pem', //
      '-CAkey', 'ca.key', '-CAcreateserial', '-days', '2',
      '-out', 'server.pem', '-extfile', 'san.cnf',
    ]);
    return pki;
  }

  SecurityContext serverContext() => SecurityContext()
    ..useCertificateChain(path('server.pem'))
    ..usePrivateKey(path('server.key'));

  SecurityContext clientTrusting(String ca) =>
      // The default context trusts no roots, so only [ca] can satisfy it.
      SecurityContext()..setTrustedCertificates(path('$ca.pem'));
}

void main() {
  group('credentialsProvider', () {
    late _FakeRedisServer server;

    setUp(() async {
      server = await _FakeRedisServer.plain()
        ..start();
    });

    tearDown(() => server.close());

    test('authenticates with fresh credentials on every connect', () async {
      var calls = 0;
      final client = RedisClient(
        socket: RedisSocketOptions(
          port: server.port,
          retryInterval: const Duration(milliseconds: 10),
          credentialsProvider: () async {
            calls++;
            return RedisCredentials(password: 'token-$calls');
          },
        ),
      );
      addTearDown(client.close);

      await client.connect();
      expect(await client.execute(['PING']), equals('PONG'));

      await server.dropClients();
      // The next command waits out the reconnect, which asks again.
      expect(await client.execute(['PING']), equals('PONG'));

      expect(
        server.auths,
        equals([
          ['default', 'token-1'],
          ['default', 'token-2'],
        ]),
      );
    });

    test('takes precedence over a static password', () async {
      final client = RedisClient(
        socket: RedisSocketOptions(
          port: server.port,
          username: 'static-user',
          password: 'static-password',
          credentialsProvider: () async =>
              const RedisCredentials(username: 'u', password: 'token'),
        ),
      );
      addTearDown(client.close);

      await client.connect();

      expect(
        server.auths,
        equals([
          ['u', 'token'],
        ]),
      );
    });

    test('fails the connect when the provider keeps throwing', () async {
      final client = RedisClient(
        socket: RedisSocketOptions(
          port: server.port,
          retryAttempts: 2,
          retryInterval: const Duration(milliseconds: 10),
          credentialsProvider: () async => throw StateError('no token'),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.connect(),
        throwsA(
          isA<SocketException>().having(
            (e) => e.message,
            'message',
            contains('Connection retry limit exceeded'),
          ),
        ),
      );
    });

    test('fails the connect when the server refuses the credentials', () async {
      server.authReply = (_) => '-WRONGPASS invalid username-password pair\r\n';
      final client = RedisClient(
        socket: RedisSocketOptions(
          port: server.port,
          retryAttempts: 2,
          retryInterval: const Duration(milliseconds: 10),
          credentialsProvider: () async =>
              const RedisCredentials(password: 'expired'),
        ),
      );
      addTearDown(client.close);

      await expectLater(client.connect(), throwsA(isA<SocketException>()));
      expect(server.auths, hasLength(2));
    });

    test('fails an attempt whose provider never answers', () async {
      final client = RedisClient(
        socket: RedisSocketOptions(
          port: server.port,
          timeout: const Duration(milliseconds: 50),
          retryAttempts: 1,
          credentialsProvider: () => Completer<RedisCredentials>().future,
        ),
      );
      addTearDown(client.close);

      await expectLater(client.connect(), throwsA(isA<SocketException>()));
      expect(server.auths, isEmpty);
    });

    test('recovers once the provider succeeds again', () async {
      var calls = 0;
      final client = RedisClient(
        socket: RedisSocketOptions(
          port: server.port,
          retryInterval: const Duration(milliseconds: 10),
          credentialsProvider: () async {
            calls++;
            if (calls == 1) throw StateError('metadata server not ready');
            return const RedisCredentials(password: 'token');
          },
        ),
      );
      addTearDown(client.close);

      await client.connect();

      expect(await client.execute(['PING']), equals('PONG'));
      expect(calls, equals(2));
    });
  });

  group('tls', () {
    late _Pki pki;
    late _FakeRedisServer server;

    setUpAll(() async {
      pki = await _Pki.generate();
    });

    tearDownAll(() => pki.dir.delete(recursive: true));

    setUp(() async {
      server = await _FakeRedisServer.secure(pki.serverContext())
        ..start();
    });

    tearDown(() => server.close());

    test('connects to a server signed by the trusted CA', () async {
      final client = RedisClient(
        socket: RedisSocketOptions(
          host: '127.0.0.1',
          port: server.port,
          tls: true,
          securityContext: pki.clientTrusting('ca'),
          credentialsProvider: () async =>
              const RedisCredentials(password: 'token'),
        ),
      );
      addTearDown(client.close);

      await client.connect();

      expect(await client.execute(['PING']), equals('PONG'));
      expect(
        server.auths,
        equals([
          ['default', 'token'],
        ]),
      );
    });

    test(
      'closes cleanly when the server answers the hang-up with an alert',
      () async {
        // The client's close sends a FIN with no close_notify. OpenSSL, as in
        // Memorystore for Valkey, reads that as a truncated connection and
        // answers with a fatal alert before closing. The proxy stands in for
        // that answer. Arriving after close, it must not be an unhandled error.
        final proxy = await _AlertOnHangUpProxy.start(server.port);
        addTearDown(proxy.close);
        final client = RedisClient(
          socket: RedisSocketOptions(
            host: '127.0.0.1',
            port: proxy.port,
            tls: true,
            securityContext: pki.clientTrusting('ca'),
          ),
        );

        await client.connect();
        expect(await client.execute(['PING']), equals('PONG'));
        await client.close();
        // An unhandled error fails the test from the test's zone; give the
        // alert time to arrive.
        await proxy.alertSent;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );

    test('reconnects after a disconnect', () async {
      // The reconnect loop learns a connection is gone from its output
      // sink's done future, so closing a TLS connection must complete it.
      final client = RedisClient(
        socket: RedisSocketOptions(
          host: '127.0.0.1',
          port: server.port,
          tls: true,
          securityContext: pki.clientTrusting('ca'),
        ),
      );
      addTearDown(client.close);

      await client.connect();
      await client.disconnect();

      expect(
        await client.execute(['PING']).timeout(const Duration(seconds: 5)),
        equals('PONG'),
      );
    });

    test(
      'reconnects after a disconnect the server answers with an alert',
      () async {
        final proxy = await _AlertOnHangUpProxy.start(server.port);
        addTearDown(proxy.close);
        final client = RedisClient(
          socket: RedisSocketOptions(
            host: '127.0.0.1',
            port: proxy.port,
            tls: true,
            securityContext: pki.clientTrusting('ca'),
          ),
        );
        addTearDown(client.close);

        await client.connect();
        await client.disconnect();
        await proxy.alertSent;

        expect(
          await client.execute(['PING']).timeout(const Duration(seconds: 5)),
          equals('PONG'),
        );
      },
    );

    test('refuses a server whose certificate does not name the host', () async {
      // The certificate names 127.0.0.1 only. Hostname verification stays on:
      // the AUTH password can be a cloud access token.
      final client = RedisClient(
        socket: RedisSocketOptions(
          port: server.port,
          tls: true,
          securityContext: pki.clientTrusting('ca'),
          retryAttempts: 1,
          credentialsProvider: () async =>
              const RedisCredentials(password: 'token'),
        ),
      );
      addTearDown(client.close);

      await expectLater(client.connect(), throwsA(isA<SocketException>()));
      expect(server.auths, isEmpty);
    });

    test('refuses a server signed by a CA it does not trust', () async {
      final client = RedisClient(
        socket: RedisSocketOptions(
          host: '127.0.0.1',
          port: server.port,
          tls: true,
          securityContext: pki.clientTrusting('other_ca'),
          retryAttempts: 1,
        ),
      );
      addTearDown(client.close);

      await expectLater(client.connect(), throwsA(isA<SocketException>()));
      expect(server.auths, isEmpty);
    });
  });

  group('connection reset by the server', () {
    late _Pki pki;

    setUpAll(() async {
      pki = await _Pki.generate();
    });

    tearDownAll(() => pki.dir.delete(recursive: true));

    for (final tls in [false, true]) {
      for (final idle in [false, true]) {
        test(
          'reconnects without an unhandled error '
          '(tls: $tls, ${idle ? 'before' : 'after'} the first command)',
          () async {
            // A reset reaches the client as a read error, which resp_client
            // reads without an error handler: unhandled, it ends the process.
            // Before anything is written, the socket doesn't complete its
            // done future with the error, so only a close does.
            final server =
                (tls
                      ? await _FakeRedisServer.secure(pki.serverContext())
                      : await _FakeRedisServer.plain())
                  ..start();
            addTearDown(server.close);
            final proxy = await _ResetProxy.start(server.port);
            addTearDown(proxy.close);
            final logger = _RecordingLogger();
            final client = RedisClient(
              socket: RedisSocketOptions(
                host: '127.0.0.1',
                port: proxy.port,
                tls: tls,
                securityContext: tls ? pki.clientTrusting('ca') : null,
                retryInterval: const Duration(milliseconds: 10),
              ),
              logger: logger,
            );
            addTearDown(client.close);

            await client.connect();
            if (idle) {
              await proxy.paired;
            } else {
              expect(await client.execute(['PING']), equals('PONG'));
            }

            // A command written before the reset is read fails only by its
            // timeout, so wait for the client to dial again.
            final reconnected = logger.connects.firstWhere(
              (count) => count == 2,
            );
            await proxy.resetClients();
            await reconnected.timeout(const Duration(seconds: 5));

            expect(
              await client
                  .execute(['PING'])
                  .timeout(const Duration(seconds: 5)),
              equals('PONG'),
            );
            expect(
              logger.infos,
              contains(startsWith('Connection read failed: SocketException')),
            );
          },
          // SO_LINGER's number and struct differ on Windows.
          testOn: '!windows',
        );
      }
    }
  });
}

/// A TCP proxy to [_FakeRedisServer] that, once the client hangs up, writes
/// a TLS alert record back to it before closing, as OpenSSL does on a
/// connection that ends without close_notify.
class _AlertOnHangUpProxy {
  _AlertOnHangUpProxy._(this._server, this._upstreamPort) {
    _server.listen((client) async {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _upstreamPort,
      );
      upstream.listen(client.add, onError: (_) {}, onDone: () {});
      client.listen(
        upstream.add,
        onError: (_) {},
        onDone: () async {
          // A fatal decode_error alert, unencrypted, which the client's TLS
          // layer cannot accept mid-session either way.
          client.add(const [0x15, 0x03, 0x03, 0x00, 0x02, 0x02, 0x32]);
          await client.flush();
          if (!_alertSent.isCompleted) _alertSent.complete();
          client.destroy();
          upstream.destroy();
        },
      );
    });
  }

  static Future<_AlertOnHangUpProxy> start(int upstreamPort) async =>
      _AlertOnHangUpProxy._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        upstreamPort,
      );

  final ServerSocket _server;
  final int _upstreamPort;
  final _alertSent = Completer<void>();

  int get port => _server.port;

  Future<void> get alertSent => _alertSent.future;

  Future<void> close() => _server.close();
}

/// Forwards TCP to a server and resets the client side on demand, as a
/// server that drops a connection with an RST would.
class _ResetProxy {
  _ResetProxy._(this._server, this._upstreamPort) {
    _server.listen((client) async {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _upstreamPort,
      );
      _pairs.add((client, upstream));
      if (!_paired.isCompleted) _paired.complete();
      upstream.listen(client.add, onError: (_) {}, onDone: client.destroy);
      client.listen(upstream.add, onError: (_) {}, onDone: upstream.destroy);
    });
  }

  static Future<_ResetProxy> start(int upstreamPort) async => _ResetProxy._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    upstreamPort,
  );

  final ServerSocket _server;
  final int _upstreamPort;
  final _pairs = <(Socket, Socket)>[];
  final _paired = Completer<void>();

  /// Completes once the first client connection is forwarded.
  Future<void> get paired => _paired.future;

  int get port => _server.port;

  /// Closes every client connection with an RST: SO_LINGER on, with a zero
  /// timeout, makes close send an RST in place of a FIN.
  Future<void> resetClients() async {
    final soLinger = Platform.isLinux ? 13 : 0x0080;
    final linger = Uint8List(8)
      ..buffer.asInt32List()[0] = 1
      ..buffer.asInt32List()[1] = 0;
    for (final (client, upstream) in _pairs) {
      client
        ..setRawOption(
          RawSocketOption(RawSocketOption.levelSocket, soLinger, linger),
        )
        ..destroy();
      upstream.destroy();
    }
    _pairs.clear();
  }

  Future<void> close() async {
    await resetClients();
    await _server.close();
  }
}

class _RecordingLogger implements RedisLogger {
  final _connects = StreamController<int>.broadcast();
  var _connectCount = 0;

  /// The running count of `Connected.` messages.
  Stream<int> get connects => _connects.stream;

  @override
  void debug(String message) {}

  final infos = <String>[];

  @override
  void info(String message) {
    infos.add(message);
    if (message == 'Connected.') _connects.add(++_connectCount);
  }

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}
}
