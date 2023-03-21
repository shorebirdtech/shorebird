import 'package:json_annotation/json_annotation.dart';

part 'error_response.g.dart';

/// {@template error_response}
/// Standard error response body from the Shorebird Code Push API.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class ErrorResponse {
  /// {@macro error_response}
  const ErrorResponse({
    required this.code,
    required this.message,
    this.details,
  });

  /// Converts a [Map] to [ErrorResponse].
  factory ErrorResponse.fromJson(Map<String, dynamic> json) =>
      _$ErrorResponseFromJson(json);

  /// The unique error code.
  final String code;

  /// Human-readable error message.
  final String message;

  /// Optional details associated with the error.
  final String? details;
}
