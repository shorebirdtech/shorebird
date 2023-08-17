import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'shorebird_plan.g.dart';

/// {@template shorebird_plan}
/// A Shorebird plan.
/// {@endtemplate}
@JsonSerializable()
class ShorebirdPlan {
  /// {@macro shorebird_plan}
  const ShorebirdPlan({
    required this.name,
    required this.monthlyCost,
    required this.currency,
    required this.patchInstallLimit,
    this.maxTeamSize,
  });

  /// Creates a [ShorebirdPlan] from a JSON object.
  factory ShorebirdPlan.fromJson(Json json) => _$ShorebirdPlanFromJson(json);

  /// Converts a [ShorebirdPlan] to a JSON object.
  Json toJson() => _$ShorebirdPlanToJson(this);

  /// The name of the plan.
  final String name;

  /// Monthly billing rate.
  @MoneyConverter()
  final Money monthlyCost;

  /// The currency of the plan (e.g. USD, CAD, etc.)
  final String currency;

  /// The number of patch installs allowed per billing period. This will be null
  /// for accounts with unlimited patch installs.
  final int? patchInstallLimit;

  /// The maximum number of collaborators allowed per account. This will be null
  /// for accounts with unlimited collaborators.
  final int? maxTeamSize;
}
