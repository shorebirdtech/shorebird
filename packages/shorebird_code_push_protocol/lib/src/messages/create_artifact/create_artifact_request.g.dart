// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_artifact_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateArtifactRequest _$CreateArtifactRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateArtifactRequest',
      json,
      ($checkedConvert) {
        final val = CreateArtifactRequest(
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert('platform', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
          size: $checkedConvert(
              'size', (v) => CreateArtifactRequest._parseStringToInt(v)),
        );
        return val;
      },
    );
