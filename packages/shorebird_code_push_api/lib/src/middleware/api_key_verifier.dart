import 'dart:io';

import 'package:shelf/shelf.dart';

Middleware apiKeyVerifier({List<String> keys = const []}) {
  return (handler) {
    return (request) async {
      final apiKey = request.headers['x-api-key'];
      if (!keys.contains(apiKey)) return Response(HttpStatus.unauthorized);
      return handler(request);
    };
  };
}
