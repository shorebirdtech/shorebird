import 'package:json_annotation/json_annotation.dart';

part 'promote_patch_request.g.dart';

/// {@template promote_patch_request}
/// The request body for POST /api/v1/patches/promote
/// {@endtemplate}
@JsonSerializable()
class PromotePatchRequest {
  /// {@macro promote_patch_request}
  const PromotePatchRequest({required this.patchId, required this.channelId});

  /// Converts a Map<String, dynamic> to a [PromotePatchRequest]
  factory PromotePatchRequest.fromJson(Map<String, dynamic> json) =>
      _$PromotePatchRequestFromJson(json);

  /// Converts a [PromotePatchRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$PromotePatchRequestToJson(this);

  /// The ID of the patch.
  final int patchId;

  /// The ID of the channel.
  final int channelId;
}
