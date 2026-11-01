import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [Abi] instance.
ScopedRef<LocalAbi> abiRef = create(() => const LocalAbi());

/// The [Abi] instance available in the current zone.
LocalAbi get abi => read(abiRef, orElse: () => const LocalAbi());

/// {@template abi}
/// A mockable wrapper around [Abi] from dart:ffi.
/// {@endtemplate}
class LocalAbi {
  /// {@macro abi}
  const LocalAbi({
    int? Function() readWindowsNativeMachine = windowsNativeMachine,
  }) : _readWindowsNativeMachine = readWindowsNativeMachine;

  final int? Function() _readWindowsNativeMachine;

  /// The current ABI: the operating system and architecture the Dart VM
  /// running the CLI was built for.
  Abi get current => Abi.current();

  /// The CPU architecture of the machine, such as `arm64` or `x64`.
  ///
  /// This is not always [current]'s architecture: Windows on Arm runs an x64
  /// Dart under emulation when no arm64 Dart SDK is available, so on Windows
  /// it asks the operating system for the native machine. Elsewhere it is the
  /// Dart VM's architecture.
  String get hostArchitecture {
    // Abi.toString() reads like `windows_x64` or `macos_arm64`.
    final name = current.toString();
    final abiArchitecture = name.substring(name.indexOf('_') + 1);
    if (name.startsWith('windows_')) {
      final machine = _readWindowsNativeMachine();
      final architecture = _windowsMachineArchitectures[machine];
      if (architecture != null) return architecture;
    }
    return abiArchitecture;
  }
}

/// `IMAGE_FILE_MACHINE_*` values, by the name [Abi] gives each architecture.
const _windowsMachineArchitectures = {
  0x014c: 'ia32',
  0x8664: 'x64',
  0xaa64: 'arm64',
};

/// The `IMAGE_FILE_MACHINE_*` value of the Windows machine's native
/// architecture, from `IsWow64Process2`, or null when it can't be read
/// (Windows before 10 version 1511 has no `IsWow64Process2`).
///
/// See https://learn.microsoft.com/windows/win32/api/wow64apiset/nf-wow64apiset-iswow64process2
int? windowsNativeMachine() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getCurrentProcess = kernel32
        .lookupFunction<IntPtr Function(), int Function()>(
          'GetCurrentProcess',
        );
    final isWow64Process2 = kernel32
        .lookupFunction<
          Int32 Function(IntPtr, Pointer<Uint16>, Pointer<Uint16>),
          int Function(int, Pointer<Uint16>, Pointer<Uint16>)
        >('IsWow64Process2');
    return using((arena) {
      final processMachine = arena<Uint16>();
      final nativeMachine = arena<Uint16>();
      final ok = isWow64Process2(
        getCurrentProcess(),
        processMachine,
        nativeMachine,
      );
      return ok == 0 ? null : nativeMachine.value;
    });
  } on Object {
    return null;
  }
}
