// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'release_patch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReleasePatch _$ReleasePatchFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ReleasePatch',
      json,
      ($checkedConvert) {
        final val = ReleasePatch(
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          number: $checkedConvert('number', (v) => (v as num).toInt()),
          channel: $checkedConvert('channel', (v) => v as String?),
          artifacts: $checkedConvert(
              'artifacts',
              (v) => (v as List<dynamic>)
                  .map((e) => PatchArtifact.fromJson(e as Map<String, dynamic>))
                  .toList()),
          isRolledBack: $checkedConvert('is_rolled_back', (v) => v as bool),
        );
        return val;
      },
      fieldKeyMap: const {'isRolledBack': 'is_rolled_back'},
    );

Map<String, dynamic> _$ReleasePatchToJson(ReleasePatch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'number': instance.number,
      'channel': instance.channel,
      'artifacts': instance.artifacts.map((e) => e.toJson()).toList(),
      'is_rolled_back': instance.isRolledBack,
    };
