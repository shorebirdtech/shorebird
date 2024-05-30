extension NullOrEmtpy on String? {
  /// Returns `true` if this string is null or empty.
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}

extension IsUpperCase on String {
  /// Returns `true` if this string is in uppercase.
  bool isUpperCase() => this == toUpperCase();
}
