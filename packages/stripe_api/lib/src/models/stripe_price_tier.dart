import 'package:json_annotation/json_annotation.dart';
import 'package:stripe_api/src/models/models.dart';

part 'stripe_price_tier.g.dart';

/// {@template stripe_price}
/// A pricing tier for a [StripePrice].
///
/// See https://stripe.com/docs/api/prices/object#price_object-tiers.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripePriceTier {
  /// {@macro stripe_price}
  const StripePriceTier({
    required this.flatAmount,
    required this.flatAmountDecimal,
    required this.unitAmount,
    required this.unitAmountDecimal,
    required this.upTo,
  });

  /// Converts a JSON object to a [StripePriceTier].
  factory StripePriceTier.fromJson(Map<String, dynamic> json) =>
      _$StripePriceTierFromJson(json);

  /// Price for the entire tier.
  final int? flatAmount;

  /// Same as [flatAmount], but contains a decimal value with at most 12
  /// decimal places.
  final String? flatAmountDecimal;

  /// Per unit price for units relevant to the tier.
  final int? unitAmount;

  /// Same as [unitAmount], but contains a decimal value with at most 12
  /// decimal places.
  final String? unitAmountDecimal;

  /// Up to and including to this quantity will be contained in the tier.
  final int? upTo;
}
