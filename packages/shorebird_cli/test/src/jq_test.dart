import 'package:shorebird_cli/src/jq.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(JqQuery, () {
    const releases = [
      {
        'id': 1,
        'version': '1.0.0',
        'platforms': {'android': 'active', 'ios': 'draft'},
        'tags': ['stable'],
      },
      {
        'id': 2,
        'version': '1.0.1',
        'platforms': {'android': 'active'},
        'tags': <String>[],
      },
    ];

    List<Object?> run(String query, [Object? input = releases]) =>
        JqQuery.parse(query).evaluate(input);

    Matcher throwsJq(String message) => throwsA(
      isA<JqException>().having(
        (e) => e.toString(),
        'message',
        contains(message),
      ),
    );

    group('paths', () {
      test('identity', () {
        expect(run('.'), equals([releases]));
        expect(run(' . '), equals([releases]));
      });

      test('fields and nested fields', () {
        expect(run('.[0].version'), equals(['1.0.0']));
        expect(run('.[0].platforms.ios'), equals(['draft']));
        expect(run('.[0]."version"'), equals(['1.0.0']));
        expect(run('.[0] | ."version"'), equals(['1.0.0']));
        expect(run('.[0]["version"]'), equals(['1.0.0']));
        expect(run('.[0].missing'), equals([null]));
        expect(run('.a.b', null), equals([null]));
      });

      test('iteration over arrays and objects', () {
        expect(run('.[].id'), equals([1, 2]));
        expect(run('.[0].platforms[]'), equals(['active', 'draft']));
        expect(run('.[].tags[]'), equals(['stable']));
      });

      test('array indexes, including negative and out of range', () {
        expect(run('.[1].id'), equals([2]));
        expect(run('.[-1].id'), equals([2]));
        expect(run('.[5]'), equals([null]));
        expect(run('.[-5]'), equals([null]));
      });

      test('? suppresses errors', () {
        expect(run('.[].version[]?'), isEmpty);
        expect(run('.[0].id.x?'), isEmpty);
        expect(run('.a[]?', {'a': 1}), isEmpty);
      });

      test('reports indexing and iteration errors', () {
        expect(() => run('.x'), throwsJq('Cannot index array with "x"'));
        expect(
          () => run('.[0][0]'),
          throwsJq('Cannot index object with number'),
        );
        expect(() => run('.[0].id[]'), throwsJq('Cannot iterate over number'));
        expect(() => run('.[]', true), throwsJq('Cannot iterate over boolean'));
        expect(() => run('.[]', 's'), throwsJq('Cannot iterate over string'));
        expect(() => run('.[]', null), throwsJq('Cannot iterate over null'));
      });
    });

    group('pipes and commas', () {
      test('pipe feeds each output to the next filter', () {
        expect(run('.[] | .version'), equals(['1.0.0', '1.0.1']));
      });

      test('comma concatenates outputs', () {
        expect(run('.[0] | .id, .version'), equals([1, '1.0.0']));
      });

      test('parentheses group', () {
        expect(
          run('[.[] | (.id, .version)]'),
          equals([
            [1, '1.0.0', 2, '1.0.1'],
          ]),
        );
      });
    });

    group('select and comparisons', () {
      test('select keeps inputs whose condition is true', () {
        expect(run('.[] | select(.id == 2) | .version'), equals(['1.0.1']));
        expect(
          run('.[] | select(.platforms.ios != null) | .id'),
          equals([1]),
        );
      });

      test('comparison operators', () {
        expect(run('.[] | .id > 1'), equals([false, true]));
        expect(run('.[] | .id >= 1'), equals([true, true]));
        expect(run('.[] | .id < 2'), equals([true, false]));
        expect(run('.[] | .id <= 1'), equals([true, false]));
        expect(run('.[] | .version == "1.0.0"'), equals([true, false]));
        expect(run('.[0].tags == ["stable"]'), equals([true]));
      });

      test('orders values of different types the way jq does', () {
        expect(run('null < false and false < true and true < 0'), [true]);
        expect(run('0 < "a" and "a" < [] and [] < {}'), [true]);
        expect(run('"a" < "b" and [1, 2] < [1, 3] and [1] < [1, 2]'), [true]);
        expect(run('[1] >= [1]'), [true]);
        expect(() => run('{} < {}'), throwsJq('ordering objects'));
      });

      test('and, or and not', () {
        expect(run('true and false'), equals([false]));
        expect(run('null or 1'), equals([true]));
        expect(run('1 or (1 | keys)'), equals([true]));
        expect(run('false and (1 | keys)'), equals([false]));
        expect(run('.[] | .tags | length > 0 and true'), equals([true, false]));
        expect(run('.[] | (.id == 1) | not'), equals([false, true]));
        expect(
          run('[null, false, 0, ""] | map(not)'),
          equals([
            [true, true, false, false],
          ]),
        );
      });
    });

    group('construction', () {
      test('objects with names, strings, expressions and shorthand', () {
        expect(
          run('.[0] | {version, "number": .id, (.version): true, v: .tags[0]}'),
          equals([
            {'version': '1.0.0', 'number': 1, '1.0.0': true, 'v': 'stable'},
          ]),
        );
        expect(run('{}'), equals([<String, Object?>{}]));
      });

      test('objects with several values produce every combination', () {
        expect(
          run('{id: .[].id}'),
          equals([
            {'id': 1},
            {'id': 2},
          ]),
        );
      });

      test('rejects object keys that are not strings', () {
        expect(() => run('{(1): 2}'), throwsJq('object keys must be strings'));
        expect(() => run('{"a"}'), throwsJq('unsupported or invalid jq'));
      });

      test('arrays collect every output', () {
        expect(
          run('[.[].id]'),
          equals([
            [1, 2],
          ]),
        );
        expect(run('[]'), equals([<Object?>[]]));
        expect(run('[.[] | select(.id > 5)]'), equals([<Object?>[]]));
      });

      test('literals', () {
        expect(
          run('1, -2.5, 1e3, "s", true, false, null'),
          equals([
            1,
            -2.5,
            1000,
            's',
            true,
            false,
            null,
          ]),
        );
      });
    });

    group('strings', () {
      test('interpolation formats values the way raw output does', () {
        expect(
          run(r'.[] | "\(.version) (#\(.id)) \(.tags)"'),
          equals(['1.0.0 (#1) ["stable"]', '1.0.1 (#2) []']),
        );
      });

      test('interpolation with several outputs produces each string', () {
        expect(run(r'"v\(.[].id)"'), equals(['v1', 'v2']));
      });

      test('escapes', () {
        expect(run(r'"a\"b\\c\/d\ne\tf\rg"'), equals(['a"b\\c/d\ne\tf\rg']));
        expect(() => run(r'"\x41"'), throwsJq(r'unsupported escape "\x"'));
        expect(() => run('"abc'), throwsJq('unterminated string'));
        expect(() => run(r'"abc\'), throwsJq('unsupported or invalid jq'));
      });
    });

    group('functions', () {
      test('length', () {
        expect(run('length'), equals([2]));
        expect(run('.[0] | length'), equals([4]));
        expect(run('.[0].version | length'), equals([5]));
        expect(run('null | length'), equals([0]));
        expect(run('-3 | length'), equals([3]));
        expect(
          () => run('true | length'),
          throwsJq('boolean (true) has no length'),
        );
      });

      test('keys', () {
        expect(
          run('.[0] | keys'),
          equals([
            ['id', 'platforms', 'tags', 'version'],
          ]),
        );
        expect(
          run('keys'),
          equals([
            [0, 1],
          ]),
        );
        expect(() => run('1 | keys'), throwsJq('number has no keys'));
      });

      test('map', () {
        expect(
          run('map(.id)'),
          equals([
            [1, 2],
          ]),
        );
        expect(
          run('.[0].platforms | map(. == "active")'),
          equals([
            [true, false],
          ]),
        );
      });

      test('empty', () {
        expect(run('empty'), isEmpty);
        expect(
          run('[1, empty, 2]'),
          equals([
            [1, 2],
          ]),
        );
      });
    });

    group('unsupported syntax', () {
      for (final (query, message) in [
        ('sort_by(.id)', 'unsupported jq function or keyword "sort_by"'),
        ('if . then 1 else 2 end', 'unsupported jq function or keyword "if"'),
        ('.[0].id + 1', 'unsupported or invalid jq at position 9: "+ 1"'),
        ('.a // "x"', 'unsupported or invalid jq at position 4: "// "x""'),
        ('..', 'unsupported or invalid jq at position 1: ".."'),
        (r'.[] as $x | $x', r'at position 5: "as $x | $x"'),
        ('.[1:2]', 'at position 4: ":2]"'),
        ('.a.', 'at position 4: ""'),
        ('', 'at position 1: ""'),
        ('map .id', 'at position 5: ".id"'),
        ('.' * 30, '..."'),
      ]) {
        test('rejects $query', () {
          expect(() => JqQuery.parse(query), throwsJq(message));
        });
      }
    });

    group('format', () {
      test('prints strings raw and other values as JSON', () {
        expect(JqQuery.format('a "b"'), equals('a "b"'));
        expect(JqQuery.format(null), equals('null'));
        expect(
          JqQuery.format({
            'a': [1],
          }),
          equals('{"a":[1]}'),
        );
        expect(
          JqQuery.format({'a': 1}, indent: '  '),
          equals('{\n  "a": 1\n}'),
        );
      });
    });
  });
}
