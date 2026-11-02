import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

@immutable
class AddEnterpriseOrganizationMemberRequest {
  const AddEnterpriseOrganizationMemberRequest({
    required this.userId,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an
  /// [AddEnterpriseOrganizationMemberRequest].
  factory AddEnterpriseOrganizationMemberRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'AddEnterpriseOrganizationMemberRequest',
      json,
      () => AddEnterpriseOrganizationMemberRequest(
        userId: json['user_id'] as int,
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AddEnterpriseOrganizationMemberRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return AddEnterpriseOrganizationMemberRequest.fromJson(json);
  }

  final int userId;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [AddEnterpriseOrganizationMemberRequest]
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
    return other is AddEnterpriseOrganizationMemberRequest &&
        userId == other.userId &&
        role == other.role;
  }
}
