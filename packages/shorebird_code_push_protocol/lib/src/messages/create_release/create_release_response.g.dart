// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_release_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateReleaseResponse _$CreateReleaseResponseFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateReleaseResponse',
      json,
      ($checkedConvert) {
        final val = CreateReleaseResponse(
          id: $checkedConvert('id', (v) => v as int),
          appId: $checkedConvert('app_id', (v) => v as String),
          version: $checkedConvert('version', (v) => v as String),
          flutterRevision:
              $checkedConvert('flutter_revision', (v) => v as String),
          displayName: $checkedConvert('display_name', (v) => v as String?),
          artifactUploadUrls: $checkedConvert('artifact_upload_urls',
              (v) => ArtifactUploadUrls.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {
        'appId': 'app_id',
        'flutterRevision': 'flutter_revision',
        'displayName': 'display_name',
        'artifactUploadUrls': 'artifact_upload_urls'
      },
    );

Map<String, dynamic> _$CreateReleaseResponseToJson(
        CreateReleaseResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'app_id': instance.appId,
      'version': instance.version,
      'flutter_revision': instance.flutterRevision,
      'display_name': instance.displayName,
      'artifact_upload_urls': instance.artifactUploadUrls.toJson(),
    };
