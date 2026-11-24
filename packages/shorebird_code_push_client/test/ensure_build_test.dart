@Tags(['version-verify'])
library;

import 'package:build_verify/build_verify.dart';
import 'package:test/test.dart';

/// build_runner compiles its builders AOT by default, which pays off only over
/// repeated builds; this one cold build spends most of its time on that
/// compile, so it runs them JIT.
const buildCommand = ['DART', 'run', 'build_runner', 'build', '--force-jit'];

void main() {
  test(
    'ensure_build',
    () => expectBuildClean(
      packageRelativeDirectory: 'packages/shorebird_code_push_client',
      customCommand: buildCommand,
    ),
    timeout: const Timeout.factor(2),
  );
}
