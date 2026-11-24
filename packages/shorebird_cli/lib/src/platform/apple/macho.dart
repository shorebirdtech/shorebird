import 'dart:io';
import 'dart:typed_data';

import 'package:shorebird_cli/src/archive_analysis/byte_utils.dart';
import 'package:shorebird_cli/src/platform/platform.dart';

const _machOHeaderSize = 32;
const _uuidLoadCommandType = 0x1b;
const _machO64Magic = 0xfeedfacf;
const _fatMagic = 0xcafebabe;
const _fatMagic64 = 0xcafebabf;
const _cpuTypeX86_64 = 0x01000007;
const _cpuTypeArm64 = 0x0100000c;
const _segment64LoadCommandType = 0x19;
const _segment64CommandSize = 72;
const _section64Size = 80;

/// Utilities for interacting with Mach-O files.
/// See https://en.wikipedia.org/wiki/Mach-O.
class MachO {
  /// Returns `true` if the provided file is a Mach-O file.
  static bool isMachOFile(File file) {
    final bytes = file.readAsBytesSync();
    final magic = readInt32(bytes, 0);

    // These are the magic numbers for Mach-O files.
    // See https://en.wikipedia.org/wiki/Mach-O#Mach-O_header
    return magic == 0xfeedface || magic == 0xfeedfacf;
  }

  /// The architectures [file] carries slices for, or null when [file] does
  /// not exist or is not a thin 64-bit or universal Mach-O.
  static Set<Arch>? architectures(File file) {
    if (!file.existsSync()) return null;
    final raf = file.openSync();
    final Uint8List header;
    try {
      header = raf.readSync(2056);
    } finally {
      raf.closeSync();
    }
    if (header.length < 8) return null;
    final data = ByteData.sublistView(header);
    if (data.getUint32(0, Endian.little) == _machO64Magic) {
      final arch = _archForCpuType(data.getUint32(4, Endian.little));
      return arch == null ? null : {arch};
    }
    final beMagic = data.getUint32(0);
    if (beMagic != _fatMagic && beMagic != _fatMagic64) return null;
    final sliceCount = data.getUint32(4);
    if (sliceCount == 0 || sliceCount > 64) return null;
    final entrySize = beMagic == _fatMagic64 ? 32 : 20;
    if (8 + sliceCount * entrySize > header.length) return null;
    final archs = <Arch>{};
    for (var i = 0; i < sliceCount; i++) {
      final arch = _archForCpuType(data.getUint32(8 + i * entrySize));
      if (arch != null) archs.add(arch);
    }
    return archs.isEmpty ? null : archs;
  }

  static Arch? _archForCpuType(int cpuType) => switch (cpuType) {
    _cpuTypeArm64 => Arch.arm64,
    _cpuTypeX86_64 => Arch.x86_64,
    _ => null,
  };

  /// Returns a copy of the provided Mach-O file with the UUID load command
  /// zeroed out. This is necessary because the same code built in different
  /// locations will generate Mach-O files with different UUIDs as the only
  /// difference.
  static Uint8List bytesWithZeroedUUID(File file) {
    final bytes = file.readAsBytesSync();

    // The number of load commands is a 32-bit int at offset 16. We could
    // probably write a more robust MachO header parser, but this is all we need
    // for now.
    final numberOfLoadCommands = readInt32(bytes, 16);

    // The load commands are immediately after the header.
    var offset = _machOHeaderSize;
    for (var i = 0; i < numberOfLoadCommands; i++) {
      final commandType = readInt32(bytes, offset);
      final commandLength = readInt32(bytes, offset + 4);

      if (commandType == _uuidLoadCommandType) {
        // Zero out the UUID bytes.
        final loadCommandStart = offset + 8;
        for (var j = loadCommandStart; j < offset + commandLength; j++) {
          bytes[j] = 0;
        }
        break;
      }

      offset += commandLength;
    }

    return bytes;
  }

  /// The total size in bytes of the `__debug_info` sections in [file], or
  /// null if [file] isn't a thin 64-bit Mach-O (an ELF, a universal binary).
  ///
  /// A dSYM whose `__debug_info` is 0 has no DWARF, so it names no functions.
  static int? debugInfoSize(File file) {
    final bytes = file.readAsBytesSync();
    if (bytes.length < _machOHeaderSize) return null;
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != _machO64Magic) return null;

    final numberOfLoadCommands = data.getUint32(16, Endian.little);
    var size = 0;
    var offset = _machOHeaderSize;
    for (var i = 0; i < numberOfLoadCommands; i++) {
      if (offset + 8 > bytes.length) return null;
      final commandType = data.getUint32(offset, Endian.little);
      final commandLength = data.getUint32(offset + 4, Endian.little);
      if (commandLength < 8) return null;
      if (commandType == _segment64LoadCommandType) {
        if (offset + _segment64CommandSize > bytes.length) return null;
        final sectionCount = data.getUint32(offset + 64, Endian.little);
        for (var j = 0; j < sectionCount; j++) {
          final section = offset + _segment64CommandSize + j * _section64Size;
          if (section + _section64Size > bytes.length) return null;
          if (_name(bytes, section) == '__debug_info') {
            size += data.getUint64(section + 40, Endian.little);
          }
        }
      }
      offset += commandLength;
    }
    return size;
  }

  /// The NUL-padded 16-byte name at [offset].
  static String _name(Uint8List bytes, int offset) => String.fromCharCodes(
    bytes.sublist(offset, offset + 16).takeWhile((b) => b != 0),
  );
}
