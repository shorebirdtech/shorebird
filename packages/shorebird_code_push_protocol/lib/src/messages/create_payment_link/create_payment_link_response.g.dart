// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_payment_link_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePaymentLinkResponse _$CreatePaymentLinkResponseFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePaymentLinkResponse',
      json,
      ($checkedConvert) {
        final val = CreatePaymentLinkResponse(
          paymentLink:
              $checkedConvert('payment_link', (v) => Uri.parse(v as String)),
        );
        return val;
      },
      fieldKeyMap: const {'paymentLink': 'payment_link'},
    );

Map<String, dynamic> _$CreatePaymentLinkResponseToJson(
        CreatePaymentLinkResponse instance) =>
    <String, dynamic>{
      'payment_link': instance.paymentLink.toString(),
    };
