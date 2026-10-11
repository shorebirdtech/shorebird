@Tags(['version-verify'])
library;

import 'package:build_verify/build_verify.dart';
import 'package:test/test.dart';
import 'src/helpers.dart';

void main() {
  useTempWorkingDirectory();
  test(
    'ensure_build',
    () => expectBuildClean(packageRelativeDirectory: 'packages/shorebird_cli'),
    timeout: const Timeout.factor(2),
  );
}
