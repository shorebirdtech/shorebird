import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/version_store.dart';

Future<Response> downloadReleaseHandler(
  Request request,
  String versionWithExtension,
) async {
  final version = path.withoutExtension(versionWithExtension);
  final releasePath = VersionStore.instance.filePathForVersion(version);
  final bytes = File(releasePath).openRead();
  return Response.ok(bytes);
}
