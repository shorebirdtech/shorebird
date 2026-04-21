import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template channel}
/// A tag used to manage the subset of installs that receive a patch.
/// By default a "stable" channel is created and used by devices to
/// query for available patches.
/// {@endtemplate}
@immutable
class Channel {
  /// {@macro channel}
  const Channel({
    required this.id,
    required this.appId,
    required this.name,
  });

  /// Converts a `Map<String, dynamic>` to a [Channel].
  factory Channel.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'Channel',
      json,
      () => Channel(
        id: json['id'] as int,
        appId: json['app_id'] as String,
        name: json['name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static Channel? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return Channel.fromJson(json);
  }

  /// The ID of the channel.
  final int id;

  /// The ID of the app.
  final String appId;

  /// The channel name.
  final String name;

  /// Converts a [Channel] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'app_id': appId,
      'name': name,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    appId,
    name,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Channel &&
        id == other.id &&
        appId == other.appId &&
        name == other.name;
  }
}
