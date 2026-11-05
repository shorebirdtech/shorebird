import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shorebird_ci/src/lcov.dart';

/// Fails when line coverage in lcov tracefiles is below a floor.
class CheckCoverageCommand extends Command<int> {
  /// Creates a [CheckCoverageCommand].
  CheckCoverageCommand() {
    argParser
      ..addOption(
        'min',
        help: 'Lowest passing line coverage, as a percentage.',
        defaultsTo: '100',
      )
      ..addMultiOption(
        'exclude',
        help:
            'Glob of source files to leave out, such as "**/*.g.dart". '
            'Repeat it, or separate globs with spaces.',
        splitCommas: false,
      );
  }

  @override
  String get name => 'check_coverage';

  @override
  String get description =>
      'Fail when line coverage is below --min. Takes lcov tracefiles '
      '(default coverage/lcov.info); several are merged, summing hits per '
      'line.';

  @override
  String get invocation => 'shorebird_ci check_coverage [lcov files] [args]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final min = double.tryParse(args['min'] as String);
    if (min == null || min < 0 || min > 100) {
      usageException('--min must be a number from 0 to 100.');
    }
    final excludes = [
      for (final value in args['exclude'] as List<String>)
        ...value.split(RegExp(r'\s+')).where((g) => g.isNotEmpty),
    ];
    final paths = args.rest.isEmpty ? ['coverage/lcov.info'] : args.rest;

    final tracefiles = <String>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        stderr.writeln('No lcov file at $path.');
        return 1;
      }
      final text = file.readAsStringSync();
      if (text.trim().isEmpty) {
        stderr.writeln(
          'Empty lcov file at $path: did the tests write coverage?',
        );
        return 1;
      }
      tracefiles.add(text);
    }

    final LcovReport report;
    try {
      report = LcovReport.parse(tracefiles).exclude(excludes);
    } on FormatException catch (e) {
      stderr.writeln('Could not parse lcov: ${e.message}: ${e.source}');
      return 1;
    }

    final percent = report.percent;
    final summary =
        'Line coverage: ${percent.toStringAsFixed(2)}% '
        '(${report.linesHit} of ${report.linesFound} lines), minimum $min%.';
    final uncovered = report.uncoveredLines;
    final missing = [
      if (uncovered.isNotEmpty) 'Lines not covered:',
      for (final MapEntry(key: file, value: lines) in uncovered.entries)
        '  $file: ${lines.join(', ')}',
    ].join('\n');

    if (percent < min) {
      stderr
        ..writeln(summary)
        ..writeln(missing);
      return 1;
    }
    stdout.writeln(summary);
    if (missing.isNotEmpty) stdout.writeln(missing);
    return 0;
  }
}
