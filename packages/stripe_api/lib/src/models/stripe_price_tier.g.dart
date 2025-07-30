// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'stripe_price_tier.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripePriceTier _$StripePriceTierFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'StripePriceTier',
  json,
  ($checkedConvert) {
    final val = StripePriceTier(
      flatAmount: $checkedConvert('flat_amount', (v) => (v as num?)?.toInt()),
      flatAmountDecimal: $checkedConvert(
        'flat_amount_decimal',
        (v) => v as String?,
      ),
      unitAmount: $checkedConvert('unit_amount', (v) => (v as num?)?.toInt()),
      unitAmountDecimal: $checkedConvert(
        'unit_amount_decimal',
        (v) => v as String?,
      ),
      upTo: $checkedConvert('up_to', (v) => (v as num?)?.toInt()),
    );
    return val;
  },
  fieldKeyMap: const {
    'flatAmount': 'flat_amount',
    'flatAmountDecimal': 'flat_amount_decimal',
    'unitAmount': 'unit_amount',
    'unitAmountDecimal': 'unit_amount_decimal',
    'upTo': 'up_to',
  },
);
