// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'subscription.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Subscription _$SubscriptionFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'Subscription',
      json,
      ($checkedConvert) {
        final val = Subscription(
          plan: $checkedConvert(
              'plan', (v) => ShorebirdPlan.fromJson(v as Map<String, dynamic>)),
          cost: $checkedConvert('cost', (v) => v as int),
          paidThroughDate: $checkedConvert('paid_through_date',
              (v) => const TimestampConverter().fromJson(v as int)),
          willRenew: $checkedConvert('will_renew', (v) => v as bool),
        );
        return val;
      },
      fieldKeyMap: const {
        'paidThroughDate': 'paid_through_date',
        'willRenew': 'will_renew'
      },
    );

Map<String, dynamic> _$SubscriptionToJson(Subscription instance) =>
    <String, dynamic>{
      'plan': instance.plan.toJson(),
      'cost': instance.cost,
      'paid_through_date':
          const TimestampConverter().toJson(instance.paidThroughDate),
      'will_renew': instance.willRenew,
    };
