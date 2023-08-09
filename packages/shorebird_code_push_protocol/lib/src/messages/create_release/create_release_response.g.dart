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
          release: $checkedConvert(
              'release', (v) => Release.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );

Map<String, dynamic> _$CreateReleaseResponseToJson(
        CreateReleaseResponse instance) =>
    <String, dynamic>{
      'release': instance.release.toJson(),
    };
