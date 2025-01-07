import 'dart:io';
import 'dart:typed_data';

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
    final timestampLocations = [0x110, 0x6e14];
    for (final location in timestampLocations) {
      bytes.setRange(location, location + 4, List.filled(4, 0));
    }

    return bytes;
  }
}
