import 'dart:io';
import 'dart:typed_data';

import 'package:shorebird_cli/src/archive_analysis/byte_utils.dart';

const _machOHeaderSize = 32;
const _uuidLoadCommandType = 0x1b;

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
}
