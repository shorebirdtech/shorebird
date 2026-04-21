import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template app}
/// The application downloaded and run on various devices/platforms.
/// {@endtemplate}
@immutable
class App {
  /// {@macro app}
  const App({
    required this.id,
    required this.displayName,
  });

  /// Converts a `Map<String, dynamic>` to an [App].
  factory App.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'App',
      json,
      () => App(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static App? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return App.fromJson(json);
  }

  /// The ID of the app.
  final String id;

  /// The display name of the app.
  final String displayName;

  /// Converts an [App] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    displayName,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is App && id == other.id && displayName == other.displayName;
  }
}
