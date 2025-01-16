/// Extension on [String] to provide null or empty getter.
extension NullOrEmpty on String? {
  /// Returns `true` if this string is null or empty.
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}

/// Extension on [String] to provide an `isUpperCase` getter.
extension IsUpperCase on String {
  /// Returns `true` if this string is in uppercase.
  bool isUpperCase() => this == toUpperCase();
}
