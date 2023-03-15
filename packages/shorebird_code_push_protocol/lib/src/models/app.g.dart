// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'app.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

App _$AppFromJson(Map<String, dynamic> json) => $checkedCreate(
      'App',
      json,
      ($checkedConvert) {
        final val = App(
          appId: $checkedConvert('app_id', (v) => v as String),
          releases: $checkedConvert(
              'releases',
              (v) => (v as List<dynamic>?)
                  ?.map((e) => Release.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
      fieldKeyMap: const {'appId': 'app_id'},
    );

Map<String, dynamic> _$AppToJson(App instance) => <String, dynamic>{
      'app_id': instance.appId,
      'releases': instance.releases.map((e) => e.toJson()).toList(),
    };
