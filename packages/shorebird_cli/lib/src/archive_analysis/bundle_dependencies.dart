// cspell:words aosp varint
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Path of the dependency metadata the Android Gradle Plugin writes into every
/// app bundle (unless disabled via `dependenciesInfo.includeInBundle`).
const bundleDependenciesPath =
    'BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb';

/// {@template dependency_version_change}
/// A Maven library whose resolved version differs between two app bundles.
/// {@endtemplate}
class DependencyVersionChange extends Equatable {
  /// {@macro dependency_version_change}
  const DependencyVersionChange({
    required this.name,
    required this.oldVersion,
    required this.newVersion,
  });

  /// The library's `group:artifact` (plus `:classifier`, if it has one).
  final String name;

  /// The version in the old bundle, or null if the library was added.
  final String? oldVersion;

  /// The version in the new bundle, or null if the library was removed.
  final String? newVersion;

  /// A one-line description, e.g. `com.example:lib 1.0.0 -> 1.0.1`.
  String describe() {
    if (oldVersion == null) return '$name $newVersion (added)';
    if (newVersion == null) return '$name $oldVersion (removed)';
    return '$name $oldVersion -> $newVersion';
  }

  @override
  List<Object?> get props => [name, oldVersion, newVersion];
}

/// Parses the `dependencies.pb` metadata from an app bundle into a map of
/// library name (`group:artifact[:classifier]`) to resolved version.
///
/// The file is an `AppDependencies` protocol buffer, defined in
/// `app_dependencies.proto` in AOSP's `platform/tools/base`
/// (`build-system/builder-model/src/main/proto/`).
/// Only the fields needed here are decoded:
///
/// ```proto
/// message AppDependencies { repeated Library library = 1; ... }
/// message Library {
///   oneof library_oneof { MavenLibrary maven_library = 1; } ...
/// }
/// message MavenLibrary {
///   string group_id = 1; string artifact_id = 2; string packaging = 3;
///   string classifier = 4; string version = 5;
/// }
/// ```
///
/// Throws a [FormatException] if [bytes] is not a valid protocol buffer.
Map<String, String> parseBundleDependencies(Uint8List bytes) {
  final versions = <String, String>{};
  for (final library in _fields(bytes).where((f) => f.number == 1)) {
    for (final maven in _fields(library.bytes).where((f) => f.number == 1)) {
      String? groupId;
      String? artifactId;
      String? classifier;
      String? version;
      for (final field in _fields(maven.bytes)) {
        switch (field.number) {
          case 1:
            groupId = field.string;
          case 2:
            artifactId = field.string;
          case 4:
            classifier = field.string;
          case 5:
            version = field.string;
        }
      }
      if (groupId == null || artifactId == null || version == null) continue;
      final name = [
        groupId,
        artifactId,
        if (classifier != null && classifier.isNotEmpty) classifier,
      ].join(':');
      versions[name] = version;
    }
  }
  return versions;
}

/// Returns the libraries whose versions differ between [oldVersions] and
/// [newVersions], sorted by name.
List<DependencyVersionChange> diffDependencyVersions(
  Map<String, String> oldVersions,
  Map<String, String> newVersions,
) {
  final names = {...oldVersions.keys, ...newVersions.keys}.toList()..sort();
  return [
    for (final name in names)
      if (oldVersions[name] != newVersions[name])
        DependencyVersionChange(
          name: name,
          oldVersion: oldVersions[name],
          newVersion: newVersions[name],
        ),
  ];
}

class _Field {
  const _Field(this.number, this.bytes);

  final int number;

  /// The payload of a length-delimited field, or empty for other wire types.
  final Uint8List bytes;

  String get string => utf8.decode(bytes);
}

/// Decodes the top-level fields of a protocol buffer message.
Iterable<_Field> _fields(Uint8List bytes) sync* {
  var offset = 0;

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (offset >= bytes.length || shift > 63) {
        throw const FormatException('Truncated varint');
      }
      final byte = bytes[offset++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) return result;
      shift += 7;
    }
  }

  while (offset < bytes.length) {
    final key = readVarint();
    final number = key >> 3;
    switch (key & 0x7) {
      case 0: // varint
        readVarint();
        yield _Field(number, Uint8List(0));
      case 1: // 64-bit
        offset += 8;
        yield _Field(number, Uint8List(0));
      case 2: // length-delimited
        final length = readVarint();
        if (offset + length > bytes.length) {
          throw const FormatException('Truncated length-delimited field');
        }
        yield _Field(
          number,
          Uint8List.sublistView(bytes, offset, offset + length),
        );
        offset += length;
      case 5: // 32-bit
        offset += 4;
        yield _Field(number, Uint8List(0));
      default:
        throw FormatException('Unsupported wire type in key $key');
    }
  }
  if (offset != bytes.length) {
    throw const FormatException('Truncated fixed-width field');
  }
}
