import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_link_result.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template patch_link}
/// What linking did for a created patch. Absent from servers that
/// predate linking.
/// Unstable: this may change shape until patch linking ships.
/// {@endtemplate}
@immutable
class PatchLink {
  /// {@macro patch_link}
  const PatchLink({
    required this.result,
    this.reason,
    this.platforms,
    this.linkNumber,
    this.platformPatchNumber,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchLink].
  factory PatchLink.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchLink',
      json,
      () => PatchLink(
        result: PatchLinkResult.fromJson(json['result'] as String),
        reason: json['reason'] as String?,
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
        linkNumber: json['link_number'] as int?,
        platformPatchNumber: json['platform_patch_number'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchLink? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchLink.fromJson(json);
  }

  /// What linking did for a created patch.
  /// Unstable: this may change shape until patch linking ships.
  final PatchLinkResult result;

  /// Why the patch was not linked, when `result` is `not_linked`.
  /// One of `platform_has_newer_patch` (the platform already has a
  /// patch numbered at or above the key's newest number) or
  /// `number_rolled_back` (a patch under the key's newest number is
  /// rolled back). Clients should treat other values as a reason
  /// they do not know; new ones may be added.
  final String? reason;

  /// When `result` is `linked` or `reused`, the other platforms that
  /// already have a patch under this number.
  final List<ReleasePlatform>? platforms;

  /// When `result` is `not_linked`, the newest number on the release
  /// created with the same key, which the patch did not join.
  final int? linkNumber;

  /// When `reason` is `platform_has_newer_patch`, the platform's
  /// newest patch number on the release.
  final int? platformPatchNumber;

  /// Converts a [PatchLink] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'result': result.toJson(),
      'reason': ?reason,
      'platforms': ?platforms?.map((e) => e.toJson()).toList(),
      'link_number': ?linkNumber,
      'platform_patch_number': ?platformPatchNumber,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    result,
    reason,
    listHash(platforms),
    linkNumber,
    platformPatchNumber,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchLink &&
        result == other.result &&
        reason == other.reason &&
        listsEqual(platforms, other.platforms) &&
        linkNumber == other.linkNumber &&
        platformPatchNumber == other.platformPatchNumber;
  }
}
