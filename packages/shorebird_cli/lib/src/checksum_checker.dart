import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [ChecksumChecker] instance.
final checksumCheckerRef = create(ChecksumChecker.new);

/// The [ChecksumChecker] instance available in the current zone.
ChecksumChecker get checksumChecker => read(checksumCheckerRef);

/// Helper class that validates checksum hashes from files.
///
/// This class uses the SHA256 hash algorithm to do its validations.
class ChecksumChecker {
  /// Checks if the [file] hash matches the received [checksum].
  bool checkFile(File file, String checksum) {
    final fileSha256 = sha256.convert(file.readAsBytesSync());
    return fileSha256.toString() == checksum;
  }
}
