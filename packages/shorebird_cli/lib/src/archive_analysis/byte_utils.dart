import 'dart:typed_data';

int readInt16(Uint8List bytes, int offset) {
  return bytes[offset + 1] << 8 | bytes[offset];
}

/// Reads a 32-bit integer as a little-endian value from the provided bytes.
int readInt32(Uint8List bytes, int offset) {
  return bytes[offset + 3] << 24 |
      bytes[offset + 2] << 16 |
      bytes[offset + 1] << 8 |
      bytes[offset];
}
