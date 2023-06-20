import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_code_push/src/generated/updater_bindings.g.dart';
import 'package:shorebird_code_push/src/updater.dart';
import 'package:test/test.dart';

class _MockUpdaterBindings extends Mock implements UpdaterBindings {}

void main() {
  group(Updater, () {
    late UpdaterBindings updaterBindings;
    late Updater updater;

    setUp(() {
      updaterBindings = _MockUpdaterBindings();

      updater = Updater();
      Updater.bindings = updaterBindings;
    });

    test('initializes from currently loaded library', () {
      expect(updater, isNotNull);
    });

    group('currentPatchNumber', () {
      test('returns null if bindings return null pointer', () {
        when(() => updaterBindings.shorebird_next_boot_patch_number())
            .thenReturn(ffi.nullptr);
        final currentPatchNumber = updater.currentPatchNumber();
        expect(currentPatchNumber, isNull);
      });

      test('returns number if bindings return non-null pointer', () {
        final charPtr = '123'.toNativeUtf8().cast<ffi.Char>();
        when(() => updaterBindings.shorebird_next_boot_patch_number())
            .thenReturn(charPtr);
        final currentPatchNumber = updater.currentPatchNumber();
        expect(currentPatchNumber, 123);
      });
    });

    group('checkForUpdate', () {
      test('forwards the result of shorebird_check_for_update', () {
        when(() => updaterBindings.shorebird_check_for_update())
            .thenReturn(true);
        expect(updater.checkForUpdate(), isTrue);

        when(() => updaterBindings.shorebird_check_for_update())
            .thenReturn(false);
        expect(updater.checkForUpdate(), isFalse);
      });
    });
  });
}
