// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'stripe_checkout_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripeCheckoutSession _$StripeCheckoutSessionFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'StripeCheckoutSession',
      json,
      ($checkedConvert) {
        final val = StripeCheckoutSession(
          customerId: $checkedConvert('customer', (v) => v as String),
          metadata:
              $checkedConvert('metadata', (v) => v as Map<String, dynamic>),
        );
        return val;
      },
      fieldKeyMap: const {'customerId': 'customer'},
    );
