// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';
import 'package:artifact_proxy/artifact_proxy.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_hotreload/shelf_hotreload.dart';
import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'config',
      defaultsTo: 'config.yaml',
      help: 'Path to config file.',
    )
    ..addFlag(
      'record',
      help: 'Record requests into config file.',
    )
    ..addFlag(
      'watch',
      help: 'Whether to watch for changes and hot-reload.',
    );

  final results = parser.parse(args);

  if (results.rest.isNotEmpty) {
    print(parser.usage);
    exit(1);
  }

  final shouldWatch = results['watch'] as bool;
  final configPath = results['config'] as String;
  final config = loadYaml(File(configPath).readAsStringSync()) as Map;
  final handler = artifactProxyHandler(config: config);

  // Hot-reload is enabled when the `--watch` flag is passed.
  if (shouldWatch) return withHotreload(() => createServer(handler));

  await createServer(handler);
}

Future<HttpServer> createServer(Handler proxy) async {
  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(proxy);
  final server = await shelf_io.serve(handler, 'localhost', 8080);
  server.autoCompress = true;
  return server;
}
