// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'full_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FullUser _$FullUserFromJson(Map<String, dynamic> json) => $checkedCreate(
      'FullUser',
      json,
      ($checkedConvert) {
        final val = FullUser(
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          email: $checkedConvert('email', (v) => v as String),
          jwtIssuer: $checkedConvert('jwt_issuer', (v) => v as String),
          hasActiveSubscription: $checkedConvert(
              'has_active_subscription', (v) => v as bool? ?? false),
          displayName: $checkedConvert('display_name', (v) => v as String?),
          stripeCustomerId:
              $checkedConvert('stripe_customer_id', (v) => v as String?),
          patchOverageLimit: $checkedConvert(
              'patch_overage_limit', (v) => (v as num?)?.toInt()),
        );
        return val;
      },
      fieldKeyMap: const {
        'jwtIssuer': 'jwt_issuer',
        'hasActiveSubscription': 'has_active_subscription',
        'displayName': 'display_name',
        'stripeCustomerId': 'stripe_customer_id',
        'patchOverageLimit': 'patch_overage_limit'
      },
    );

Map<String, dynamic> _$FullUserToJson(FullUser instance) => <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'display_name': instance.displayName,
      'has_active_subscription': instance.hasActiveSubscription,
      'stripe_customer_id': instance.stripeCustomerId,
      'jwt_issuer': instance.jwtIssuer,
      'patch_overage_limit': instance.patchOverageLimit,
    };
