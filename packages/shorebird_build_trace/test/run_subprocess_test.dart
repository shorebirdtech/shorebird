import 'dart:io';

import 'package:shorebird_build_trace/shorebird_build_trace.dart';
import 'package:test/test.dart';

void main() {
  group('runSubprocess', () {
    // runSubprocess branches on BuildTracer.current, which is process-global,
    // so make sure no test leaks its installation into the next.
    tearDown(BuildTracer.stop);

    test(
      'falls through to Process.run when no tracer is installed',
      () async {
        expect(BuildTracer.current, isNull);
        final result = await runSubprocess(
          Platform.resolvedExecutable,
          const ['--version'],
        );
        expect(result.exitCode, 0);
      },
    );

    test(
      'routes through BuildTracer.startAndTraceSubprocess when installed '
      'and records a subprocess span on the child pid',
      () async {
        final tracer = BuildTracer();
        late ProcessResult result;
        await BuildTracer.runAsync(tracer, () async {
          result = await runSubprocess(
            Platform.resolvedExecutable,
            const ['--version'],
          );
        });
        expect(result.exitCode, 0);
        expect(result.pid, greaterThan(0));

        // Expect process_name + thread_name metadata + one subprocess span
        // on the child's real OS pid.
        final phs = tracer.events.map((e) => e['ph']).toList();
        expect(phs, containsAll(<String>['M', 'M', 'X']));
        for (final e in tracer.events) {
          expect(e['pid'], result.pid);
        }
      },
    );
  });
}
