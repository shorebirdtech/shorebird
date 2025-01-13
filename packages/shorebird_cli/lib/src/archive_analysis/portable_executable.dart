import 'dart:io';
import 'dart:typed_data';

import 'package:shorebird_cli/src/archive_analysis/byte_utils.dart';

/// Utilities for interacting with Windows Portable Executable files.
class PortableExecutable {
  /// Zeroes out the timestamps in the provided PE file to enable comparison of
  /// binaries with different build times.
  ///
  /// Timestamps are DWORD (4-byte) values at:
  ///   1. offset 0x110 in the PE header.
  ///   2. offset 0x6e14 (seems to be in section 1, need to figure out a robust
  ///     way to find this).
  ///
  /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#coff-file-header-object-and-image
  static Uint8List bytesWithZeroedTimestamps(File file) {
    final bytes = file.readAsBytesSync();

    // https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#signature-image-only
    // 4 bytes for signature
    // 2 bytes for machine
    // 2 bytes for number of sections
    // 4 bytes for time date stamp
    // 4 bytes for pointer to symbol table
    final peHeaderOffset = readInt32(bytes, 0x3c);
    final numSections = readInt16(bytes, peHeaderOffset + 0x6);
    final peHeaderTimestampOffset = peHeaderOffset + 0x8;
    final peHeaderTimestamp = readInt32(bytes, peHeaderTimestampOffset);
    // Zero out the first timestamp
    bytes.setRange(
      peHeaderTimestampOffset,
      peHeaderTimestampOffset + 4,
      List.filled(4, 0),
    );

    final optionalHeaderOffset = peHeaderOffset + 0x18;
    // optional header size is 0xf0
    // section headers are 0x28 each
    int? rawDataPtr;
    int? rawDataSize;
    for (var i = 0; i < numSections; i++) {
      final sectionOffset = optionalHeaderOffset + 0xf0 + i * 0x28;
      final sectionName =
          String.fromCharCodes(bytes.sublist(sectionOffset, sectionOffset + 8));
      // final virtualSize = readInt32(bytes, sectionOffset + 0x8);
      // final virtualAddress = readInt32(bytes, sectionOffset + 0xc);
      final sizeOfRawData = readInt32(bytes, sectionOffset + 0x10);
      final pointerToRawData = readInt32(bytes, sectionOffset + 0x14);
      // final characteristics = readInt32(bytes, sectionOffset + 0x24);
      print(
          '''section $i: $sectionName, $sizeOfRawData, ${pointerToRawData.toRadixString(16)}''');
      if (sectionName.startsWith('.rdata')) {
        rawDataPtr = pointerToRawData;
        rawDataSize = sizeOfRawData;
      }
    }

    if (rawDataPtr == null || rawDataSize == null) {
      throw Exception('Could not find .rdata section');
    }

    for (var i = 0; i < rawDataSize; i += 4) {
      final currentOffset = rawDataPtr + i;
      final num = readInt32(bytes, currentOffset);
      if (num == peHeaderTimestamp) {
        print('found timestamp at ${currentOffset.toRadixString(16)}');
        bytes.setRange(currentOffset, currentOffset + 4, List.filled(4, 0));
      }
    }

    return bytes;
  }
}
