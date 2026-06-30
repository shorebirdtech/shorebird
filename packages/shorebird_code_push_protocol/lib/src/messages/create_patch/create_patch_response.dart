// Spec descriptions copy prose verbatim into dartdoc, where `[x]`
// inside a sentence (placeholder text, ALL_CAPS tokens, license
// templates) is parsed as a symbol reference even when no such
// symbol exists. Suppress file-locally so the lint stays live
// elsewhere; spec authors do not always escape brackets.
// ignore_for_file: comment_references
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_patch_response}
/// The response body for POST /apps/{appId}/patches. Deliberately
/// narrower than [Patch]: a freshly-created patch has no `notes`
/// yet (those are set via PATCH /.../{patchId}), so this endpoint
/// exposes only the identifiers the client needs to upload
/// artifacts.
/// {@endtemplate}
@immutable
class CreatePatchResponse {
  /// {@macro create_patch_response}
  const CreatePatchResponse({
    required this.id,
    required this.number,
    this.clientPatchId,
    this.channel,
  });

  /// Converts a `Map<String, dynamic>` to a [CreatePatchResponse].
  factory CreatePatchResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreatePatchResponse',
      json,
      () => CreatePatchResponse(
        id: json['id'] as int,
        number: json['number'] as int,
        clientPatchId: json['client_patch_id'] as String?,
        channel: json['channel'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreatePatchResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreatePatchResponse.fromJson(json);
  }

  /// The unique patch identifier.
  final int id;

  /// The patch number. A larger number equates to a newer patch.
  final int number;

  /// The client-supplied correlation key, if one was provided on the
  /// request. Echoed back so callers can verify whether an
  /// idempotent re-use occurred. See `CreatePatchRequest.client_patch_id`.
  final String? clientPatchId;

  /// The channel this patch is currently promoted to, if any. Null on a
  /// freshly-created patch (the common path) and on idempotent hits where
  /// the existing patch has not been promoted. When non-null on an
  /// idempotent hit it tells the client that uploading further artifacts
  /// will go live to that channel's users immediately — letting the
  /// client surface the append-after-promotion case without a second
  /// round-trip to list patches.
  final String? channel;

  /// Converts a [CreatePatchResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'client_patch_id': clientPatchId,
      'channel': channel,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    number,
    clientPatchId,
    channel,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreatePatchResponse &&
        id == other.id &&
        number == other.number &&
        clientPatchId == other.clientPatchId &&
        channel == other.channel;
  }
}
