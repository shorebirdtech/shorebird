// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'artifact_upload_urls.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ArtifactUploadUrls _$ArtifactUploadUrlsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ArtifactUploadUrls',
      json,
      ($checkedConvert) {
        final val = ArtifactUploadUrls(
          android: $checkedConvert(
              'android',
              (v) => AndroidArtifactUploadUrls.fromJson(
                  v as Map<String, dynamic>)),
        );
        return val;
      },
    );

Map<String, dynamic> _$ArtifactUploadUrlsToJson(ArtifactUploadUrls instance) =>
    <String, dynamic>{
      'android': instance.android.toJson(),
    };

AndroidArtifactUploadUrls _$AndroidArtifactUploadUrlsFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'AndroidArtifactUploadUrls',
      json,
      ($checkedConvert) {
        final val = AndroidArtifactUploadUrls(
          x86: $checkedConvert('x86', (v) => v as String),
          aarch64: $checkedConvert('aarch64', (v) => v as String),
          arm: $checkedConvert('arm', (v) => v as String),
        );
        return val;
      },
    );

Map<String, dynamic> _$AndroidArtifactUploadUrlsToJson(
        AndroidArtifactUploadUrls instance) =>
    <String, dynamic>{
      'x86': instance.x86,
      'aarch64': instance.aarch64,
      'arm': instance.arm,
    };
