import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

class _MockPlatform extends Mock implements Platform {}

class TestCommand extends ShorebirdCommand {
  @override
  String get description => 'test';

  @override
  String get name => 'test';
}

void main() {
  group('ShorebirdCommand', () {
    late Platform platform;
    late ShorebirdCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
        },
      );
    }

    setUp(() {
      platform = _MockPlatform();
      when(() => platform.environment).thenReturn(const {});
      command = runWithOverrides(TestCommand.new);
    });

    group('hostedUrl', () {
      test('returns hosted url from env if available', () {
        when(() => platform.environment).thenReturn({
          'SHOREBIRD_HOSTED_URL': 'https://example.com',
        });
        expect(
          runWithOverrides(() => command.hostedUri),
          equals(Uri.parse('https://example.com')),
        );
      });

      test('falls back to shorebird.yaml', () {
        final directory = Directory.systemTemp.createTempSync();
        File(p.join(directory.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: test-id
base_url: https://example.com''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => command.hostedUri),
            getCurrentDirectory: () => directory,
          ),
          equals(Uri.parse('https://example.com')),
        );
      });

      test('returns null when there is no env override or shorebird.yaml', () {
        expect(runWithOverrides(() => command.hostedUri), isNull);
      });
    });
  });
}
