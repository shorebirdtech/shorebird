// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_release_patches_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetReleasePatchesResponse _$GetReleasePatchesResponseFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'GetReleasePatchesResponse',
      json,
      ($checkedConvert) {
        final val = GetReleasePatchesResponse(
          patches: $checkedConvert(
              'patches',
              (v) => (v as Map<String, dynamic>).map(
                    (k, e) => MapEntry(
                        int.parse(k),
                        (e as List<dynamic>)
                            .map((e) => PatchArtifact.fromJson(
                                e as Map<String, dynamic>))
                            .toList()),
                  )),
        );
        return val;
      },
    );

Map<String, dynamic> _$GetReleasePatchesResponseToJson(
        GetReleasePatchesResponse instance) =>
    <String, dynamic>{
      'patches': instance.patches.map(
          (k, e) => MapEntry(k.toString(), e.map((e) => e.toJson()).toList())),
    };
