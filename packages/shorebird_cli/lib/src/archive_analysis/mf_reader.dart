import 'dart:io';

import 'package:meta/meta.dart';

/// {@template mf_entry}
/// A single entry from an .MF file.
/// {@endtemplate}
@immutable
class MfEntry {
  /// {@macro mf_entry}
  const MfEntry({
    required this.name,
    required this.sha256Digest,
  });

  /// Contents of the `Name` field.
  final String name;

  /// Contents of the `SHA-256-Digest` field.
  final String sha256Digest;

  @override
  String toString() => 'MfEntry(name: $name, sha256Digest: $sha256Digest)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MfEntry &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          sha256Digest == other.sha256Digest;

  @override
  int get hashCode => Object.hashAll([name, sha256Digest]);
}

/// Parses a .MF file into a list of [MfEntry]s.
class MfReader {
  static final nameRegex = RegExp(r'^Name: (.+)$');
  static final nameContinuedRegex = RegExp(r'^ (.+)$');
  static final shaDigestRegex = RegExp(r'^SHA-256-Digest: (.+)$');

  /// Parses the content of [mfFile] into a list of [MfEntry]s.
  ///
  /// [mfFile] should be a JAR manifest file, as described in
  /// https://docs.oracle.com/javase/tutorial/deployment/jar/manifestindex.html.
  static List<MfEntry> read(File mfFile) => parse(mfFile.readAsStringSync());

  /// Parses the contents [mfContents] file into a list of [MfEntry]s.
  ///
  /// [mfContents] should be a JAR manifest file, as described in
  /// https://docs.oracle.com/javase/tutorial/deployment/jar/manifestindex.html.
  static List<MfEntry> parse(String mfContents) {
    final lines = mfContents.split('\n').map((line) => line.trimRight());
    final entries = <MfEntry>[];
    var currentHash = '';
    var currentName = '';
    for (final line in lines) {
      if (line.isEmpty && currentName.isNotEmpty && currentHash.isNotEmpty) {
        entries.add(MfEntry(name: currentName, sha256Digest: currentHash));
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
      entries.add(MfEntry(name: currentName, sha256Digest: currentHash));
    }

    return entries;
  }
}
