import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template account_position}
/// Where the account stands against its plan right now, worked out by
/// the server so every client shows the same figures. Counts are per
/// allotment period (the base subscription's billing period) unless
/// said otherwise. Overage is per overage period, which for an annual
/// plan is the month its overage subscription bills on.
/// {@endtemplate}
@immutable
class AccountPosition {
  /// {@macro account_position}
  const AccountPosition({
    required this.includedInstalls,
    required this.installs,
    required this.includedInstallsUsed,
    required this.includedExhausted,
    required this.overageInstalls,
    required this.installCeiling,
    required this.remainingInstalls,
    required this.atCeiling,
    required this.nearingLimit,
    required this.consumingOverage,
    required this.accruedOverageAmount,
  });

  /// Converts a `Map<String, dynamic>` to an [AccountPosition].
  factory AccountPosition.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AccountPosition',
      json,
      () => AccountPosition(
        includedInstalls: json['included_installs'] as int,
        installs: json['installs'] as int,
        includedInstallsUsed: json['included_installs_used'] as int,
        includedExhausted: json['included_exhausted'] as bool,
        overageInstalls: json['overage_installs'] as int,
        installCeiling: checkedKey(json, 'install_ceiling') as int?,
        remainingInstalls: checkedKey(json, 'remaining_installs') as int?,
        atCeiling: json['at_ceiling'] as bool,
        nearingLimit: json['nearing_limit'] as bool,
        consumingOverage: json['consuming_overage'] as bool,
        accruedOverageAmount:
            checkedKey(json, 'accrued_overage_amount') as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AccountPosition? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AccountPosition.fromJson(json);
  }

  /// Installs the account may make this allotment period before
  /// overage begins: the plan's allotment plus any credit.
  final int includedInstalls;

  /// Installs served so far this allotment period.
  final int installs;

  /// Installs taken from the included allotment. Installs billed as
  /// overage are not counted here.
  final int includedInstallsUsed;

  /// Whether the included allotment is used up.
  final bool includedExhausted;

  /// Overage installs billed this overage period, capped at the
  /// spending limit. `0` when the plan has no overage billing.
  final int overageInstalls;

  /// The install count at which patches stop being served, or null
  /// when nothing stops them.
  final int? installCeiling;

  /// Installs left before `install_ceiling`, or null when there is no
  /// ceiling.
  final int? remainingInstalls;

  /// Whether `install_ceiling` has been reached.
  final bool atCeiling;

  /// Whether installs have reached the share of `install_ceiling`
  /// at which Shorebird emails a warning.
  final bool nearingLimit;

  /// Whether installs are being billed as overage right now.
  final bool consumingOverage;

  /// What `overage_installs` costs at the plan's overage price, in
  /// minor units of the plan's currency, as a decimal number in a
  /// string because it can be fractional. Null when the plan has
  /// no overage billing.
  final String? accruedOverageAmount;

  /// Converts an [AccountPosition] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'included_installs': includedInstalls,
      'installs': installs,
      'included_installs_used': includedInstallsUsed,
      'included_exhausted': includedExhausted,
      'overage_installs': overageInstalls,
      'install_ceiling': installCeiling,
      'remaining_installs': remainingInstalls,
      'at_ceiling': atCeiling,
      'nearing_limit': nearingLimit,
      'consuming_overage': consumingOverage,
      'accrued_overage_amount': accruedOverageAmount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    includedInstalls,
    installs,
    includedInstallsUsed,
    includedExhausted,
    overageInstalls,
    installCeiling,
    remainingInstalls,
    atCeiling,
    nearingLimit,
    consumingOverage,
    accruedOverageAmount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AccountPosition &&
        includedInstalls == other.includedInstalls &&
        installs == other.installs &&
        includedInstallsUsed == other.includedInstallsUsed &&
        includedExhausted == other.includedExhausted &&
        overageInstalls == other.overageInstalls &&
        installCeiling == other.installCeiling &&
        remainingInstalls == other.remainingInstalls &&
        atCeiling == other.atCeiling &&
        nearingLimit == other.nearingLimit &&
        consumingOverage == other.consumingOverage &&
        accruedOverageAmount == other.accruedOverageAmount;
  }
}
