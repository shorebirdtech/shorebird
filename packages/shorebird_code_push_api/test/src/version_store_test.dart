import 'dart:io';

import 'package:shorebird_code_push_api/src/version_store.dart';
import 'package:test/test.dart';

void main() {
  group('VersionStore', () {
    group('getNextVersion', () {
      test('returns 0.0.1 when no versions exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        final store = VersionStore(cachePath: tempDir.path);
        expect(store.getNextVersion(), equals('0.0.1'));
      });

      test('returns 0.0.2 when 0.0.1 exists', () {
        final tempDir = Directory.systemTemp.createTempSync();
        final store = VersionStore(cachePath: tempDir.path)
          ..addVersion('0.0.1', []);
        expect(store.getNextVersion(), equals('0.0.2'));
      });
    });

    group('latestVersionForClient', () {
      test('returns null when cache does not exist', () {
        const store = VersionStore(cachePath: 'invalid-path');
        expect(store.latestVersionForClient('empty-client-id'), isNull);
      });

      test('returns null when no versions exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        final store = VersionStore(cachePath: tempDir.path);
        expect(store.latestVersionForClient('empty-client-id'), isNull);
      });

      test('returns latest version when multiple versions exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        final store = VersionStore(cachePath: tempDir.path)
          ..addVersion('0.0.1', [])
          ..addVersion('0.0.2', []);
        expect(
          store.latestVersionForClient('empty-client-id'),
          equals('0.0.2'),
        );
      });

      test('returns null when current version is the latest version', () {
        final tempDir = Directory.systemTemp.createTempSync();
        final store = VersionStore(cachePath: tempDir.path)
          ..addVersion('0.0.1', [])
          ..addVersion('0.0.2', []);
        expect(
          store.latestVersionForClient(
            'empty-client-id',
            currentVersion: '0.0.2',
          ),
          isNull,
        );
      });
    });
  });
}
