import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template promote_patch_request}
/// The request body for POST /apps/{appId}/patches/promote.
/// {@endtemplate}
@immutable
class PromotePatchRequest {
  /// {@macro promote_patch_request}
  const PromotePatchRequest({
    required this.patchId,
    required this.channelId,
  });

  /// Converts a `Map<String, dynamic>` to a [PromotePatchRequest].
  factory PromotePatchRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PromotePatchRequest',
      json,
      () => PromotePatchRequest(
        patchId: json['patch_id'] as int,
        channelId: json['channel_id'] as int,
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

  /// Converts a [PromotePatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'patch_id': patchId,
      'channel_id': channelId,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    patchId,
    channelId,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PromotePatchRequest &&
        patchId == other.patchId &&
        channelId == other.channelId;
  }
}
