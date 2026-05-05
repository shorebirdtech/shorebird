// All updater integration tests live in this single file. This is
// deliberate: `package:test` parallelizes tests across files via
// isolates, but `dlopen` loads the test_hooks cdylib exactly once per
// process and the updater's `OnceCell<UpdateConfig>` is shared across
// every isolate. Splitting these tests across multiple files would
// require either a `dart_test.yaml` concurrency override scoped to
// `test/integration/`, or a subprocess-per-test runner.
//
// Same file = same isolate = serial = no contention. If the suite
// outgrows one file, see `docs/integration_tests.md` for the
// concurrency-override path.
//
// The unit tests under `test/src/` are unaffected: they only use
// `_MockUpdaterBindings` and never load the real cdylib.

// `setUpAll` shells out to `cargo build -p library_test_hooks`. On a
// cold checkout that compiles `updater` and its dependencies and can
// take a couple of minutes — well past `package:test`'s default 30s
// per-test timeout, which also covers `setUpAll`.
@Timeout(Duration(minutes: 10))
library;

import 'dart:ffi';

import 'package:shorebird_code_push/src/generated/updater_bindings.g.dart';
import 'package:shorebird_code_push/src/updater.dart';
import 'package:test/test.dart';

import 'generated/test_hooks_bindings.g.dart';
import 'helpers/build.dart';

void main() {
  // Set in setUpAll exactly when the cdylib build/load failed. The
  // pair (`skipReason`, `testHooks`) is contractually mutually
  // exclusive: a null `skipReason` means `testHooks` is initialized,
  // and tests early-return on a non-null `skipReason` before touching
  // `testHooks`.
  String? skipReason;
  late final TestHooksBindings testHooks;

  setUpAll(() async {
    try {
      final path = await buildTestHooksCdylib();
      final lib = DynamicLibrary.open(path);
      // `Updater.bindings` is `@visibleForTesting` and the package's own
      // unit tests reassign it. We do the same here, pointing the
      // production code path at our test_hooks cdylib (which re-exports
      // the production C API alongside the `shorebird_test_*` hooks).
      Updater.bindings = UpdaterBindings(lib);
      testHooks = TestHooksBindings(lib);
    } on Object catch (e, st) {
      skipReason = 'Could not build/load library_test_hooks cdylib.\n$e\n$st';
    }
  });

  group('library_test_hooks', () {
    test('exposes both production and test-hook symbols', () {
      // `markTestSkipped` only flags the test as skipped — it does not
      // abort execution. Early-return after marking, otherwise the body
      // below would touch the uninitialized `testHooks` when the
      // setUpAll build couldn't run (e.g., no Rust toolchain on the
      // host).
      final reason = skipReason;
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }

      // Test-only symbol layered on top of the production C API.
      // Calling on a process with no prior init clears already-empty
      // globals — should be a no-op, not a crash.
      expect(testHooks.shorebird_test_reset, returnsNormally);

      // Production symbols flow through the same library. With no
      // init, `shorebird_current_boot_patch_number` returns the
      // `log_on_error` default (0).
      const updater = Updater();
      expect(updater.currentPatchNumber(), 0);
      expect(updater.nextPatchNumber(), 0);

      // Reset is still callable after exercising production symbols.
      expect(testHooks.shorebird_test_reset, returnsNormally);
    });
  });
}
