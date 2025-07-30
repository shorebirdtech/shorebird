import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:stripe_api/src/models/stripe_price_tier.dart';

part 'stripe_price.g.dart';

/// {@template billing_scheme}
/// An enum representing the billing scheme of a [StripePrice].
///
/// https://docs.stripe.com/api/prices/object#price_object-billing_scheme
/// {@endtemplate}
@JsonEnum(fieldRename: FieldRename.snake)
enum BillingScheme {
  /// Per unit pricing refers to the unit_price.
  perUnit('per_unit'),

  /// Tiered pricing refers to the tiers of the price.
  tiered('tiered');

  /// {@macro billing_scheme}
  const BillingScheme(this.value);

  /// The [String] value.
  final String value;
}

/// {@template usage_type}
/// Whether the price is based on usage (metered) or the quantity in the
/// subscription (licensed).
/// https://docs.stripe.com/api/prices/object#price_object-recurring-usage_type
/// {@endtemplate}
@JsonEnum()
enum UsageType {
  /// Automatically bills the quantity set when adding it to a subscription.
  licensed,

  /// Bills based on usage.
  metered,
}

/// {@template stripe_price}
/// A partial Dart representation of the Price object from Stripe's API.
///
/// See https://stripe.com/docs/api/prices/object.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripePrice {
  /// {@macro stripe_price}
  const StripePrice({
    required this.id,
    required this.productId,
    required this.currency,
    required this.billingScheme,
    this.unitAmount,
    this.unitAmountDecimal,
    this.tiers,
    this.usageType,
    this.metadata = const {},
    this.meterId,
    this.nickname,
  });

  /// Converts a JSON object to a [StripePrice].
  factory StripePrice.fromJson(Map<String, dynamic> json) =>
      _$StripePriceFromJson(json);

  /// Unique identifier for this object, of the form "price_{base64_id}".
  final String id;

  /// The ID of the product this price is associated with.
  @JsonKey(name: 'product')
  final String productId;

  /// Three-letter ISO currency code, in lowercase.
  final String currency;

  /// The unit amount in cents to be charged, represented as a whole integer if
  /// possible. Only set if billing_scheme=per_unit.
  final int? unitAmount;

  /// Same as [unitAmount], but contains a decimal value with at most 12 decimal
  /// places.
  final Decimal? unitAmountDecimal;

  /// The tiers of the price, if it is a tiered price.
  final List<StripePriceTier>? tiers;

  /// One of "per_unit" or "tiered". Per unit pricing refers to the unit_price.
  final BillingScheme billingScheme;

  /// Metadata associated with the price.
  final Map<String, dynamic> metadata;

  /// The ID of the meter this price is attached to, if any.
  /// This will only be present if this price has metered usage. A subscription
  /// should have at most one item with metered usage.
  @JsonKey(readValue: _readMeterId)
  final String? meterId;

  /// The nickname of the price (set in Stripe's dashboard)
  /// and displayed to the user via the Shorebird console.
  final String? nickname;

  static Object? _readMeterId(Map<dynamic, dynamic> json, String _) {
    final recurring = json['recurring'] as Map<String, dynamic>?;
    return recurring?['meter'];
  }

  /// Whether this price is based on usage (metered) or the quantity in the
  /// subscription (licensed). Will only be present if this price is attached
  /// to a recurring subscription.
  @JsonKey(readValue: _readUsageType)
  final UsageType? usageType;

  static Object? _readUsageType(Map<dynamic, dynamic> json, String _) {
    final recurring = json['recurring'] as Map<String, dynamic>?;
    return recurring?['usage_type'];
  }
}

/// Extension on [StripePrice] to interact with tiers.
extension StripePriceTiers on StripePrice {
  /// Returns the tier for the given quantity.
  ///
  /// If [quantity] is greater than the highest tier's upper bound, returns the
  /// first (and assumed only) tier with no upper bound.
  StripePriceTier? tierForQuantity(int quantity) {
    if (tiers == null) {
      return null;
    }

    final sortedBoundedTiers = tiers!
        .where((tier) => tier.upTo != null)
        .sortedBy<num>((tier) => tier.upTo!);

    for (final tier in sortedBoundedTiers) {
      if (tier.upTo! >= quantity) {
        return tier;
      }
    }

    // If the quantity is greater than the highest bounded tier's upper bound,
    // return the highest tier with a bound (we don't support unbounded tiers).
    return sortedBoundedTiers.last;
  }
}
