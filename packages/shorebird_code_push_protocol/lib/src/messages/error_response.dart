import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template error_response}
/// Standard error response body from the Shorebird CodePush API.
/// {@endtemplate}
@immutable
class ErrorResponse {
  /// {@macro error_response}
  const ErrorResponse({
    required this.code,
    required this.message,
    this.details,
  });

  /// Converts a `Map<String, dynamic>` to an [ErrorResponse].
  factory ErrorResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ErrorResponse',
      json,
      () => ErrorResponse(
        code: json['code'] as String,
        message: json['message'] as String,
        details: json['details'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ErrorResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ErrorResponse.fromJson(json);
  }

  /// The unique error code.
  final String code;

  /// Human-readable error message.
  final String message;

  /// Optional details associated with the error.
  final String? details;

  /// Converts an [ErrorResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'details': details,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    code,
    message,
    details,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ErrorResponse &&
        code == other.code &&
        message == other.message &&
        details == other.details;
  }
}
