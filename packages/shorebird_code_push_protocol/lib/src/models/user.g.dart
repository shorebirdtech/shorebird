// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => $checkedCreate(
      'User',
      json,
      ($checkedConvert) {
        final val = User(
          id: $checkedConvert('id', (v) => v as int),
          email: $checkedConvert('email', (v) => v as String),
          hasActiveSubscription: $checkedConvert(
              'has_active_subscription', (v) => v as bool? ?? false),
          displayName: $checkedConvert('display_name', (v) => v as String?),
          stripeCustomerId:
              $checkedConvert('stripe_customer_id', (v) => v as String?),
          tosAcceptedAt: $checkedConvert('tos_accepted_at',
              (v) => v == null ? null : DateTime.parse(v as String)),
        );
        return val;
      },
      fieldKeyMap: const {
        'hasActiveSubscription': 'has_active_subscription',
        'displayName': 'display_name',
        'stripeCustomerId': 'stripe_customer_id',
        'tosAcceptedAt': 'tos_accepted_at'
      },
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'display_name': instance.displayName,
      'has_active_subscription': instance.hasActiveSubscription,
      'stripe_customer_id': instance.stripeCustomerId,
      'tos_accepted_at': instance.tosAcceptedAt?.toIso8601String(),
    };
