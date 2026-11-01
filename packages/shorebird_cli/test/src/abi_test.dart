import 'dart:ffi';
import 'dart:io';

import 'package:shorebird_cli/src/abi.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class _FakeLocalAbi extends LocalAbi {
  _FakeLocalAbi(this._current, {int? nativeMachine})
    : super(readWindowsNativeMachine: () => nativeMachine);

  final Abi _current;

  @override
  Abi get current => _current;
}

void main() {
  useTempWorkingDirectory();
  group(LocalAbi, () {
    test('returns the current ABI', () {
      expect(const LocalAbi().current, equals(Abi.current()));
    });

    group('hostArchitecture', () {
      test("is the Dart VM's architecture off Windows", () {
        expect(
          _FakeLocalAbi(Abi.macosArm64, nativeMachine: 0xaa64).hostArchitecture,
          equals('arm64'),
        );
        expect(
          _FakeLocalAbi(Abi.linuxX64).hostArchitecture,
          equals('x64'),
        );
      });

      test("is the native machine's on Windows, under emulation too", () {
        expect(
          _FakeLocalAbi(Abi.windowsX64, nativeMachine: 0xaa64).hostArchitecture,
          equals('arm64'),
        );
      });

      test(
        "falls back to the Dart VM's when Windows can't say",
        () {
          expect(
            _FakeLocalAbi(Abi.windowsX64).hostArchitecture,
            equals('x64'),
          );
        },
      );

      test('names this machine', () {
        expect(
          const LocalAbi().hostArchitecture,
          isIn(['arm64', 'x64', 'ia32', 'riscv64', 'arm']),
        );
      });
    });

    group('windowsNativeMachine', () {
      test(
        'reads the machine on Windows',
        () {
          expect(windowsNativeMachine(), isIn([0x8664, 0xaa64]));
        },
        skip: !Platform.isWindows,
      );

      test(
        'is null elsewhere',
        () {
          expect(windowsNativeMachine(), isNull);
        },
        skip: Platform.isWindows,
      );
    });
  });
}
