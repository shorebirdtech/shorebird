import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/form_data.dart';
import 'package:shelf_multipart/multipart.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:shorebird_code_push_api/src/version_store.dart';

Future<Response> uploadReleaseHandler(Request request) async {
  if (!request.isMultipart || !request.isMultipartForm) {
    return Response.badRequest(body: 'Expected multipart form request');
  }

  final store = request.lookup<VersionStore>();

  store.cacheDir.createSync(recursive: true);

  final nextVersion = store.getNextVersion();
  final path = store.filePathForVersion(nextVersion);

  var foundFile = false;

  try {
    await for (final formData in request.multipartFormData) {
      // 'file' is just the name of the field we used in this form.
      if (formData.name == 'file') {
        if (foundFile) {
          throw Exception('Unexpected form data: ${formData.name}');
        }
        final file = File(path);
        await file.create();
        await file.writeAsBytes(await formData.part.readBytes(), flush: true);
        foundFile = true;
        continue;
      } else {
        throw Exception('Unexpected form data: ${formData.name}');
      }
    }
    if (!foundFile) throw Exception('Missing file');
  } catch (error) {
    return Response.badRequest(body: error.toString());
  }

  return Response(HttpStatus.created, body: 'OK');
}
