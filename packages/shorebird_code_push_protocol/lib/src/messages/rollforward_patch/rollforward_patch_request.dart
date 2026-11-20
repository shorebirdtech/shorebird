import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template rollforward_patch_request}
/// The optional request body for POST
/// /apps/{appId}/releases/{releaseId}/patches/{patchId}/rollforward.
/// {@endtemplate}
@immutable
class RollforwardPatchRequest {
  /// {@macro rollforward_patch_request}
  const RollforwardPatchRequest({
    this.platforms,
  });

  /// Converts a `Map<String, dynamic>` to a [RollforwardPatchRequest].
  factory RollforwardPatchRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'RollforwardPatchRequest',
      json,
      () => RollforwardPatchRequest(
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static RollforwardPatchRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return RollforwardPatchRequest.fromJson(json);
  }

  /// The platforms whose patches under the number to roll forward,
  /// at least one. Omit to roll forward every platform's.
  /// Unstable: this may change shape until patch linking ships.
  final List<ReleasePlatform>? platforms;

  /// Converts a [RollforwardPatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'platforms': ?platforms?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(platforms).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RollforwardPatchRequest &&
        listsEqual(platforms, other.platforms);
  }
}
