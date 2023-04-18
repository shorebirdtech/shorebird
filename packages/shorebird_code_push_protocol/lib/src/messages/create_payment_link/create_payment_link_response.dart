import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'create_payment_link_response.g.dart';

/// {@template create_payment_link_response}
/// A wrapper for a Stripe payment link.
/// {@endtemplate}
@JsonSerializable()
class CreatePaymentLinkResponse {
  /// {@macro create_payment_link_response}
  CreatePaymentLinkResponse({required this.paymentLink});

  /// Converts a [CreatePaymentLinkResponse] to a JSON object.
  Json toJson() => _$CreatePaymentLinkResponseToJson(this);

  /// Stripe payment link.
  ///
  /// See https://stripe.com/docs/api/payment_links/payment_links/create.
  final Uri paymentLink;
}
