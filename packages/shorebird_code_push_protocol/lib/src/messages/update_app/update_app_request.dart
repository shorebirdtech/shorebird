import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template update_app_request}
/// The request body for PATCH /apps/{appId}.
/// {@endtemplate}
@immutable
class UpdateAppRequest {
  /// {@macro update_app_request}
  const UpdateAppRequest({
    required this.name,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdateAppRequest].
  factory UpdateAppRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UpdateAppRequest',
      json,
      () => UpdateAppRequest(
        name: json['name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdateAppRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UpdateAppRequest.fromJson(json);
  }

  /// The new display name of the app: at least 1 and at most 256
  /// characters.
  final String name;

  /// Converts a [UpdateAppRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }

  @override
  int get hashCode => name.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateAppRequest && name == other.name;
  }
}
