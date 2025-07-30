// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'stripe_subscription_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripeSubscriptionItem _$StripeSubscriptionItemFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('StripeSubscriptionItem', json, ($checkedConvert) {
  final val = StripeSubscriptionItem(
    id: $checkedConvert('id', (v) => v as String),
    price: $checkedConvert(
      'price',
      (v) => StripePrice.fromJson(v as Map<String, dynamic>),
    ),
    quantity: $checkedConvert('quantity', (v) => (v as num?)?.toInt()),
  );
  return val;
});
