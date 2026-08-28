import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template version_distribution_entry}
/// One bucket in a version-distribution chart: the exact count of
/// currently-active devices on a given release version. A null
/// `release_version` represents devices whose client did not emit one
/// (typically very old Flutter clients).
/// {@endtemplate}
@immutable
class VersionDistributionEntry {
  /// {@macro version_distribution_entry}
  const VersionDistributionEntry({
    required this.releaseVersion,
    required this.deviceCount,
    required this.percentage,
  });

  /// Converts a `Map<String, dynamic>` to a [VersionDistributionEntry].
  factory VersionDistributionEntry.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'VersionDistributionEntry',
      json,
      () => VersionDistributionEntry(
        releaseVersion: checkedKey(json, 'release_version') as String?,
        deviceCount: json['device_count'] as int,
        percentage: (json['percentage'] as num).toDouble(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static VersionDistributionEntry? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return VersionDistributionEntry.fromJson(json);
  }

  /// The release version for this bucket, or null for devices whose
  /// client did not emit one.
  final String? releaseVersion;

  /// Number of currently-active devices on this release version
  /// within the active-device window.
  final int deviceCount;

  /// Fractional share of currently-active devices on this release
  /// version, in [0.0, 1.0]. Server is the source of truth; clients
  /// should render this value rather than recomputing it.
  final double percentage;

  /// Converts a [VersionDistributionEntry] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'release_version': releaseVersion,
      'device_count': deviceCount,
      'percentage': percentage,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    releaseVersion,
    deviceCount,
    percentage,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VersionDistributionEntry &&
        releaseVersion == other.releaseVersion &&
        deviceCount == other.deviceCount &&
        percentage == other.percentage;
  }
}
