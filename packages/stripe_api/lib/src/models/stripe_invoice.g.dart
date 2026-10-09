// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'stripe_invoice.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripeInvoice _$StripeInvoiceFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StripeInvoice', json, ($checkedConvert) {
      final val = StripeInvoice(
        id: $checkedConvert('id', (v) => v as String),
        status: $checkedConvert(
          'status',
          (v) => $enumDecodeNullable(
            _$StripeInvoiceStatusEnumMap,
            v,
            unknownValue: JsonKey.nullForUndefinedEnumValue,
          ),
        ),
      );
      return val;
    });

const _$StripeInvoiceStatusEnumMap = {
  StripeInvoiceStatus.draft: 'draft',
  StripeInvoiceStatus.open: 'open',
  StripeInvoiceStatus.paid: 'paid',
  StripeInvoiceStatus.uncollectible: 'uncollectible',
  StripeInvoiceStatus.voided: 'void',
};
