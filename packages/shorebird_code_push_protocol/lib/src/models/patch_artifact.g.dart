// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'patch_artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PatchArtifact _$PatchArtifactFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PatchArtifact',
      json,
      ($checkedConvert) {
        final val = PatchArtifact(
          patchNumber: $checkedConvert('patch_number', (v) => v as int),
          downloadUrl: $checkedConvert('download_url', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {
        'patchNumber': 'patch_number',
        'downloadUrl': 'download_url'
      },
    );

Map<String, dynamic> _$PatchArtifactToJson(PatchArtifact instance) =>
    <String, dynamic>{
      'patch_number': instance.patchNumber,
      'download_url': instance.downloadUrl,
      'hash': instance.hash,
    };
