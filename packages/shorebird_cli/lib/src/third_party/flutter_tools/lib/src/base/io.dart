// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// This file serves as the single point of entry into the `dart:io` APIs
/// within Flutter tools.
///
/// In order to make Flutter tools more testable, we use the `FileSystem` APIs
/// in `package:file` rather than using the `dart:io` file APIs directly (see
/// `file_system.dart`). Doing so allows us to swap out local file system
/// access with mockable (or in-memory) file systems, making our tests hermetic
/// vis-a-vis file system access.
///
/// We also use `package:platform` to provide an abstraction away from the
/// static methods in the `dart:io` `Platform` class (see `platform.dart`). As
/// such, do not export Platform from this file!
///
/// To ensure that all file system and platform API access within Flutter tools
/// goes through the proper APIs, we forbid direct imports of `dart:io` (via a
/// test), forcing all callers to instead import this file, which exports the
/// blessed subset of `dart:io` that is legal to use in Flutter tools.
///
/// Because of the nature of this file, it is important that **platform and file
/// APIs not be exported from `dart:io` in this file**! Moreover, be careful
/// about any additional exports that you add to this file, as doing so will
/// increase the API surface that we have to test in Flutter tools, and the APIs
/// in `dart:io` can sometimes be hard to use in tests.
library;

// We allow `print()` in this file as a fallback for writing to the terminal via
// regular stdout/stderr/stdio paths. Everything else in the flutter_tools
// library should route terminal I/O through the [Stdio] class defined below.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' as io show exit;

import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';

export 'dart:io' hide exit;

/// Exits the process with the given [exitCode].
typedef ExitFunction = Never Function(int exitCode);

const ExitFunction _defaultExitFunction = io.exit;

ExitFunction _exitFunction = _defaultExitFunction;

/// Exits the process.
///
/// Throws [AssertionError] if assertions are enabled and the dart:io exit
/// is still active when called. This may indicate exit was called in
/// a test without being configured correctly.
///
/// This is analogous to the `exit` function in `dart:io`, except that this
/// function may be set to a testing-friendly value by calling
/// [setExitFunctionForTests] (and then restored to its default implementation
/// with [restoreExitFunction]). The default implementation delegates to
/// `dart:io`.
ExitFunction get exit {
  assert(
    _exitFunction != io.exit || !_inUnitTest(),
    'io.exit was called with assertions active in a unit test',
  );
  return _exitFunction;
}

// Whether the tool is executing in a unit test.
bool _inUnitTest() {
  return Zone.current[#test.declarer] != null;
}

/// Sets the [exit] function to a function that throws an exception rather
/// than exiting the process; this is intended for testing purposes.
@visibleForTesting
void setExitFunctionForTests([ExitFunction? exitFunction]) {
  _exitFunction = exitFunction ??
      (int exitCode) {
        throw ProcessExit(exitCode, immediate: true);
      };
}

/// Restores the [exit] function to the `dart:io` implementation.
@visibleForTesting
void restoreExitFunction() {
  _exitFunction = _defaultExitFunction;
}
