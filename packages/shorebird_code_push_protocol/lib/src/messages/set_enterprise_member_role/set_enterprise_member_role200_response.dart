import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_role.dart';

@immutable
class SetEnterpriseMemberRole200Response {
  const SetEnterpriseMemberRole200Response({
    required this.userId,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [SetEnterpriseMemberRole200Response].
  factory SetEnterpriseMemberRole200Response.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'SetEnterpriseMemberRole200Response',
      json,
      () => SetEnterpriseMemberRole200Response(
        userId: json['user_id'] as int,
        role: EnterpriseRole.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static SetEnterpriseMemberRole200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return SetEnterpriseMemberRole200Response.fromJson(json);
  }

  final int userId;

  /// A person's role in an enterprise.
  final EnterpriseRole role;

  /// Converts a [SetEnterpriseMemberRole200Response]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    userId,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SetEnterpriseMemberRole200Response &&
        userId == other.userId &&
        role == other.role;
  }
}
