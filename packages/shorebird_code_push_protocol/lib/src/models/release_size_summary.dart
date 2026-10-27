import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
import 'package:shorebird_code_push_protocol/src/models/size_analysis_status.dart';

/// {@template release_size_summary}
/// One platform's size-analysis verdict for a release. The size fields
/// and `engine_version` are non-null exactly when `status` is
/// `succeeded`.
/// {@endtemplate}
@immutable
class ReleaseSizeSummary {
  /// {@macro release_size_summary}
  const ReleaseSizeSummary({
    required this.platform,
    required this.status,
    required this.engineVersion,
    required this.analyzedAt,
    required this.totalSizeInBytes,
    required this.dartSizeInBytes,
    required this.nativeSizeInBytes,
    required this.assetSizeInBytes,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleaseSizeSummary].
  factory ReleaseSizeSummary.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReleaseSizeSummary',
      json,
      () => ReleaseSizeSummary(
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        status: SizeAnalysisStatus.fromJson(json['status'] as String),
        engineVersion: checkedKey(json, 'engine_version') as String?,
        analyzedAt: maybeParseDateTime(
          checkedKey(json, 'analyzed_at') as String?,
        ),
        totalSizeInBytes: checkedKey(json, 'total_size_in_bytes') as int?,
        dartSizeInBytes: checkedKey(json, 'dart_size_in_bytes') as int?,
        nativeSizeInBytes: checkedKey(json, 'native_size_in_bytes') as int?,
        assetSizeInBytes: checkedKey(json, 'asset_size_in_bytes') as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReleaseSizeSummary? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReleaseSizeSummary.fromJson(json);
  }

  /// The platform the analyzed artifact is for.
  final ReleasePlatform platform;

  /// The verdict of a release artifact's size analysis.
  final SizeAnalysisStatus status;

  /// The version of the size analyzer that produced the result.
  /// Null unless `status` is `succeeded`.
  final String? engineVersion;

  /// When the analysis reached its verdict, in UTC.
  final DateTime? analyzedAt;

  /// The artifact's total size in bytes.
  final int? totalSizeInBytes;

  /// Bytes attributed to Dart code.
  final int? dartSizeInBytes;

  /// Bytes attributed to native code.
  final int? nativeSizeInBytes;

  /// Bytes attributed to assets.
  final int? assetSizeInBytes;

  /// Converts a [ReleaseSizeSummary] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'platform': platform.toJson(),
      'status': status.toJson(),
      'engine_version': engineVersion,
      'analyzed_at': analyzedAt?.toUtc().toIso8601String(),
      'total_size_in_bytes': totalSizeInBytes,
      'dart_size_in_bytes': dartSizeInBytes,
      'native_size_in_bytes': nativeSizeInBytes,
      'asset_size_in_bytes': assetSizeInBytes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    platform,
    status,
    engineVersion,
    analyzedAt,
    totalSizeInBytes,
    dartSizeInBytes,
    nativeSizeInBytes,
    assetSizeInBytes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReleaseSizeSummary &&
        platform == other.platform &&
        status == other.status &&
        engineVersion == other.engineVersion &&
        analyzedAt == other.analyzedAt &&
        totalSizeInBytes == other.totalSizeInBytes &&
        dartSizeInBytes == other.dartSizeInBytes &&
        nativeSizeInBytes == other.nativeSizeInBytes &&
        assetSizeInBytes == other.assetSizeInBytes;
  }
}
