import 'package:json_annotation/json_annotation.dart';

part 'stripe_billing_meter.g.dart';

/// {@template stripe_billing_meter}
/// A billing meter in Stripe.
///
/// See https://docs.stripe.com/api/billing/meter/object
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripeBillingMeter {
  /// {@macro stripe_billing_meter}
  StripeBillingMeter({
    required this.id,
    required this.displayName,
    required this.eventName,
  });

  /// Converts a JSON object to a [StripeBillingMeter].
  factory StripeBillingMeter.fromJson(Map<String, dynamic> json) =>
      _$StripeBillingMeterFromJson(json);

  /// The unique identifier for this object.
  final String id;

  /// The meter's name.
  final String displayName;

  /// The name of the meter event to record usage for. Corresponds with the
  /// event_name field on meter events.
  final String eventName;
}
