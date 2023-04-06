// ignore_for_file: avoid_print

import 'dart:io';

import 'package:artifact_proxy/artifact_proxy.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_hotreload/shelf_hotreload.dart';
import 'package:yaml/yaml.dart';

Future<void> main() async {
  const configPath = 'config.yaml';
  final isDev = Platform.environment['DEV'] == 'true';
  final config = loadYaml(File(configPath).readAsStringSync()) as Map;
  final handler = artifactProxyHandler(config: config);
  final ip = InternetAddress.anyIPv6;
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  // Hot-reload is enabled when the DEBUG environment variable is set to true.
  if (isDev) return withHotreload(() => serve(handler, ip, port));

  await serve(handler, ip, port);
}

Future<HttpServer> serve(Handler proxy, InternetAddress ip, int port) async {
  const pipeline = Pipeline();
  final handler = pipeline.addMiddleware(logRequests()).addHandler(proxy);
  final server = await shelf_io.serve(handler, ip, port);
  print('Serving at http://localhost:${server.port}');
  server.autoCompress = true;
  return server;
}
