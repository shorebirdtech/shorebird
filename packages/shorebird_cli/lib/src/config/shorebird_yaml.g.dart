// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type, unnecessary_lambdas

part of 'shorebird_yaml.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ShorebirdYaml _$ShorebirdYamlFromJson(Map json) => $checkedCreate(
      'ShorebirdYaml',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          allowedKeys: const ['app_id', 'flavors', 'base_url', 'auto_update'],
        );
        final val = ShorebirdYaml(
          appId: $checkedConvert('app_id', (v) => v as String),
          flavors: $checkedConvert(
              'flavors',
              (v) => (v as Map?)?.map(
                    (k, e) => MapEntry(k as String, e as String),
                  )),
          baseUrl: $checkedConvert('base_url', (v) => v as String?),
          autoUpdate: $checkedConvert('auto_update', (v) => v as bool?),
        );
        return val;
      },
      fieldKeyMap: const {
        'appId': 'app_id',
        'baseUrl': 'base_url',
        'autoUpdate': 'auto_update'
      },
    );
