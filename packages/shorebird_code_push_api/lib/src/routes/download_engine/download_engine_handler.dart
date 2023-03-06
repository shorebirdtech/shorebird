import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';

final engineUrl = Uri.parse(
  'https://storage.googleapis.com/download/storage/v1/b/shorebird-code-push-api.appspot.com/o/${Uri.encodeComponent('engines/engine.zip')}?alt=media',
);

Future<Response> downloadEngineHandler(Request request, String revision) async {
  final httpClient = await request.lookup<Future<http.Client>>();
  final response = await httpClient.get(
    engineUrl,
    headers: {
      'Content-Type': 'application/octet-stream',
      'Connection': 'close'
    },
  );

  if (response.statusCode != HttpStatus.ok) {
    return Response(response.statusCode, body: response.body);
  }

  return Response.ok(response.bodyBytes);
}
