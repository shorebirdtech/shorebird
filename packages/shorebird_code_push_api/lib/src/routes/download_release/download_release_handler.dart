import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:shorebird_code_push_api/src/version_store.dart';

Future<Response> downloadReleaseHandler(
  Request request,
  String versionWithExtension,
) async {
  final version = path.withoutExtension(versionWithExtension);
  final releasePath =
      request.lookup<VersionStore>().filePathForVersion(version);
  final file = File(releasePath);
  if (!file.existsSync()) return Response.notFound('Release not found');
  final bytes = file.openRead();
  return Response.ok(bytes);
}
