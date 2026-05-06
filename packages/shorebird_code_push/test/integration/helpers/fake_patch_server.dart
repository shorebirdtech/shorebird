import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'fixtures.dart';

/// In-process fake of the Shorebird patches API for integration tests.
///
/// Binds to `127.0.0.1` on an ephemeral port. Tests configure the next
/// `/api/v1/patches/check` response, optionally register patch bytes
/// for download, and inspect counters / recorded events afterward.
///
/// This is intentionally minimal — no auth, no Range support, no
/// concurrency control. Stages 3+ (download cutoff / resume tests)
/// will extend it as needed.
class FakePatchServer {
  FakePatchServer._(this._httpServer);

  static Future<FakePatchServer> start() async {
    // Handler captures the instance by reference so the closure
    // resolves against live state. `late final` lets us reference
    // `instance` in the closure body before it's assigned — the
    // closure only runs once requests arrive, by which time we've
    // assigned it below.
    late final FakePatchServer instance;
    final httpServer = await shelf_io.serve(
      (Request request) => instance._handle(request),
      '127.0.0.1',
      0,
    );
    return instance = FakePatchServer._(httpServer);
  }

  final HttpServer _httpServer;

  String get baseUrl => 'http://127.0.0.1:${_httpServer.port}';

  /// Number of `/api/v1/patches/check` requests received.
  int patchCheckCount = 0;

  /// Number of GET requests served from the registered downloadables.
  int downloadCount = 0;

  /// Bodies of every `/api/v1/patches/events` request received,
  /// decoded as JSON.
  final List<Map<String, dynamic>> recordedEvents = [];

  Map<String, dynamic>? _checkResponse;
  final Map<String, Uint8List> _downloadables = {};

  /// Schedules the next `/api/v1/patches/check` response to advertise
  /// [patch] as available, and registers its bytes for download at a
  /// generated URL under this server's base.
  void enqueuePatch(PatchFixture patch) {
    final path = '/patch/${patch.number}';
    _downloadables[path] = patch.bytes;
    _checkResponse = {
      'patch_available': true,
      'patch': {
        'number': patch.number,
        'hash': patch.hash,
        'download_url': '$baseUrl$path',
      },
    };
  }

  /// Server has nothing new — `patch_available: false`, no rollback
  /// signal, no patch.
  void respondWithNoUpdate() {
    _checkResponse = {'patch_available': false};
  }

  /// Server has rolled back the listed patch numbers with no
  /// replacement. Used to exercise the patch-to-release rollback
  /// path that produced shorebird #3728.
  void respondWithRollback(List<int> rolledBackNumbers) {
    _checkResponse = {
      'patch_available': false,
      'rolled_back_patch_numbers': rolledBackNumbers,
    };
  }

  Future<void> stop() => _httpServer.close(force: true);

  Future<Response> _handle(Request request) async {
    final path = '/${request.url.path}';
    if (request.method == 'POST' && path == '/api/v1/patches/check') {
      patchCheckCount++;
      final body = _checkResponse;
      if (body == null) {
        return Response.internalServerError(
          body: 'no patch check response configured',
        );
      }
      return Response.ok(
        jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && path == '/api/v1/patches/events') {
      final raw = await request.readAsString();
      recordedEvents.add(jsonDecode(raw) as Map<String, dynamic>);
      return Response.ok('');
    }
    if (request.method == 'GET') {
      final bytes = _downloadables[path];
      if (bytes != null) {
        downloadCount++;
        return Response.ok(
          bytes,
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': '${bytes.length}',
          },
        );
      }
    }
    return Response.notFound('${request.method} $path');
  }
}
