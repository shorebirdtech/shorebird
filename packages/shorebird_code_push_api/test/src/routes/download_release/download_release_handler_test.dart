import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:shorebird_code_push_api/src/routes/download_release/download_release.dart';
import 'package:shorebird_code_push_api/src/version_store.dart';
import 'package:test/test.dart';

class _MockVersionStore extends Mock implements VersionStore {}

void main() {
  group('downloadReleaseHandler', () {
    final uri = Uri.parse('http://localhost/');
    late VersionStore store;

    setUp(() {
      store = _MockVersionStore();
    });

    test('returns 404 if release not found', () async {
      when(() => store.filePathForVersion('1.0.0')).thenReturn('not-found');

      final request = Request('GET', uri).provide(() => store);
      final response = await downloadReleaseHandler(request, '1.0.0.txt');

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('returns 200 if release found', () async {
      when(
        () => store.filePathForVersion('1.0.0'),
      ).thenReturn(path.join('test', 'fixtures', 'release.txt'));

      final request = Request('GET', uri).provide(() => store);
      final response = await downloadReleaseHandler(request, '1.0.0.txt');

      expect(response.statusCode, HttpStatus.ok);
    });
  });
}
