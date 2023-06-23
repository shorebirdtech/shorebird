import 'dart:io';

import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';

/// Parses a .MF file into a [PathHashes] map.
class MfReader {
  static final nameRegex = RegExp(r'^Name: (.+)$');
  static final nameContinuedRegex = RegExp(r'^ (.+)$');
  static final shaDigestRegex = RegExp(r'^SHA-256-Digest: (.+)$');

  /// Parses the content of [mfFile] into a [PathHashes] map.
  ///
  /// [mfFile] should be a JAR manifest file, as described in
  /// https://docs.oracle.com/javase/tutorial/deployment/jar/manifestindex.html.
  static PathHashes read(File mfFile) => parse(mfFile.readAsStringSync());

  /// Parses the contents [mfContents] file into a [PathHashes] map.
  ///
  /// [mfContents] should be a JAR manifest file, as described in
  /// https://docs.oracle.com/javase/tutorial/deployment/jar/manifestindex.html.
  static PathHashes parse(String mfContents) {
    final lines = mfContents.split('\n').map((line) => line.trimRight());
    final entries = <String, String>{};
    var currentHash = '';
    var currentName = '';
    for (final line in lines) {
      if (line.isEmpty && currentName.isNotEmpty && currentHash.isNotEmpty) {
        entries[currentName] = currentHash;
        currentHash = '';
        currentName = '';
      } else if (nameRegex.hasMatch(line)) {
        currentName = nameRegex.firstMatch(line)!.group(1)!;
      } else if (nameContinuedRegex.hasMatch(line)) {
        currentName += nameContinuedRegex.firstMatch(line)!.group(1)!;
      } else if (shaDigestRegex.hasMatch(line)) {
        currentHash = shaDigestRegex.firstMatch(line)!.group(1)!;
      }
    }

    if (currentName.isNotEmpty && currentHash.isNotEmpty) {
      entries[currentName] = currentHash;
    }

    return entries;
  }
}
