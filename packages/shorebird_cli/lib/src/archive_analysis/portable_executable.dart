import 'dart:io';
import 'dart:typed_data';

import 'package:shorebird_cli/src/archive_analysis/byte_utils.dart';

/// Utilities for interacting with Windows Portable Executable files.
class PortableExecutable {
  /// Zeroes out the timestamps in the provided PE file to enable comparison of
  /// binaries with different build times.
  ///
  /// Flutter app EXEs include the build time as a timestamp twice in the file.
  /// We need to zero these out so we can check for actual binary differences.
  ///
  /// Timestamps are DWORD (4-byte) values at:
  ///   1. In the PE header. The offset of this header is always at 0x3c in the
  ///      file, and the timestamp is at offset 0x8 from the start of the PE.
  ///   2. In the .rdata section. I have not yet found a precise way to
  ///      determine the timestamp's offset in this section, so we read through
  ///      the section in 4-byte increments and zero out any DWORDs that match
  ///      the timestamp from the PE header.
  ///
  /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#coff-file-header-object-and-image
  static Uint8List bytesWithZeroedTimestamps(File file) {
    final bytes = file.readAsBytesSync();

    // https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#signature-image-only
    //
    // PE files have a 4-byte "signature" that identifies them as PE files. This
    // signature is at the offset specified at 0x3c, and the PE header starts
    // after this.
    //
    // The PE header is 20 bytes long and contains the following fields:
    //   0x0: 2 bytes for machine
    //   0x2: 2 bytes for number of sections
    //   0x4: 4 bytes for time date stamp
    //   0x8: 4 bytes for pointer to symbol table
    //   0xc: 4 bytes for number of symbols
    //   0x10: 2 bytes for size of optional header
    const peHeaderSize = 0x14;
    final signatureOffset = readInt32(bytes, 0x3c);
    final peHeaderOffset = signatureOffset + 0x4;
    final numSections = readInt16(bytes, peHeaderOffset + 0x2);
    final peHeaderTimestampOffset = peHeaderOffset + 0x4;
    final optionalHeaderSize = readInt16(bytes, peHeaderOffset + 0x10);
    final peHeaderTimestamp = readInt32(bytes, peHeaderTimestampOffset);
    // Zero out the first timestamp
    bytes.setRange(
      peHeaderTimestampOffset,
      peHeaderTimestampOffset + 4,
      List.filled(4, 0),
    );

    // After the PE header is the optional header, which is of variable size.
    // It does not contain any information we currently care about, so we skip
    // that and proceed to the section table, which follows the optional header.
    //
    // Each section header is 40 (0x28) bytes long.
    //
    // https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#section-table-section-headers
    const sectionHeaderSize = 0x28;
    final sectionHeadersOffset =
        peHeaderOffset + peHeaderSize + optionalHeaderSize;

    int? rawDataOffset;
    int? rawDataSize;
    for (var i = 0; i < numSections; i++) {
      final sectionOffset = sectionHeadersOffset + i * sectionHeaderSize;
      final sectionName = String.fromCharCodes(
        bytes.sublist(sectionOffset, sectionOffset + 8),
      );
      if (sectionName.startsWith('.rdata')) {
        rawDataSize = readInt32(bytes, sectionOffset + 0x10);
        rawDataOffset = readInt32(bytes, sectionOffset + 0x14);
        break;
      }
    }

    // If we could not find an .rdata section, that means that this PE file is
    // likely malformed.
    if (rawDataOffset == null || rawDataSize == null) {
      throw Exception('Could not find .rdata section');
    }

    // Iterate through the .rdata section and zero out any instances of the
    // timestamp from the PE header that we find.
    for (var i = 0; i < rawDataSize; i += 4) {
      final currentOffset = rawDataOffset + i;
      if (readInt32(bytes, currentOffset) == peHeaderTimestamp) {
        bytes.setRange(currentOffset, currentOffset + 4, List.filled(4, 0));
      }
    }

    return bytes;
  }
}
