import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template plan}
/// The subscription an account is on: what it costs, what it
/// includes, and how installs past the allotment are handled. An
/// account with no subscription is on the free Hobby plan, whose
/// billing period is the calendar month.
///
/// Several fields are strings rather than enums so that new values
/// can be added without breaking clients; their current values are
/// listed in each description.
/// {@endtemplate}
@immutable
class Plan {
  /// {@macro plan}
  const Plan({
    required this.name,
    required this.currency,
    required this.basePrice,
    required this.baseInstallCount,
    required this.patchInstallCredit,
    required this.patchOverageLimit,
    required this.pricePerOverageInstall,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.isTiered,
    required this.isTrial,
    required this.baseStanding,
    required this.overageStanding,
    required this.overageState,
    required this.overageBlockedBy,
    required this.overagePeriodStart,
    required this.overagePeriodEnd,
    required this.features,
    required this.level,
    required this.minimumReleasesKept,
    required this.maxTeamSize,
    required this.availableRoles,
    required this.billingInterval,
    required this.billingIntervalCount,
    required this.subscriberSince,
  });

  /// Converts a `Map<String, dynamic>` to a [Plan].
  factory Plan.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'Plan',
      json,
      () => Plan(
        name: json['name'] as String,
        currency: json['currency'] as String,
        basePrice: json['base_price'] as int,
        baseInstallCount: json['base_install_count'] as int,
        patchInstallCredit: json['patch_install_credit'] as int,
        patchOverageLimit: checkedKey(json, 'patch_overage_limit') as int?,
        pricePerOverageInstall:
            checkedKey(json, 'price_per_overage_install') as String?,
        currentPeriodStart: DateTime.parse(
          json['current_period_start'] as String,
        ),
        currentPeriodEnd: DateTime.parse(json['current_period_end'] as String),
        cancelAtPeriodEnd: json['cancel_at_period_end'] as bool,
        isTiered: json['is_tiered'] as bool,
        isTrial: json['is_trial'] as bool,
        baseStanding: json['base_standing'] as String,
        overageStanding: json['overage_standing'] as String,
        overageState: json['overage_state'] as String,
        overageBlockedBy: checkedKey(json, 'overage_blocked_by') as String?,
        overagePeriodStart: maybeParseDateTime(
          checkedKey(json, 'overage_period_start') as String?,
        ),
        overagePeriodEnd: maybeParseDateTime(
          checkedKey(json, 'overage_period_end') as String?,
        ),
        features: (json['features'] as List).cast<String>(),
        level: json['level'] as String,
        minimumReleasesKept: checkedKey(json, 'minimum_releases_kept') as int?,
        maxTeamSize: checkedKey(json, 'max_team_size') as int?,
        availableRoles: (json['available_roles'] as List)
            .map<Role>((e) => Role.fromJson(e as String))
            .toList(),
        billingInterval: checkedKey(json, 'billing_interval') as String?,
        billingIntervalCount:
            checkedKey(json, 'billing_interval_count') as int?,
        subscriberSince: maybeParseDateTime(
          checkedKey(json, 'subscriber_since') as String?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static Plan? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return Plan.fromJson(json);
  }

  /// The plan's display name.
  final String name;

  /// The ISO 4217 code of the plan's currency (e.g. `usd`).
  final String currency;

  /// The list price per billing period, in minor units of
  /// `currency` (e.g. cents), whatever the installs used. Does not
  /// reflect coupons or discounts.
  final int basePrice;

  /// The patch installs included in the base price each billing period.
  final int baseInstallCount;

  /// Extra patch installs granted to the account's owner on top of
  /// `base_install_count`, such as promotional or support credit.
  /// `0` when there is none.
  final int patchInstallCredit;

  /// The most installs past the allotment the owner has agreed to
  /// pay for each overage period: their spending limit, in
  /// installs. Null when the owner has set no limit.
  final int? patchOverageLimit;

  /// The price of each install past the allotment, in minor units
  /// of `currency`, as a decimal number in a string because it can
  /// be fractional (e.g. `"0.1"`). Null when the plan has no
  /// overage billing.
  final String? pricePerOverageInstall;

  /// The start of the current billing period. The start of the
  /// current month on the Hobby plan.
  final DateTime currentPeriodStart;

  /// The end of the current billing period. The start of the next
  /// month on the Hobby plan.
  final DateTime currentPeriodEnd;

  /// Whether the subscription is set to end at the end of the current billing
  /// period.
  final bool cancelAtPeriodEnd;

  /// Whether the plan is one of the standard tiers an account can switch
  /// between.
  final bool isTiered;

  /// Whether the account is on a trial, which is not billed and ends on its
  /// own.
  final bool isTrial;

  /// The payment standing of the subscription carrying the plan:
  /// `none` (no subscription), `trialing`, `active`, or `past_due`.
  /// `past_due` keeps the plan in force while Stripe retries the
  /// payment; prompt for a working payment method.
  final String baseStanding;

  /// The payment standing of the subscription carrying the overage
  /// price, in the same terms as `base_standing` plus `unpaid`
  /// (every retry failed and only paying the invoice resumes
  /// overage). Equal to `base_standing` when overage bills on the
  /// base subscription; independent when an annual plan bills
  /// overage on its own monthly subscription. `none` when the plan
  /// has no overage billing.
  final String overageStanding;

  /// Whether installs past the allotment are served, and on what
  /// terms: `unavailable` (the plan has no overage billing), `off`
  /// (the limit is `0`), `blocked` (a payment is overdue; see
  /// `overage_blocked_by`), `capped` (up to `patch_overage_limit`
  /// each overage period), or `unlimited`.
  final String overageState;

  /// Which overdue payment holds overage back while
  /// `overage_state` is `blocked`: `base_past_due`,
  /// `overage_past_due`, or `overage_unpaid`. Null otherwise.
  final String? overageBlockedBy;

  /// The start of the period overage is capped and invoiced over:
  /// the billing period for a monthly plan, the overage
  /// subscription's own month for an annual one. Null when the
  /// plan has no overage billing.
  final DateTime? overagePeriodStart;

  /// The end of the period overage is capped and invoiced over.
  /// Null when the plan has no overage billing.
  final DateTime? overagePeriodEnd;

  /// The features the plan enables. Current values:
  /// `collaboration`, `historicalInsights`, `audienceAnalytics`,
  /// `customTokenExpiration`, `auditLogs`, `sizeAnalysis`,
  /// `oidcFederation`.
  final List<String> features;

  /// The plan's tier: `free`, `pro`, `business`, or `enterprise`.
  final String level;

  /// How many of an app's releases are kept however long they sit
  /// unused. Null when releases are never retired.
  final int? minimumReleasesKept;

  /// The most members an account may have: `1` on plans without
  /// collaboration, null when there is no limit.
  final int? maxTeamSize;

  /// The roles that may be given to members on this plan.
  final List<Role> availableRoles;

  /// The unit the subscription bills on: `day`, `week`, `month`, or
  /// `year`. Null without a subscription.
  final String? billingInterval;

  /// How many `billing_interval`s make one billing period. Null
  /// without a subscription.
  final int? billingIntervalCount;

  /// When the subscription started; unchanged by renewals and plan
  /// changes. Null without a subscription.
  final DateTime? subscriberSince;

  /// Converts a [Plan] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'currency': currency,
      'base_price': basePrice,
      'base_install_count': baseInstallCount,
      'patch_install_credit': patchInstallCredit,
      'patch_overage_limit': patchOverageLimit,
      'price_per_overage_install': pricePerOverageInstall,
      'current_period_start': currentPeriodStart.toUtc().toIso8601String(),
      'current_period_end': currentPeriodEnd.toUtc().toIso8601String(),
      'cancel_at_period_end': cancelAtPeriodEnd,
      'is_tiered': isTiered,
      'is_trial': isTrial,
      'base_standing': baseStanding,
      'overage_standing': overageStanding,
      'overage_state': overageState,
      'overage_blocked_by': overageBlockedBy,
      'overage_period_start': overagePeriodStart?.toUtc().toIso8601String(),
      'overage_period_end': overagePeriodEnd?.toUtc().toIso8601String(),
      'features': features,
      'level': level,
      'minimum_releases_kept': minimumReleasesKept,
      'max_team_size': maxTeamSize,
      'available_roles': availableRoles.map((e) => e.toJson()).toList(),
      'billing_interval': billingInterval,
      'billing_interval_count': billingIntervalCount,
      'subscriber_since': subscriberSince?.toUtc().toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    name,
    currency,
    basePrice,
    baseInstallCount,
    patchInstallCredit,
    patchOverageLimit,
    pricePerOverageInstall,
    currentPeriodStart,
    currentPeriodEnd,
    cancelAtPeriodEnd,
    isTiered,
    isTrial,
    baseStanding,
    overageStanding,
    overageState,
    overageBlockedBy,
    overagePeriodStart,
    overagePeriodEnd,
    listHash(features),
    level,
    minimumReleasesKept,
    maxTeamSize,
    listHash(availableRoles),
    billingInterval,
    billingIntervalCount,
    subscriberSince,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Plan &&
        name == other.name &&
        currency == other.currency &&
        basePrice == other.basePrice &&
        baseInstallCount == other.baseInstallCount &&
        patchInstallCredit == other.patchInstallCredit &&
        patchOverageLimit == other.patchOverageLimit &&
        pricePerOverageInstall == other.pricePerOverageInstall &&
        currentPeriodStart == other.currentPeriodStart &&
        currentPeriodEnd == other.currentPeriodEnd &&
        cancelAtPeriodEnd == other.cancelAtPeriodEnd &&
        isTiered == other.isTiered &&
        isTrial == other.isTrial &&
        baseStanding == other.baseStanding &&
        overageStanding == other.overageStanding &&
        overageState == other.overageState &&
        overageBlockedBy == other.overageBlockedBy &&
        overagePeriodStart == other.overagePeriodStart &&
        overagePeriodEnd == other.overagePeriodEnd &&
        listsEqual(features, other.features) &&
        level == other.level &&
        minimumReleasesKept == other.minimumReleasesKept &&
        maxTeamSize == other.maxTeamSize &&
        listsEqual(availableRoles, other.availableRoles) &&
        billingInterval == other.billingInterval &&
        billingIntervalCount == other.billingIntervalCount &&
        subscriberSince == other.subscriberSince;
  }
}
