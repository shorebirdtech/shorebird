import 'package:json_annotation/json_annotation.dart';

part 'stripe_invoice.g.dart';

/// Possible states of a [StripeInvoice].
///
/// See https://docs.stripe.com/invoicing/overview#invoice-statuses.
enum StripeInvoiceStatus {
  /// Not yet finalized. It can still be edited and cannot be paid.
  draft,

  /// Finalized and awaiting payment.
  open,

  /// Paid in full.
  paid,

  /// Written off as unlikely to be paid. Stripe still accepts payment on it.
  uncollectible,

  /// Canceled. It can no longer be paid, and the status is final.
  @JsonValue('void')
  voided,
}

/// {@template stripe_invoice}
/// A partial Dart representation of the Invoice object from Stripe's API.
///
/// See https://docs.stripe.com/api/invoices/object.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripeInvoice {
  /// {@macro stripe_invoice}
  const StripeInvoice({required this.id, this.status});

  /// Converts a JSON object to a [StripeInvoice].
  factory StripeInvoice.fromJson(Map<String, dynamic> json) =>
      _$StripeInvoiceFromJson(json);

  /// The unique identifier for this object.
  final String id;

  /// The invoice's status, or null when Stripe reports none or one this
  /// client does not know.
  @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
  final StripeInvoiceStatus? status;

  /// Whether the customer can still pay this invoice.
  bool get isPayable =>
      status == StripeInvoiceStatus.open ||
      status == StripeInvoiceStatus.uncollectible;
}
