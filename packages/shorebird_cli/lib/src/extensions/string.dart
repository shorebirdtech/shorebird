extension NullOrEmtpy on String? {
  /// Returns `true` if this string is null or empty.
  bool get isNullOrEmpty => this == null || this!.isEmpty;

  String? get toKebabCase {
    final exp = RegExp('(?<=[a-z])[A-Z]');
    return this?.replaceAllMapped(exp, (m) => '-${m.group(0)}').toLowerCase();
  }
}
