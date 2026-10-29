import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

@immutable
class EnterpriseAppSummary {
  const EnterpriseAppSummary({
    required this.id,
    required this.displayName,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseAppSummary].
  factory EnterpriseAppSummary.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseAppSummary',
      json,
      () => EnterpriseAppSummary(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseAppSummary? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseAppSummary.fromJson(json);
  }

  final String id;
  final String displayName;

  /// Converts an [EnterpriseAppSummary] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    displayName,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseAppSummary &&
        id == other.id &&
        displayName == other.displayName;
  }
}
