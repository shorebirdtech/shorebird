import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/check_for_updates/check_for_updates.dart';
import 'package:shorebird_code_push_api/src/version_store.dart';

Future<Response> checkForUpdatesHandler(Request request) async {
  late final CheckForUpdatesRequest checkForUpdatesRequest;
  try {
    checkForUpdatesRequest = CheckForUpdatesRequest.fromJson(
      jsonDecode(await request.readAsString()) as Map<String, dynamic>,
    );
  } catch (_) {
    return Response.badRequest(
      body: 'Invalid request body',
      headers: {HttpHeaders.contentTypeHeader: ContentType.text.value},
    );
  }

  final latestVersion = VersionStore.instance.latestVersionForClient(
    checkForUpdatesRequest.clientId,
    currentVersion: checkForUpdatesRequest.version,
  );

  final response = latestVersion == null
      ? const CheckForUpdatesResponse()
      : CheckForUpdatesResponse(
          updateAvailable: true,
          update: Update(version: latestVersion, hash: ''),
        );

  return Response.ok(
    json.encode(response.toJson()),
    headers: {HttpHeaders.contentTypeHeader: ContentType.json.value},
  );
}
