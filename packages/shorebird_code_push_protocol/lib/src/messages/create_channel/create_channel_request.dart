import 'package:json_annotation/json_annotation.dart';

part 'create_channel_request.g.dart';

/// {@template create_channel_request}
/// The request body for POST /api/v1/apps/<appId>/channels
/// {@endtemplate}
@JsonSerializable()
class CreateChannelRequest {
  /// {@macro create_channel_request}
  const CreateChannelRequest({required this.channel});

  /// Converts a Map<String, dynamic> to a [CreateChannelRequest]
  factory CreateChannelRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateChannelRequestFromJson(json);

  /// Converts a [CreateChannelRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreateChannelRequestToJson(this);

  /// The channel name.
  final String channel;
}
