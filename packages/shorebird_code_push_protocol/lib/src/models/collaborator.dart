import 'package:json_annotation/json_annotation.dart';

part 'collaborator.g.dart';

/// {@template collaborator}
/// A user who has permission to collaborate on an app.
/// {@endtemplate}
@JsonSerializable()
class Collaborator {
  /// {@macro collaborator}
  const Collaborator({required this.userId, required this.email});

  /// Converts a Map<String, dynamic> to an [Collaborator]
  factory Collaborator.fromJson(Map<String, dynamic> json) =>
      _$CollaboratorFromJson(json);

  /// Converts a [Collaborator] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CollaboratorToJson(this);

  /// The unique identifier for the user.
  final int userId;

  /// The email address of the user.
  final String email;
}
