import 'dart:io';

import 'package:flutter_version_resolver/flutter_version_resolver.dart';
import 'package:flutter_version_resolver/src/logger.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// Resolves the Flutter version for a package and optionally writes it to a
/// file.
///
/// Usage:
/// ```sh
/// dart run bin/flutter_version_resolver.dart <path-to-package> [<output-file>]
/// ```
Future<int> main(List<String> arguments) async {
  return await runScoped(() async {
    if (arguments.isEmpty || arguments.length > 2) {
      logger.err(
        'Usage: dart run bin/flutter_version_resolver.dart <path-to-package> [<output-file>]',
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
    );
    logger.info('Resolved Flutter version: $flutterVersion');

    if (arguments.length > 1) {
      final outputFile = File(arguments[1])
        ..createSync(recursive: true)
        ..writeAsStringSync(flutterVersion);
      logger.info('Wrote flutter version to ${outputFile.path}');
    }

    return ExitCode.success.code;
  }, values: {loggerRef});
}
