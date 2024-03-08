import 'dart:io';
import 'dart:typed_data';

const machOHeaderSize = 32;
const uuidLoadCommandType = 0x1b;

/// Utilities for interacting with Mach-O files.
/// See https://en.wikipedia.org/wiki/Mach-O.
class MachO {
  /// Reads a 32-bit integer as a little-endian value from the provided bytes.
  static int _readInt32(Uint8List bytes, int offset) {
    return bytes[offset + 3] << 24 |
        bytes[offset + 2] << 16 |
        bytes[offset + 1] << 8 |
        bytes[offset];
  }

  /// Returns `true` if the provided file is a Mach-O file.
  static bool isMachOFile(File file) {
    final bytes = file.readAsBytesSync();
    final magic = _readInt32(bytes, 0);

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
    final numberOfLoadCommands = _readInt32(bytes, 16);

    // The load commands are immediately after the header.
    var offset = machOHeaderSize;
    for (var i = 0; i < numberOfLoadCommands; i++) {
      final commandType = _readInt32(bytes, offset);
      final commandLength = _readInt32(bytes, offset + 4);

      if (commandType == uuidLoadCommandType) {
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
