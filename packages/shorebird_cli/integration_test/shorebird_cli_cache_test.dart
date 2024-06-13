import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import 'helpers.dart';

R runWithOverrides<R>(R Function() body) {
  return runScoped(
    body,
    values: {
      authRef,
      httpClientRef,
      loggerRef,
      platformRef,
      shorebirdEnvRef,
    },
  );
}

void main() {
  group('shorebird cache', () {
    test('can clear the cache', () {
      final result = runCommand(
        'shorebird cache clear',
        workingDirectory: '.',
      );

      expect(result.exitCode, equals(ExitCode.success.code));
    });
  });
}
