// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'stripe_payment_method.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripePaymentMethod _$StripePaymentMethodFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StripePaymentMethod', json, ($checkedConvert) {
      final val = StripePaymentMethod(
        id: $checkedConvert('id', (v) => v as String),
        card: $checkedConvert(
          'card',
          (v) => v == null
              ? null
              : StripePaymentMethodCard.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

StripePaymentMethodCard _$StripePaymentMethodCardFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('StripePaymentMethodCard', json, ($checkedConvert) {
  final val = StripePaymentMethodCard(
    country: $checkedConvert('country', (v) => v as String?),
  );
  return val;
});
