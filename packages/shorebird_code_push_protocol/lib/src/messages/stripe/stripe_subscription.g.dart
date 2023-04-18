// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

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
          cancelAtPeriodEnd:
              $checkedConvert('cancel_at_period_end', (v) => v as bool),
          currentPeriodEnd: $checkedConvert('current_period_end',
              (v) => const TimestampConverter().fromJson(v as int)),
          currentPeriodStart: $checkedConvert('current_period_start',
              (v) => const TimestampConverter().fromJson(v as int)),
          customer: $checkedConvert('customer', (v) => v as String),
          startDate: $checkedConvert('start_date',
              (v) => const TimestampConverter().fromJson(v as int)),
          status: $checkedConvert('status',
              (v) => $enumDecode(_$StripeSubscriptionStatusEnumMap, v)),
          endedAt: $checkedConvert(
              'ended_at',
              (v) => _$JsonConverterFromJson<int, DateTime>(
                  v, const TimestampConverter().fromJson)),
          canceledAt: $checkedConvert(
              'canceled_at',
              (v) => _$JsonConverterFromJson<int, DateTime>(
                  v, const TimestampConverter().fromJson)),
        );
        return val;
      },
      fieldKeyMap: const {
        'cancelAtPeriodEnd': 'cancel_at_period_end',
        'currentPeriodEnd': 'current_period_end',
        'currentPeriodStart': 'current_period_start',
        'startDate': 'start_date',
        'endedAt': 'ended_at',
        'canceledAt': 'canceled_at'
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
) =>
    json == null ? null : fromJson(json as Json);
