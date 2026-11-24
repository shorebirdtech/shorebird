@Tags(['version-verify'])
library;

import 'dart:io';

import 'package:build_verify/build_verify.dart';
import 'package:test/test.dart';

import 'src/helpers.dart';

void main() {
  useTempWorkingDirectory();
  test(
    'ensure_build',
    // Builds and diffs the real package, which `expectBuildClean` finds from
    // the current directory.
    () => IOOverrides.runZoned(
      () =>
          expectBuildClean(packageRelativeDirectory: 'packages/shorebird_cli'),
      getCurrentDirectory: () => Directory(packagePath('')),
    ),
    // `dart run build_runner` compiles its builders from scratch first (42 s
    // on a CI runner), so the whole run takes about a minute.
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
