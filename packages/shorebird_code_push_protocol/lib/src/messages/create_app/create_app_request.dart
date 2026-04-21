import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_app_request}
/// The request body for POST /apps.
/// {@endtemplate}
@immutable
class CreateAppRequest {
  /// {@macro create_app_request}
  const CreateAppRequest({
    required this.displayName,
    required this.organizationId,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateAppRequest].
  factory CreateAppRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateAppRequest',
      json,
      () => CreateAppRequest(
        displayName: json['display_name'] as String,
        organizationId: json['organization_id'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateAppRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateAppRequest.fromJson(json);
  }

  /// The display name of the app.
  final String displayName;

  /// The id of organization that this app will belong to.
  final int organizationId;

  /// Converts a [CreateAppRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'display_name': displayName,
      'organization_id': organizationId,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    displayName,
    organizationId,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateAppRequest &&
        displayName == other.displayName &&
        organizationId == other.organizationId;
  }
}
