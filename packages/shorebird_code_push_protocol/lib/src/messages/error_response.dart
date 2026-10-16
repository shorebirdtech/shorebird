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
    this.documentationUrl,
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
        documentationUrl: maybeParseUri(json['documentation_url'] as String?),
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

  /// A page that documents this API and its errors.
  final Uri? documentationUrl;

  /// Converts an [ErrorResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'details': ?details,
      'documentation_url': ?documentationUrl?.toString(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    code,
    message,
    details,
    documentationUrl,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ErrorResponse &&
        code == other.code &&
        message == other.message &&
        details == other.details &&
        documentationUrl == other.documentationUrl;
  }
}
