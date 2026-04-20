import 'package:collection/collection.dart';

/// Runs [build] to construct a `fromJson`-parsed value of type [T],
/// converting any `TypeError` (e.g. an unexpected null or a cast
/// failure on a required field) into a `FormatException` that names
/// the class and includes the offending JSON. Generated `fromJson`
/// factories delegate to this so callers that catch `Exception`
/// treat malformed bodies as a parse error, not a crash.
T parseFromJson<T>(
  String className,
  Map<String, dynamic> json,
  T Function() build,
) {
  try {
    return build();
  } on TypeError catch (error) {
    throw FormatException('Failed to parse $className from JSON: $error', json);
  }
}

/// Check if two nullable lists are deeply equal.
bool listsEqual<T>(List<T>? a, List<T>? b) {
  final deepEquals = const DeepCollectionEquality().equals;
  return deepEquals(a, b);
}

/// Check if two nullable maps are deeply equal.
bool mapsEqual<K, V>(Map<K, V>? a, Map<K, V>? b) {
  final deepEquals = const DeepCollectionEquality().equals;
  return deepEquals(a, b);
}

/// A deep hash of a nullable list — consistent with [listsEqual].
/// Two lists that compare equal under [listsEqual] produce the same
/// hash. Null hashes to 0.
int listHash<T>(List<T>? list) {
  if (list == null) return 0;
  return const DeepCollectionEquality().hash(list);
}

/// A deep hash of a nullable map — consistent with [mapsEqual].
/// Two maps that compare equal under [mapsEqual] produce the same
/// hash. Null hashes to 0.
int mapHash<K, V>(Map<K, V>? map) {
  if (map == null) return 0;
  return const DeepCollectionEquality().hash(map);
}
