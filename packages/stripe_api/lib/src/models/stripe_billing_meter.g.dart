// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'stripe_billing_meter.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripeBillingMeter _$StripeBillingMeterFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'StripeBillingMeter',
      json,
      ($checkedConvert) {
        final val = StripeBillingMeter(
          id: $checkedConvert('id', (v) => v as String),
          displayName: $checkedConvert('display_name', (v) => v as String),
          eventName: $checkedConvert('event_name', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {
        'displayName': 'display_name',
        'eventName': 'event_name',
      },
    );
