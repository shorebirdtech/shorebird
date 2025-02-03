import 'package:decimal/decimal.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'plan.g.dart';

/// {@template plan}
/// A plan represents a user's subscription to the Code Push product. It
/// includes details about the plan, such as the name, price, and billing
/// period.
/// {@endtemplate}
@JsonSerializable()
class Plan {
  /// {@macro plan}
  Plan({
    required this.name,
    required this.currency,
    required this.basePrice,
    required this.baseInstallCount,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.isTiered,
    required this.isTrial,
    this.pricePerOverageInstall,
    this.maxTeamSize,
  });

  /// Deserialize a [Plan] from [json].
  static Plan fromJson(Map<String, dynamic> json) => _$PlanFromJson(json);

  /// Serialize the [Plan] to [Json].
  Json toJson() => _$PlanToJson(this);

  /// The display name of the plan
  final String name;

  /// The ISO 4217 currency code for the plan.
  final String currency;

  /// The price paid per billing period, irrespective of the number of patch
  /// installs used. This number is in minor units of [currency]
  /// (e.g., cents for USD).
  final int basePrice;

  /// The number of patch installs included with the base price.
  final int baseInstallCount;

  /// The price per patch install over [baseInstallCount]. This is in minor
  /// units of [currency] (e.g., cents for USD) and may be a fractional value.
  /// Will be null if the user's plan does not support overage billing.
  final Decimal? pricePerOverageInstall;

  /// The start of the current billing period.
  /// If the user is on a free plan, this will be the start of the current
  /// month.
  final DateTime currentPeriodStart;

  /// The end of the current billing period.
  /// If the user is on a free plan, this will be the start of the next month.
  final DateTime currentPeriodEnd;

  /// Whether the subscription will be canceled at the end of the current
  /// billing period.
  final bool cancelAtPeriodEnd;

  /// Whether the plan is tier (i.e., whether the user can change their plan).
  final bool isTiered;

  /// Whether the user is on a trial plan. Trial plans are not billed and cancel
  /// automatically at the end of the trial period.
  final bool isTrial;

  /// The maximum number of collaborators allowed per account. This will be null
  /// for accounts with unlimited collaborators.
  final int? maxTeamSize;
}
