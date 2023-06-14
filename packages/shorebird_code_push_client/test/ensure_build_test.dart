@Tags(['version-verify'])
library;

import 'package:build_verify/build_verify.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ensure_build',
    () => expectBuildClean(
      packageRelativeDirectory: 'packages/shorebird_code_push_client',
    ),
    timeout: const Timeout.factor(2),
  );
}
