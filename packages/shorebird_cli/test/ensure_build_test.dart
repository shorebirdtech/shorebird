@Tags(['version-verify'])
library;

import 'dart:io';

import 'package:build_verify/build_verify.dart';
import 'package:test/test.dart';

import 'src/helpers.dart';

/// build_runner compiles its builders AOT by default, which pays off only over
/// repeated builds; this one cold build spends most of its time on that
/// compile, so it runs them JIT.
const buildCommand = ['DART', 'run', 'build_runner', 'build', '--force-jit'];

void main() {
  useTempWorkingDirectory();
  test(
    'ensure_build',
    // Builds and diffs the real package, which `expectBuildClean` finds from
    // the current directory.
    () => IOOverrides.runZoned(
      () => expectBuildClean(
        packageRelativeDirectory: 'packages/shorebird_cli',
        customCommand: buildCommand,
      ),
      getCurrentDirectory: () => Directory(packagePath('')),
    ),
    timeout: const Timeout.factor(2),
  );
}
