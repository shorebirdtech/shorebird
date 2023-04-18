// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'stripe_customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripeCustomer _$StripeCustomerFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'StripeCustomer',
      json,
      ($checkedConvert) {
        final val = StripeCustomer(
          id: $checkedConvert('id', (v) => v as String),
          name: $checkedConvert('name', (v) => v as String?),
          email: $checkedConvert('email', (v) => v as String?),
          subscriptions: $checkedConvert('subscriptions',
              (v) => _subscriptionsFromJson(v as Map<String, dynamic>?)),
        );
        return val;
      },
    );
