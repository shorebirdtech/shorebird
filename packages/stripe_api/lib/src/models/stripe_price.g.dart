// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'stripe_price.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripePrice _$StripePriceFromJson(Map<String, dynamic> json) => $checkedCreate(
  'StripePrice',
  json,
  ($checkedConvert) {
    final val = StripePrice(
      id: $checkedConvert('id', (v) => v as String),
      productId: $checkedConvert('product', (v) => v as String),
      currency: $checkedConvert('currency', (v) => v as String),
      billingScheme: $checkedConvert(
        'billing_scheme',
        (v) => $enumDecode(_$BillingSchemeEnumMap, v),
      ),
      unitAmount: $checkedConvert('unit_amount', (v) => (v as num?)?.toInt()),
      unitAmountDecimal: $checkedConvert(
        'unit_amount_decimal',
        (v) => v == null ? null : Decimal.fromJson(v as String),
      ),
      tiers: $checkedConvert(
        'tiers',
        (v) => (v as List<dynamic>?)
            ?.map((e) => StripePriceTier.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      usageType: $checkedConvert(
        'usage_type',
        (v) => $enumDecodeNullable(_$UsageTypeEnumMap, v),
        readValue: StripePrice._readUsageType,
      ),
      metadata: $checkedConvert(
        'metadata',
        (v) => v as Map<String, dynamic>? ?? const {},
      ),
      meterId: $checkedConvert(
        'meter_id',
        (v) => v as String?,
        readValue: StripePrice._readMeterId,
      ),
      nickname: $checkedConvert('nickname', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {
    'productId': 'product',
    'billingScheme': 'billing_scheme',
    'unitAmount': 'unit_amount',
    'unitAmountDecimal': 'unit_amount_decimal',
    'usageType': 'usage_type',
    'meterId': 'meter_id',
  },
);

const _$BillingSchemeEnumMap = {
  BillingScheme.perUnit: 'per_unit',
  BillingScheme.tiered: 'tiered',
};

const _$UsageTypeEnumMap = {
  UsageType.licensed: 'licensed',
  UsageType.metered: 'metered',
};
