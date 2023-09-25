// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_releases_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetReleasesResponse _$GetReleasesResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'GetReleasesResponse',
      json,
      ($checkedConvert) {
        final val = GetReleasesResponse(
          releases: $checkedConvert(
              'releases',
              (v) => (v as List<dynamic>)
                  .map((e) => Release.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$GetReleasesResponseToJson(
        GetReleasesResponse instance) =>
    <String, dynamic>{
      'releases': instance.releases.map((e) => e.toJson()).toList(),
    };
