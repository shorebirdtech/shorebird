import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crclib/catalog.dart';
import 'package:crypto/crypto.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logger.dart';

/// A reference to a [ChecksumChecker] instance.
final checksumCheckerRef = create(ChecksumChecker.new);

/// The [ChecksumChecker] instance available in the current zone.
ChecksumChecker get checksumChecker => read(checksumCheckerRef);

/// The algorithm used to create the checksum.
enum ChecksumAlgorithm {
  // ignore: public_member_api_docs
  sha256,
  // ignore: public_member_api_docs
  crc32c;
}

/// Helper class that validates checksum hashes from files.
///
/// This class uses the SHA256 hash algorithm to do its validations.
class ChecksumChecker {
  /// Checks if the [file] hash matches the received [checksum].
  bool checkFile(
    File file, {
    required String checksum,
    required ChecksumAlgorithm algorithm,
  }) {
    switch (algorithm) {
      case ChecksumAlgorithm.sha256:
        return _checkSha256(file, checksum);
      case ChecksumAlgorithm.crc32c:
        return _checkCrc32c(file, checksum);
    }
  }

  /// Checks if the [file] hash matches the received [checksum]. [checksum] is
  /// a base64 encoded string.
  ///
  /// [checksum] can be computed locally by running the following in the
  /// terminal:
  ///
  ///   gcloud-crc32c -e /path/to/file
  ///
  bool _checkCrc32c(File file, String checksum) {
    logger.detail('checking CRC for ${file.path} against $checksum');
    final fileCrc32c = Crc32C().convert(file.readAsBytesSync()).toBigInt();
    final decodedBase64 = base64.decode(checksum);
    final expectedCrc32c = _deserializeBigInt(decodedBase64);
    logger
      ..detail('actualCrc32c: $fileCrc32c')
      ..detail('expectedCrc32c: $expectedCrc32c');
    return fileCrc32c == expectedCrc32c;
  }

  bool _checkSha256(File file, String checksum) {
    final fileSha256 = sha256.convert(file.readAsBytesSync());
    return fileSha256.toString() == checksum;
  }

  /// Converts a byte array to a BigInt.
  BigInt _deserializeBigInt(Uint8List array) {
    var bi = BigInt.zero;
    for (final byte in array) {
      bi <<= 8;
      bi |= BigInt.from(byte);
    }
    return bi;
  }
}
