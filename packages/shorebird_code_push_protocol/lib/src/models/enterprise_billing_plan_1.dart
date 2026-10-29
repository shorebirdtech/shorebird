import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template enterprise_billing_plan_1}
/// The plan of an enterprise's billing account.
/// {@endtemplate}
@immutable
class EnterpriseBillingPlan1 {
  /// {@macro enterprise_billing_plan_1}
  const EnterpriseBillingPlan1({
    required this.name,
    required this.level,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.currency,
    this.billingInterval,
    this.billingIntervalCount,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseBillingPlan1].
  factory EnterpriseBillingPlan1.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseBillingPlan1',
      json,
      () => EnterpriseBillingPlan1(
        name: json['name'] as String,
        level: json['level'] as String,
        billingInterval: json['billing_interval'] as String?,
        billingIntervalCount: json['billing_interval_count'] as int?,
        currentPeriodStart: DateTime.parse(
          json['current_period_start'] as String,
        ),
        currentPeriodEnd: DateTime.parse(json['current_period_end'] as String),
        cancelAtPeriodEnd: json['cancel_at_period_end'] as bool,
        currency: json['currency'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseBillingPlan1? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseBillingPlan1.fromJson(json);
  }

  /// The plan's name, as the contract's price names it.
  final String name;

  /// The plan level, such as `enterprise`.
  final String level;

  /// The unit the plan bills on (`month`, `year`).
  final String? billingInterval;

  /// How many intervals make one billing period.
  final int? billingIntervalCount;
  final DateTime currentPeriodStart;

  /// When the current period ends and the plan renews.
  final DateTime currentPeriodEnd;

  /// Whether the plan ends instead of renewing.
  final bool cancelAtPeriodEnd;
  final String currency;

  /// Converts an [EnterpriseBillingPlan1] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'level': level,
      'billing_interval': billingInterval,
      'billing_interval_count': billingIntervalCount,
      'current_period_start': currentPeriodStart.toUtc().toIso8601String(),
      'current_period_end': currentPeriodEnd.toUtc().toIso8601String(),
      'cancel_at_period_end': cancelAtPeriodEnd,
      'currency': currency,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    name,
    level,
    billingInterval,
    billingIntervalCount,
    currentPeriodStart,
    currentPeriodEnd,
    cancelAtPeriodEnd,
    currency,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseBillingPlan1 &&
        name == other.name &&
        level == other.level &&
        billingInterval == other.billingInterval &&
        billingIntervalCount == other.billingIntervalCount &&
        currentPeriodStart == other.currentPeriodStart &&
        currentPeriodEnd == other.currentPeriodEnd &&
        cancelAtPeriodEnd == other.cancelAtPeriodEnd &&
        currency == other.currency;
  }
}
