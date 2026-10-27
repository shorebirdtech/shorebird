/// The order audit log entries are listed in.
enum AuditLogOrder {
  /// Newest first.
  desc._('desc'),

  /// Oldest first, holding back entries younger than 60 seconds, for polling.
  asc._('asc');

  const AuditLogOrder._(this.value);

  /// Creates a AuditLogOrder from a json value.
  factory AuditLogOrder.fromJson(String json) {
    return AuditLogOrder.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException('Unknown AuditLogOrder value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static AuditLogOrder? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return AuditLogOrder.fromJson(json);
  }

  /// The value of the enum.  This is the exact value
  /// from the OpenAPI spec and will be used for network transport.
  final String value;

  /// Converts the enum to its json value.
  String toJson() => value;

  /// Returns the string form of the enum.
  @override
  String toString() => value;
}
