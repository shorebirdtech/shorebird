import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/account_position.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_billing_plan_1.dart';

/// {@template enterprise_billing}
/// An enterprise's contract and its usage against it.
/// {@endtemplate}
@immutable
class EnterpriseBilling {
  /// {@macro enterprise_billing}
  const EnterpriseBilling({
    required this.hasBillingAccount,
    required this.plan,
    required this.position,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseBilling].
  factory EnterpriseBilling.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseBilling',
      json,
      () => EnterpriseBilling(
        hasBillingAccount: json['has_billing_account'] as bool,
        plan: EnterpriseBillingPlan1.maybeFromJson(
          checkedKey(json, 'plan') as Map<String, dynamic>?,
        ),
        position: AccountPosition.maybeFromJson(
          checkedKey(json, 'position') as Map<String, dynamic>?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseBilling? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseBilling.fromJson(json);
  }

  /// Whether the enterprise owns a billing account.
  final bool hasBillingAccount;

  /// The plan of an enterprise's billing account.
  final EnterpriseBillingPlan1? plan;

  /// Where the account stands against its plan right now, worked out by
  /// the server so every client shows the same figures. Counts are per
  /// allotment period (the base subscription's billing period) unless
  /// said otherwise. Overage is per overage period, which for an annual
  /// plan is the month its overage subscription bills on.
  final AccountPosition? position;

  /// Converts an [EnterpriseBilling] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'has_billing_account': hasBillingAccount,
      'plan': plan?.toJson(),
      'position': position?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    hasBillingAccount,
    plan,
    position,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseBilling &&
        hasBillingAccount == other.hasBillingAccount &&
        plan == other.plan &&
        position == other.position;
  }
}
