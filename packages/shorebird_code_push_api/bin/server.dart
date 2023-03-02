import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final router = shelf_router.Router()
    ..all('/', (_) => Response.ok('Hello, world!'));

  final server = await shelf_io.serve(
    logRequests().addHandler(router.call),
    InternetAddress.anyIPv6,
    port,
  );

  // ignore: avoid_print
  print('Serving at http://${server.address.host}:${server.port}');
}
