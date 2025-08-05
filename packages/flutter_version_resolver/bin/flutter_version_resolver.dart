import 'dart:io';

import 'package:flutter_version_resolver/flutter_version_resolver.dart';
import 'package:mason_logger/mason_logger.dart';

/// Resolves the Flutter version for a package and optionally writes it to a
/// file.
///
/// Usage:
/// ```sh
/// dart run bin/flutter_version_resolver.dart <path-to-package> [<output-file>]
/// ```
Future<int> main(List<String> arguments) async {
  final logger = Logger();

  if (arguments.isEmpty) {
    logger.err(
      'Usage: dart run bin/flutter_version_resolver.dart <path-to-package>',
    );
    return ExitCode.usage.code;
  }

  final packageDirectory = Directory(arguments[0]);
  if (!packageDirectory.existsSync()) {
    logger.err(
      'Package directory does not exist: ${packageDirectory.path}',
    );
    return ExitCode.usage.code;
  }

  final flutterVersion = resolveFlutterVersion(
    packagePath: packageDirectory.path,
    log: logger.info,
  );
  logger.info('Resolved Flutter version: $flutterVersion');

  return ExitCode.success.code;
}
