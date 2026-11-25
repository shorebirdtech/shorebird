import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/artifact_upload_method.dart';

/// {@template create_symbols_response}
/// Where to upload a symbol file's bytes.
/// {@endtemplate}
@immutable
class CreateSymbolsResponse {
  /// {@macro create_symbols_response}
  const CreateSymbolsResponse({
    required this.url,
    required this.uploadMethod,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateSymbolsResponse].
  factory CreateSymbolsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateSymbolsResponse',
      json,
      () => CreateSymbolsResponse(
        url: json['url'] as String,
        uploadMethod: ArtifactUploadMethod.fromJson(
          json['upload_method'] as String,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateSymbolsResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateSymbolsResponse.fromJson(json);
  }

  /// The resumable upload session URI for the symbol file.
  final String url;

  /// Always `resumable`. A session carries the object's retention
  /// metadata, which a signed multipart URL cannot, so there is no
  /// multipart path for symbols.
  final ArtifactUploadMethod uploadMethod;

  /// Converts a [CreateSymbolsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'upload_method': uploadMethod.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    url,
    uploadMethod,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateSymbolsResponse &&
        url == other.url &&
        uploadMethod == other.uploadMethod;
  }
}
