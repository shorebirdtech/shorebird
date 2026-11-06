import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:shorebird_cli/src/build_flags.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(BuildFlags, () {
    final parser = ArgParser()
      ..addMultiOption('dart-define', splitCommas: false)
      ..addMultiOption('dart-define-from-file', splitCommas: false);

    String hash(String value) => sha256.convert(utf8.encode(value)).toString();

    BuildFlags flags(List<String> args, {String? target}) =>
        BuildFlags.fromArgs(parser.parse(args), target: target);

    group('fromArgs', () {
      test('hashes each define value, never keeping it', () {
        final result = flags(['--dart-define=API_KEY=sec=ret']);

        expect(result.dartDefines, {'API_KEY': hash('sec=ret')});
        expect(json.encode(result.toJson()), isNot(contains('sec=ret')));
      });

      test('reads defines passed after --', () {
        final result = flags([
          '--',
          '--dart-define=A=1',
          '--dart-define',
          'B=2',
        ]);

        expect(result.dartDefines, {'A': hash('1'), 'B': hash('2')});
      });

      test('reads a JSON file, with --dart-define taking precedence', () {
        File('defines.json').writeAsStringSync(
          json.encode({'A': 'file', 'N': 3, 'B': true}),
        );

        final result = flags([
          '--dart-define-from-file=defines.json',
          '--dart-define=A=flag',
        ]);

        expect(result.dartDefines, {
          'A': hash('flag'),
          'N': hash('3'),
          'B': hash('true'),
        });
      });

      test('reads a .env file as Flutter does', () {
        File('.env').writeAsStringSync('''
# a comment
PLAIN=value # trailing
DOUBLE="foo#bar=baz"
SINGLE='quoted'
EMPTY=
''');

        final result = flags(['--dart-define-from-file=.env']);

        expect(result.dartDefines, {
          'PLAIN': hash('value'),
          'DOUBLE': hash('foo#bar=baz'),
          'SINGLE': hash('quoted'),
          'EMPTY': hash(''),
        });
      });

      test('throws for a missing define file', () {
        expect(
          () => flags(['--dart-define-from-file=missing.json']),
          throwsFormatException,
        );
      });

      test('hashes a target relative to the project, null for the '
          'default', () {
        expect(flags([], target: 'lib/main.dart').target, isNull);
        expect(flags([], target: './lib/main.dart').target, isNull);
        expect(
          flags([], target: './lib/main_prod.dart').target,
          equals(hash('lib/main_prod.dart')),
        );
        expect(
          flags(
            [],
            target: '${Directory.current.path}/lib/main_prod.dart',
          ).target,
          equals(hash('lib/main_prod.dart')),
        );
      });
    });

    test('reads what toJson wrote', () {
      final original = flags(['--dart-define=A=1'], target: 'lib/x.dart');

      final read = BuildFlags.fromJson(
        json.decode(json.encode(original.toJson())) as Map<String, dynamic>,
      );

      expect(read.dartDefines, original.dartDefines);
      expect(read.target, original.target);
    });

    group('differencesFrom', () {
      test('is empty when they match', () {
        expect(
          flags(['--dart-define=A=1']).differencesFrom(
            flags(['--dart-define=A=1']),
          ),
          isEmpty,
        );
      });

      test('names missing, extra and changed keys and the target', () {
        final release = flags([
          '--dart-define=GONE=1',
          '--dart-define=CHANGED=1',
        ], target: 'lib/main_prod.dart');
        final patch = flags([
          '--dart-define=CHANGED=2',
          '--dart-define=NEW=1',
        ]);

        expect(patch.differencesFrom(release), [
          '--dart-define missing: GONE',
          '--dart-define not in the release: NEW',
          '--dart-define with a different value: CHANGED',
          '--target differs from the release',
        ]);
      });
    });
  });
}
