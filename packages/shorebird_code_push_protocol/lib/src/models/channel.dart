import 'package:json_annotation/json_annotation.dart';

part 'channel.g.dart';

/// {@template channel}
/// A release channel for an app
/// {@endtemplate}
@JsonSerializable()
class Channel {
  /// {@macro channel}
  const Channel({required this.id, required this.appId, required this.name});

  /// Converts a Map<String, dynamic> to a [Channel]
  factory Channel.fromJson(Map<String, dynamic> json) =>
      _$ChannelFromJson(json);

  /// Converts a [Channel] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$ChannelToJson(this);

  /// The ID of the channel;
  final int id;

  /// The ID of the app.
  final String appId;

  /// The channel name.
  final String name;
}
