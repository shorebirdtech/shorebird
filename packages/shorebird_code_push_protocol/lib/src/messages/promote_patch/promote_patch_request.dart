import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template promote_patch_request}
/// The request body for POST /apps/{appId}/patches/promote.
/// {@endtemplate}
@immutable
class PromotePatchRequest {
  /// {@macro promote_patch_request}
  const PromotePatchRequest({
    required this.patchId,
    required this.channelId,
    this.rolloutPercentage,
    this.platforms,
  });

  /// Converts a `Map<String, dynamic>` to a [PromotePatchRequest].
  factory PromotePatchRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PromotePatchRequest',
      json,
      () => PromotePatchRequest(
        patchId: json['patch_id'] as int,
        channelId: json['channel_id'] as int,
        rolloutPercentage: (json['rollout_percentage'] as num?)?.toDouble(),
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PromotePatchRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PromotePatchRequest.fromJson(json);
  }

  /// The ID of the patch.
  final int patchId;

  /// The ID of the channel.
  final int channelId;

  /// The percentage of the channel's devices to offer the patch to, a
  /// multiple of 0.01 from 0.01 to 100. Defaults to 100.
  final double? rolloutPercentage;

  /// The platforms whose patches under the number to promote, at
  /// least one. Omit to promote every platform's.
  /// Unstable: this may change shape until patch linking ships.
  final List<ReleasePlatform>? platforms;

  /// Converts a [PromotePatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'patch_id': patchId,
      'channel_id': channelId,
      'rollout_percentage': ?rolloutPercentage,
      'platforms': ?platforms?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    patchId,
    channelId,
    rolloutPercentage,
    listHash(platforms),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PromotePatchRequest &&
        patchId == other.patchId &&
        channelId == other.channelId &&
        rolloutPercentage == other.rolloutPercentage &&
        listsEqual(platforms, other.platforms);
  }
}
