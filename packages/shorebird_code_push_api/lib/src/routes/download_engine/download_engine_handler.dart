import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';

final _engineUrl = Uri.parse(
  'https://storage.googleapis.com/download/storage/v1/b/shorebird-code-push-api.appspot.com/o/${Uri.encodeComponent('engines/engine.zip')}?alt=media',
);

Future<Response> downloadEngineHandler(Request request, String revision) async {
  final httpClient = request.lookup<http.Client>();
  final req = http.Request('GET', _engineUrl);
  req.headers.addAll(
    {
      'Content-Type': 'application/octet-stream',
      'Connection': 'close',
    },
  );
  final response = await httpClient.send(req);

  if (response.statusCode != HttpStatus.ok) {
    return Response(response.statusCode, body: response.stream);
  }

  return Response.ok(response.stream);
}
