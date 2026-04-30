// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_channel_request}
/// The request body for POST /apps/{appId}/channels.
/// {@endtemplate}
@immutable
class CreateChannelRequest {
  /// {@macro create_channel_request}
  const CreateChannelRequest({
    required this.channel,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateChannelRequest].
  factory CreateChannelRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateChannelRequest',
      json,
      () => CreateChannelRequest(
        channel: json['channel'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateChannelRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateChannelRequest.fromJson(json);
  }

  /// The channel name.
  final String channel;

  /// Converts a [CreateChannelRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'channel': channel,
    };
  }

  @override
  int get hashCode => channel.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateChannelRequest && channel == other.channel;
  }
}
