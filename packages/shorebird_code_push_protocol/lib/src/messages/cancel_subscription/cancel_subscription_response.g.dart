// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'cancel_subscription_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CancelSubscriptionResponse _$CancelSubscriptionResponseFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CancelSubscriptionResponse',
      json,
      ($checkedConvert) {
        final val = CancelSubscriptionResponse(
          expirationDate: $checkedConvert('expiration_date',
              (v) => const TimestampConverter().fromJson(v as int)),
        );
        return val;
      },
      fieldKeyMap: const {'expirationDate': 'expiration_date'},
    );

Map<String, dynamic> _$CancelSubscriptionResponseToJson(
        CancelSubscriptionResponse instance) =>
    <String, dynamic>{
      'expiration_date':
          const TimestampConverter().toJson(instance.expirationDate),
    };
