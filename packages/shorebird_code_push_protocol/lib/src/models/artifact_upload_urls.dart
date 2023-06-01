import 'package:json_annotation/json_annotation.dart';

part 'artifact_upload_urls.g.dart';

/// {@template artifact_upload_urls}
/// An object that contains signed upload URLs for artifacts.
/// {@endtemplate}
@JsonSerializable()
class ArtifactUploadUrls {
  /// {@macro artifact_upload_urls}
  const ArtifactUploadUrls({required this.android});

  /// Converts a Map<String, dynamic> to an [ArtifactUploadUrls]
  factory ArtifactUploadUrls.fromJson(Map<String, dynamic> json) =>
      _$ArtifactUploadUrlsFromJson(json);

  /// Converts a [ArtifactUploadUrls] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$ArtifactUploadUrlsToJson(this);

  /// The upload urls for Android artifacts.
  final AndroidArtifactUploadUrls android;
}

/// {@template android_artifact_upload_urls}
/// An object that contains signed upload URLs for Android artifacts.
/// {@endtemplate}
@JsonSerializable()
class AndroidArtifactUploadUrls {
  /// {@macro android_artifact_upload_urls}
  const AndroidArtifactUploadUrls({
    required this.x86,
    required this.aarch64,
    required this.arm,
  });

  /// Converts a Map<String, dynamic> to an [AndroidArtifactUploadUrls]
  factory AndroidArtifactUploadUrls.fromJson(Map<String, dynamic> json) =>
      _$AndroidArtifactUploadUrlsFromJson(json);

  /// Converts a [AndroidArtifactUploadUrls] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$AndroidArtifactUploadUrlsToJson(this);

  final String x86;
  final String aarch64;
  final String arm;
}
