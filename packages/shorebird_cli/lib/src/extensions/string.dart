extension NullOrEmtpy on String? {
  /// Returns `true` if this string is null or empty.
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}

extension Case on String {
  /// returns `sentance-case` (kebab case)
  String get toKebabCase {
    final exp = RegExp('(?<=[a-z])[A-Z]');
    return replaceAllMapped(exp, (m) => '-${m.group(0)}')
        .toLowerCase()
        .replaceAll("_", "-");
  }
}
