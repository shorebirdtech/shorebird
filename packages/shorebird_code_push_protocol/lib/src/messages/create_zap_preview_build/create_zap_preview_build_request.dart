import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_payload_format.dart';

/// {@template create_zap_preview_build_request}
/// The request body for POST /zap/previews/{previewId}/builds.
/// {@endtemplate}
@immutable
class CreateZapPreviewBuildRequest {
  /// {@macro create_zap_preview_build_request}
  const CreateZapPreviewBuildRequest({
    required this.payloadFormat,
    required this.size,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateZapPreviewBuildRequest].
  factory CreateZapPreviewBuildRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateZapPreviewBuildRequest',
      json,
      () => CreateZapPreviewBuildRequest(
        payloadFormat: ZapPayloadFormat.fromJson(
          json['payloadFormat'] as String,
        ),
        size: json['size'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateZapPreviewBuildRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateZapPreviewBuildRequest.fromJson(json);
  }

  /// The format of a preview build's payload.
  final ZapPayloadFormat payloadFormat;

  /// A positive integer: the payload's size in bytes, at most 128 MiB
  /// (134217728). Bound into the upload session, so an upload of any
  /// other size fails.
  final int size;

  /// Converts a [CreateZapPreviewBuildRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'payloadFormat': payloadFormat.toJson(),
      'size': size,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    payloadFormat,
    size,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateZapPreviewBuildRequest &&
        payloadFormat == other.payloadFormat &&
        size == other.size;
  }
}
