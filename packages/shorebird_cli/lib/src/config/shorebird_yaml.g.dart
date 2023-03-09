// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type

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
          allowedKeys: const ['product_id'],
        );
        final val = ShorebirdYaml(
          productId: $checkedConvert('product_id', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'productId': 'product_id'},
    );
