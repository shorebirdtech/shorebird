import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_size_summary.dart';

/// {@template get_release_size_analysis_response}
/// The response body for
/// GET /apps/{appId}/releases/{releaseId}/size-analysis without
/// `include=tree`.
/// {@endtemplate}
@immutable
class GetReleaseSizeAnalysisResponse {
  /// {@macro get_release_size_analysis_response}
  const GetReleaseSizeAnalysisResponse({
    required this.platforms,
  });

  /// Converts a `Map<String, dynamic>` to a [GetReleaseSizeAnalysisResponse].
  factory GetReleaseSizeAnalysisResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetReleaseSizeAnalysisResponse',
      json,
      () => GetReleaseSizeAnalysisResponse(
        platforms: (json['platforms'] as List)
            .map<ReleaseSizeSummary>(
              (e) => ReleaseSizeSummary.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetReleaseSizeAnalysisResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetReleaseSizeAnalysisResponse.fromJson(json);
  }

  /// One entry per platform whose analysis reached a verdict (only
  /// `platform`'s, when that parameter is sent). Platforms never
  /// analyzed are left out, so the list may be empty.
  final List<ReleaseSizeSummary> platforms;

  /// Converts a [GetReleaseSizeAnalysisResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'platforms': platforms.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(platforms).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetReleaseSizeAnalysisResponse &&
        listsEqual(platforms, other.platforms);
  }
}
