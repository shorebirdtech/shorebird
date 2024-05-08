import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

Matcher exitsWithCode(ExitCode exitcode) => throwsA(
      isA<ProcessExit>().having(
        (e) => e.exitCode,
        'exitCode',
        exitcode.code,
      ),
    );
