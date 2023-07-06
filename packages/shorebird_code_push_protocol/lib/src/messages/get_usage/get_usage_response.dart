import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_usage_response.g.dart';

/// {@template get_usage_response}
/// The response body for GET /api/v1/usage
/// {@endtemplate}
@JsonSerializable()
class GetUsageResponse {
  /// {@macro get_usage_response}
  const GetUsageResponse({
    required this.plan,
    required this.apps,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    this.patchInstallLimit,
  });

  /// Converts a Map<String, dynamic> to a [GetUsageResponse].
  factory GetUsageResponse.fromJson(Map<String, dynamic> json) =>
      _$GetUsageResponseFromJson(json);

  /// Converts a [GetUsageResponse] to a Map<String, dynamic>.
  Json toJson() => _$GetUsageResponseToJson(this);

  /// The name of the user's plan tier.
  final ShorebirdPlan plan;

  /// The usage per app.
  final List<AppUsage> apps;

  /// The start of the current billing period.
  final DateTime currentPeriodStart;

  /// The end of the current billing period.
  final DateTime currentPeriodEnd;

  /// The upper limit of patch installs for the current billing period.
  /// If `null`, there is no limit.
  final int? patchInstallLimit;
}

/// {@template app_usage}
/// The usage for a single app.
/// {@endtemplate}
@JsonSerializable()
class AppUsage {
  /// {@macro app_usage}
  const AppUsage({
    required this.id,
    required this.name,
    required this.patchInstallCount,
  });

  /// Converts a Map<String, dynamic> to a [AppUsage].
  factory AppUsage.fromJson(Map<String, dynamic> json) =>
      _$AppUsageFromJson(json);

  /// Converts a [AppUsage] to a Map<String, dynamic>.
  Json toJson() => _$AppUsageToJson(this);

  /// The id of the app.
  final String id;

  /// The display name of the app.
  final String name;

  /// The number of patch installs for the app.
  final int patchInstallCount;
}
