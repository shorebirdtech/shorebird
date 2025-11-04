// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_release_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetReleaseResponse _$GetReleaseResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GetReleaseResponse', json, ($checkedConvert) {
      final val = GetReleaseResponse(
        release: $checkedConvert(
          'release',
          (v) => Release.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$GetReleaseResponseToJson(GetReleaseResponse instance) =>
    <String, dynamic>{'release': instance.release.toJson()};
