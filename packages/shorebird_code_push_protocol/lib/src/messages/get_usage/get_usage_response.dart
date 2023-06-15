import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_usage_response.g.dart';

/// {@template get_usage_response}
/// The response body for GET /api/v1/usage
/// {@endtemplate}
@JsonSerializable()
class GetUsageResponse {
  /// {@macro get_usage_response}
  const GetUsageResponse({required this.apps});

  /// Converts a Map<String, dynamic> to a [GetUsageResponse].
  factory GetUsageResponse.fromJson(Map<String, dynamic> json) =>
      _$GetUsageResponseFromJson(json);

  /// Converts a [GetUsageResponse] to a Map<String, dynamic>.
  Json toJson() => _$GetUsageResponseToJson(this);

  /// The usage per app.
  final List<AppUsage> apps;
}

/// {@template app_usage}
/// The usage for a single app.
/// {@endtemplate}
@JsonSerializable()
class AppUsage {
  /// {@macro app_usage}
  const AppUsage({required this.id, required this.platforms});

  /// Converts a Map<String, dynamic> to a [AppUsage].
  factory AppUsage.fromJson(Map<String, dynamic> json) =>
      _$AppUsageFromJson(json);

  /// Converts a [AppUsage] to a Map<String, dynamic>.
  Json toJson() => _$AppUsageToJson(this);

  /// The id of the app.
  final String id;

  /// The usage per platform.
  final List<PlatformUsage> platforms;
}

/// {@template platform_usage}
/// The usage for a single platform.
/// {@endtemplate}
@JsonSerializable()
class PlatformUsage {
  /// {@macro platform_usage}
  const PlatformUsage({required this.name, required this.arches});

  /// Converts a Map<String, dynamic> to a [PlatformUsage].
  factory PlatformUsage.fromJson(Map<String, dynamic> json) =>
      _$PlatformUsageFromJson(json);

  /// Converts a [PlatformUsage] to a Map<String, dynamic>.
  Json toJson() => _$PlatformUsageToJson(this);

  /// The name of the platform.
  final String name;

  /// The usage per arch.
  final List<ArchUsage> arches;
}

/// {@template arch_usage}
/// The usage for a single architecture.
/// {@endtemplate}
@JsonSerializable()
class ArchUsage {
  /// {@macro arch_usage}
  const ArchUsage({required this.name, required this.patches});

  /// Converts a Map<String, dynamic> to a [ArchUsage].
  factory ArchUsage.fromJson(Map<String, dynamic> json) =>
      _$ArchUsageFromJson(json);

  /// Converts a [ArchUsage] to a Map<String, dynamic>.
  Json toJson() => _$ArchUsageToJson(this);

  /// The name of the architecture.
  final String name;

  /// The usage per patch.
  final List<PatchUsage> patches;
}

/// {@template patch_usage}
/// The usage for a single patch.
/// {@endtemplate}
@JsonSerializable()
class PatchUsage {
  /// {@macro patch_usage}
  const PatchUsage({required this.number, required this.installCount});

  /// Converts a Map<String, dynamic> to a [PatchUsage].
  factory PatchUsage.fromJson(Map<String, dynamic> json) =>
      _$PatchUsageFromJson(json);

  /// Converts a [PatchUsage] to a Map<String, dynamic>.
  Json toJson() => _$PatchUsageToJson(this);

  /// The number of the patch.
  final int number;

  /// The number of times the patch has been installed.
  final int installCount;
}
