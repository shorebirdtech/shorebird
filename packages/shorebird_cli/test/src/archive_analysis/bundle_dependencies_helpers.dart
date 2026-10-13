// cspell:words varint
import 'dart:convert';
import 'dart:typed_data';

/// Encodes a length-delimited protocol buffer field.
List<int> protoField(int number, List<int> payload) => [
  ...protoVarint(number << 3 | 2),
  ...protoVarint(payload.length),
  ...payload,
];

/// Encodes [value] as a protocol buffer varint.
List<int> protoVarint(int value) {
  final bytes = <int>[];
  var remaining = value;
  while (remaining >= 0x80) {
    bytes.add(remaining & 0x7f | 0x80);
    remaining >>= 7;
  }
  return bytes..add(remaining);
}

/// Encodes an `AppDependencies.library` entry for a Maven library.
List<int> mavenLibrary(
  String group,
  String artifact,
  String version, {
  String? classifier,
}) => protoField(
  1,
  protoField(1, [
    ...protoField(1, utf8.encode(group)),
    ...protoField(2, utf8.encode(artifact)),
    ...protoField(3, utf8.encode('aar')),
    if (classifier != null) ...protoField(4, utf8.encode(classifier)),
    ...protoField(5, utf8.encode(version)),
  ]),
);

/// Encodes an `AppDependencies` message from [libraries].
Uint8List appDependencies(List<List<int>> libraries) =>
    Uint8List.fromList(libraries.expand((l) => l).toList());
