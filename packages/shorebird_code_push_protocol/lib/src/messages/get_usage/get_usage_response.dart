import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/account_position.dart';
import 'package:shorebird_code_push_protocol/src/models/app_usage.dart';

/// {@template get_usage_response}
/// The response body for GET /usage and
/// GET /organizations/{organizationId}/usage.
/// {@endtemplate}
@immutable
class GetUsageResponse {
  /// {@macro get_usage_response}
  const GetUsageResponse({
    required this.apps,
    required this.position,
    required this.reportedOverage,
  });

  /// Converts a `Map<String, dynamic>` to a [GetUsageResponse].
  factory GetUsageResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetUsageResponse',
      json,
      () => GetUsageResponse(
        apps: (json['apps'] as List)
            .map<AppUsage>((e) => AppUsage.fromJson(e as Map<String, dynamic>))
            .toList(),
        position: AccountPosition.fromJson(
          json['position'] as Map<String, dynamic>,
        ),
        reportedOverage: checkedKey(json, 'reported_overage') as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetUsageResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetUsageResponse.fromJson(json);
  }

  /// Patch installs this allotment period for each app in every
  /// organization the account's owner owns.
  final List<AppUsage> apps;

  /// Where the account stands against its plan.
  final AccountPosition position;

  /// Overage installs already reported to Stripe for billing this
  /// overage period. Null when the plan has no overage billing.
  final int? reportedOverage;

  /// Converts a [GetUsageResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'apps': apps.map((e) => e.toJson()).toList(),
      'position': position.toJson(),
      'reported_overage': reportedOverage,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(apps),
    position,
    reportedOverage,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetUsageResponse &&
        listsEqual(apps, other.apps) &&
        position == other.position &&
        reportedOverage == other.reportedOverage;
  }
}
