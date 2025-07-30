// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'stripe_subscription.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripeSubscription _$StripeSubscriptionFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'StripeSubscription',
      json,
      ($checkedConvert) {
        final val = StripeSubscription(
          id: $checkedConvert('id', (v) => v as String),
          cancelAtPeriodEnd: $checkedConvert(
            'cancel_at_period_end',
            (v) => v as bool,
          ),
          currentPeriodEnd: $checkedConvert(
            'current_period_end',
            (v) => const TimestampConverter().fromJson((v as num).toInt()),
          ),
          currentPeriodStart: $checkedConvert(
            'current_period_start',
            (v) => const TimestampConverter().fromJson((v as num).toInt()),
          ),
          customer: $checkedConvert('customer', (v) => v as String),
          startDate: $checkedConvert(
            'start_date',
            (v) => const TimestampConverter().fromJson((v as num).toInt()),
          ),
          status: $checkedConvert(
            'status',
            (v) => $enumDecode(_$StripeSubscriptionStatusEnumMap, v),
          ),
          items: $checkedConvert(
            'items',
            (v) => _subscriptionItemsFromJson(v as Map<String, dynamic>?),
          ),
          endedAt: $checkedConvert(
            'ended_at',
            (v) => _$JsonConverterFromJson<int, DateTime>(
              v,
              const TimestampConverter().fromJson,
            ),
          ),
          canceledAt: $checkedConvert(
            'canceled_at',
            (v) => _$JsonConverterFromJson<int, DateTime>(
              v,
              const TimestampConverter().fromJson,
            ),
          ),
          trialStart: $checkedConvert(
            'trial_start',
            (v) => _$JsonConverterFromJson<int, DateTime>(
              v,
              const TimestampConverter().fromJson,
            ),
          ),
          trialEnd: $checkedConvert(
            'trial_end',
            (v) => _$JsonConverterFromJson<int, DateTime>(
              v,
              const TimestampConverter().fromJson,
            ),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'cancelAtPeriodEnd': 'cancel_at_period_end',
        'currentPeriodEnd': 'current_period_end',
        'currentPeriodStart': 'current_period_start',
        'startDate': 'start_date',
        'endedAt': 'ended_at',
        'canceledAt': 'canceled_at',
        'trialStart': 'trial_start',
        'trialEnd': 'trial_end',
      },
    );

const _$StripeSubscriptionStatusEnumMap = {
  StripeSubscriptionStatus.active: 'active',
  StripeSubscriptionStatus.pastDue: 'past_due',
  StripeSubscriptionStatus.unpaid: 'unpaid',
  StripeSubscriptionStatus.canceled: 'canceled',
  StripeSubscriptionStatus.incomplete: 'incomplete',
  StripeSubscriptionStatus.incompleteExpired: 'incomplete_expired',
  StripeSubscriptionStatus.trialing: 'trialing',
  StripeSubscriptionStatus.paused: 'paused',
};

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) => json == null ? null : fromJson(json as Json);
