import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_adoption_entry.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_adoption_range.dart';

/// {@template get_patch_adoption_response}
/// The response body for GET /apps/{appId}/metrics/patch-adoption. Covers
/// exactly one release.
/// {@endtemplate}
@immutable
class GetPatchAdoptionResponse {
  /// {@macro get_patch_adoption_response}
  const GetPatchAdoptionResponse({
    required this.releaseVersion,
    required this.isLatest,
    required this.granularity,
    required this.range,
    required this.asOf,
    required this.patches,
  });

  /// Converts a `Map<String, dynamic>` to a [GetPatchAdoptionResponse].
  factory GetPatchAdoptionResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetPatchAdoptionResponse',
      json,
      () => GetPatchAdoptionResponse(
        releaseVersion: json['release_version'] as String,
        isLatest: json['is_latest'] as bool,
        granularity: checkedKey(json, 'granularity') as String?,
        range: PatchAdoptionRange.fromJson(
          json['range'] as Map<String, dynamic>,
        ),
        asOf: DateTime.parse(json['as_of'] as String),
        patches: (json['patches'] as List)
            .map<PatchAdoptionEntry>(
              (e) => PatchAdoptionEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetPatchAdoptionResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetPatchAdoptionResponse.fromJson(json);
  }

  /// The release version this response is for.
  final String releaseVersion;

  /// True when the release was resolved via the "latest release by
  /// creation date" default (no `release_version` was supplied).
  final bool isLatest;

  /// The bucket resolution (`hour`, `day`, `week`, or `month`), or null
  /// when each patch carries a single full-window value.
  final String? granularity;

  /// The effective (post-clamp) window the response covers.
  final PatchAdoptionRange range;

  /// Server's UTC timestamp at the moment the response was
  /// constructed. Not a freshness indicator for the underlying
  /// data, which is refreshed by an hourly scheduled query and
  /// may lag by up to ~1 hour.
  final DateTime asOf;

  /// One entry per patch of the release.
  final List<PatchAdoptionEntry> patches;

  /// Converts a [GetPatchAdoptionResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'release_version': releaseVersion,
      'is_latest': isLatest,
      'granularity': granularity,
      'range': range.toJson(),
      'as_of': asOf.toIso8601String(),
      'patches': patches.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    releaseVersion,
    isLatest,
    granularity,
    range,
    asOf,
    listHash(patches),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetPatchAdoptionResponse &&
        releaseVersion == other.releaseVersion &&
        isLatest == other.isLatest &&
        granularity == other.granularity &&
        range == other.range &&
        asOf == other.asOf &&
        listsEqual(patches, other.patches);
  }
}
