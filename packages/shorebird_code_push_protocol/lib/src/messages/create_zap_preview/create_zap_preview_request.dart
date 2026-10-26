import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_zap_preview_request}
/// The request body for POST /zap/previews.
/// {@endtemplate}
@immutable
class CreateZapPreviewRequest {
  /// {@macro create_zap_preview_request}
  const CreateZapPreviewRequest({
    this.name,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateZapPreviewRequest].
  factory CreateZapPreviewRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateZapPreviewRequest',
      json,
      () => CreateZapPreviewRequest(
        name: json['name'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateZapPreviewRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateZapPreviewRequest.fromJson(json);
  }

  /// The preview's display name, trimmed, at most 64 characters.
  /// Absent, blank or not a
  /// string, the preview is named `Untitled`.
  final String? name;

  /// Converts a [CreateZapPreviewRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': ?name,
    };
  }

  @override
  int get hashCode => name.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateZapPreviewRequest && name == other.name;
  }
}
