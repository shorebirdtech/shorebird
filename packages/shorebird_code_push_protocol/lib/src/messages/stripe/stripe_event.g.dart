// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'stripe_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripeEvent<T> _$StripeEventFromJson<T>(Map<String, dynamic> json) =>
    $checkedCreate(
      'StripeEvent',
      json,
      ($checkedConvert) {
        final val = StripeEvent<T>(
          id: $checkedConvert('id', (v) => v as String),
          jsonData: $checkedConvert('data', (v) => v as Map<String, dynamic>),
        );
        return val;
      },
      fieldKeyMap: const {'jsonData': 'data'},
    );
