import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// Root route handler.
Response onRequest(RequestContext context) {
  return Response.json(
    body: {
      'name': 'Shorebird Self-Hosted CodePush API',
      'version': '1.0.0',
      'documentation': 'https://docs.shorebird.dev',
    },
  );
}
