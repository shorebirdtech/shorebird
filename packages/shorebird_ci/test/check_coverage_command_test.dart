// cspell:words BRDA

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:shorebird_ci/src/lcov.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// An lcov record for [file] with [hits] per line, numbered from 1.
String record(String file, List<int> hits) => [
  'SF:$file',
  for (final (i, h) in hits.indexed) 'DA:${i + 1},$h',
  'LF:${hits.length}',
  'LH:${hits.where((h) => h > 0).length}',
  'end_of_record',
  '',
].join('\n');

void main() {
  group(LcovReport, () {
    test('counts lines found and hit', () {
      final report = LcovReport.parse([
        record('lib/a.dart', [1, 0, 3]) + record('lib/b.dart', [0]),
      ]);
      expect(report.linesFound, 4);
      expect(report.linesHit, 2);
      expect(report.percent, 50);
      expect(report.uncoveredLines, {
        'lib/a.dart': [2],
        'lib/b.dart': [1],
      });
    });

    test('sums hits per line across tracefiles', () {
      final report = LcovReport.parse([
        record('lib/a.dart', [1, 0]),
        record('lib/a.dart', [0, 2]),
      ]);
      expect(report.linesFound, 2);
      expect(report.linesHit, 2);
      expect(report.uncoveredLines, isEmpty);
    });

    test('reads DA checksums and ignores other records', () {
      const tracefile =
          'TN:\nSF:lib/a.dart\nFN:1,f\nDA:1,0,abc\nDA:2,4,def\n'
          'BRDA:1,0,0,1\nend_of_record\n';
      final report = LcovReport.parse([tracefile]);
      expect(report.linesFound, 2);
      expect(report.linesHit, 1);
    });

    test('ignores DA lines outside a record', () {
      final report = LcovReport.parse(['DA:1,0\n']);
      expect(report.linesFound, 0);
      expect(report.percent, 0);
    });

    test('throws on a malformed DA line', () {
      expect(
        () => LcovReport.parse(['SF:a.dart\nDA:1\nend_of_record\n']),
        throwsFormatException,
      );
    });

    test('excludes absolute, relative and Windows paths by glob', () {
      final report = LcovReport.parse([
        record('/home/runner/work/x/lib/a.g.dart', [0]) +
            record('lib/b.g.dart', [0]) +
            record(r'C:\work\lib\c.g.dart', [0]) +
            record('lib/d.dart', [1]),
      ]).exclude(['**/*.g.dart']);
      expect(report.files, ['lib/d.dart']);
      expect(report.percent, 100);
    });

    test('excludes by absolute glob', () {
      final report = LcovReport.parse([
        record('/repo/lib/gen/a.dart', [0]) + record('/repo/lib/b.dart', [1]),
      ]).exclude(['/repo/lib/gen/**']);
      expect(report.files, ['/repo/lib/b.dart']);
    });
  });

  group(CheckCoverageCommand, () {
    setUpTempDir('shorebird_ci_check_coverage_command_');

    String write(String name, String contents) {
      final file = File(p.join(tempDir.path, name))
        ..writeAsStringSync(contents);
      return file.path;
    }

    Future<int?> run(List<String> args) {
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(CheckCoverageCommand());
      return runner.run(['check_coverage', ...args]);
    }

    test('passes at the minimum', () async {
      final lcov = write('lcov.info', record('lib/a.dart', [1, 0]));
      expect(await run([lcov, '--min', '50']), 0);
    });

    test('fails below the minimum', () async {
      final lcov = write('lcov.info', record('lib/a.dart', [1, 0]));
      expect(await run([lcov, '--min', '50.1']), 1);
    });

    test('needs 100 by default', () async {
      final lcov = write('lcov.info', record('lib/a.dart', [1, 0]));
      expect(await run([lcov]), 1);
    });

    test('passes at 100 with nothing uncovered', () async {
      final lcov = write('lcov.info', record('lib/a.dart', [1, 1]));
      expect(await run([lcov]), 0);
    });

    test('reads coverage/lcov.info when given no files', () async {
      Directory(p.join(tempDir.path, 'coverage')).createSync();
      write(p.join('coverage', 'lcov.info'), record('lib/a.dart', [1]));
      final cwd = Directory.current;
      Directory.current = tempDir;
      addTearDown(() => Directory.current = cwd);
      expect(await run([]), 0);
    });

    test('merges several files', () async {
      final a = write('a.info', record('lib/a.dart', [1, 0]));
      final b = write('b.info', record('lib/a.dart', [0, 1]));
      expect(await run([a, b]), 0);
    });

    test('splits --exclude on spaces', () async {
      final lcov = write(
        'lcov.info',
        record('lib/a.g.dart', [0]) +
            record('lib/b.freezed.dart', [0]) +
            record('lib/c.dart', [1]),
      );
      expect(
        await run([lcov, '--exclude', '**/*.g.dart **/*.freezed.dart']),
        0,
      );
    });

    test('fails when every line is excluded', () async {
      final lcov = write('lcov.info', record('lib/a.g.dart', [1]));
      expect(await run([lcov, '--exclude', '**/*.g.dart']), 1);
    });

    test('fails on a missing file', () async {
      expect(await run([p.join(tempDir.path, 'none.info'), '--min', '0']), 1);
    });

    test('fails on an empty file', () async {
      final lcov = write('lcov.info', '\n');
      expect(await run([lcov, '--min', '0']), 1);
    });

    test('fails on a malformed file', () async {
      final lcov = write('lcov.info', 'SF:a.dart\nDA:x,1\nend_of_record\n');
      expect(await run([lcov, '--min', '0']), 1);
    });

    test('has a description', () {
      expect(CheckCoverageCommand().description, isNotEmpty);
    });

    test('fails on a file with no source records', () async {
      final lcov = write('lcov.info', 'TN:\n');
      expect(await run([lcov, '--min', '0']), 1);
    });

    for (final min in ['abc', '-1', '101', 'NaN']) {
      test('rejects --min $min', () async {
        final lcov = write('lcov.info', record('lib/a.dart', [1]));
        expect(run([lcov, '--min', min]), throwsA(isA<UsageException>()));
      });
    }
  });
}
