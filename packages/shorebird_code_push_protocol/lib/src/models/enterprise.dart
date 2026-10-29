import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template enterprise}
/// An enterprise, as its admins read it.
/// {@endtemplate}
@immutable
class Enterprise {
  /// {@macro enterprise}
  const Enterprise({
    required this.id,
    required this.name,
    required this.domains,
  });

  /// Converts a `Map<String, dynamic>` to an [Enterprise].
  factory Enterprise.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'Enterprise',
      json,
      () => Enterprise(
        id: json['id'] as int,
        name: json['name'] as String,
        domains: (json['domains'] as List).cast<String>(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static Enterprise? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return Enterprise.fromJson(json);
  }

  final int id;
  final String name;

  /// The domains it owns.
  final List<String> domains;

  /// Converts an [Enterprise] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'domains': domains,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    listHash(domains),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Enterprise &&
        id == other.id &&
        name == other.name &&
        listsEqual(domains, other.domains);
  }
}
