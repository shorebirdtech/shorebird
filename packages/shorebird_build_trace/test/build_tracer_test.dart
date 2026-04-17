import 'dart:convert';
import 'dart:io';

import 'package:shorebird_build_trace/shorebird_build_trace.dart';
import 'package:test/test.dart';

void main() {
  group(BuildTraceEvent, () {
    test('toJson produces a Chrome Trace Event Format complete event', () {
      final event = BuildTraceEvent(
        name: 'gen_snapshot',
        cat: 'subprocess',
        ts: 100,
        dur: 200,
        pid: 42,
        tid: 1,
        args: {
          'argv': ['--foo'],
        },
      );

      expect(event.toJson(), {
        'ph': 'X',
        'name': 'gen_snapshot',
        'cat': 'subprocess',
        'ts': 100,
        'dur': 200,
        'pid': 42,
        'tid': 1,
        'args': {
          'argv': ['--foo'],
        },
      });
    });

    test('toJson omits args when null', () {
      final event = BuildTraceEvent(
        name: 'x',
        cat: 'c',
        ts: 0,
        dur: 1,
        pid: 1,
        tid: 1,
      );
      expect(event.toJson().containsKey('args'), isFalse);
    });

    test('fromJson round-trips', () {
      final event = BuildTraceEvent(
        name: 'n',
        cat: 'c',
        ts: 10,
        dur: 20,
        pid: 7,
        tid: 1,
        args: {'a': 1},
      );
      final parsed = BuildTraceEvent.fromJson(event.toJson());
      expect(parsed.name, 'n');
      expect(parsed.cat, 'c');
      expect(parsed.ts, 10);
      expect(parsed.dur, 20);
      expect(parsed.pid, 7);
      expect(parsed.tid, 1);
      expect(parsed.args, {'a': 1});
    });
  });

  group(BuildTracer, () {
    late Directory tempDir;
    late File traceFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('build_trace_test_');
      traceFile = File('${tempDir.path}/trace.json');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('addCompleteEvent records one ph:X event', () {
      BuildTracer()
        ..addCompleteEvent(
          name: 'x',
          cat: 'c',
          pid: 1,
          tid: 1,
          startMicros: 100,
          endMicros: 500,
        )
        ..writeToFile(traceFile);
      final decoded = jsonDecode(traceFile.readAsStringSync()) as List;
      expect(decoded, hasLength(1));
      final e = decoded.single as Map<String, Object?>;
      expect(e['ph'], 'X');
      expect(e['dur'], 400);
    });

    test('addProcessNameMetadata emits ph:M process_name', () {
      BuildTracer()
        ..addProcessNameMetadata(pid: 1, name: 'foo')
        ..writeToFile(traceFile);
      final m =
          (jsonDecode(traceFile.readAsStringSync()) as List).single
              as Map<String, Object?>;
      expect(m['ph'], 'M');
      expect(m['name'], 'process_name');
      expect((m['args']! as Map)['name'], 'foo');
    });

    test('addThreadNameMetadata emits ph:M thread_name', () {
      BuildTracer()
        ..addThreadNameMetadata(pid: 1, tid: 5, name: 'network')
        ..writeToFile(traceFile);
      final m =
          (jsonDecode(traceFile.readAsStringSync()) as List).single
              as Map<String, Object?>;
      expect(m['ph'], 'M');
      expect(m['name'], 'thread_name');
      expect(m['tid'], 5);
      expect((m['args']! as Map)['name'], 'network');
    });

    test('addFlowStart / addFlowEnd emit ph:s / ph:f with bp=e', () {
      final t = BuildTracer()
        ..addFlowStart(id: 99, pid: 1, tid: 1, atMicros: 10)
        ..addFlowEnd(id: 99, pid: 2, tid: 1, atMicros: 50);
      t.writeToFile(traceFile);
      final events = jsonDecode(traceFile.readAsStringSync()) as List;
      expect((events[0] as Map)['ph'], 's');
      expect((events[0] as Map)['id'], 99);
      expect((events[0] as Map)['bp'], 'e');
      expect((events[1] as Map)['ph'], 'f');
      expect((events[1] as Map)['id'], 99);
    });

    test('trace<T> records a span around a sync body', () {
      final t = BuildTracer();
      final result = t.trace<int>(
        name: 'work',
        cat: 'c',
        pid: 1,
        tid: 1,
        body: () => 42,
      );
      expect(result, 42);
      expect(t.eventCount, 1);
    });

    test('trace<T> records a span even when body throws', () {
      final t = BuildTracer();
      expect(
        () => t.trace<int>(
          name: 'work',
          cat: 'c',
          pid: 1,
          tid: 1,
          body: () => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(t.eventCount, 1);
    });

    test('traceAsync records a span around an async body', () async {
      final t = BuildTracer();
      final result = await t.traceAsync<int>(
        name: 'work',
        cat: 'c',
        pid: 1,
        tid: 1,
        body: () async => 7,
      );
      expect(result, 7);
      expect(t.eventCount, 1);
    });

    test('timeSubprocess emits a subprocess span and returns the result', () {
      final t = BuildTracer();
      final result = t.timeSubprocess(
        executable: '/usr/bin/true',
        arguments: const [],
        pid: 1,
        tid: 2,
        runner: () => ProcessResult(100, 0, '', ''),
      );
      expect(result.exitCode, 0);
      t.writeToFile(traceFile);
      final e =
          (jsonDecode(traceFile.readAsStringSync()) as List).single
              as Map<String, Object?>;
      expect(e['name'], 'true');
      expect(e['cat'], 'subprocess');
    });

    test(
      'timeSubprocessAsync records a span even when runner throws',
      () async {
        final t = BuildTracer();
        await expectLater(
          t.timeSubprocessAsync(
            executable: 'diff',
            arguments: const ['-u'],
            pid: 1,
            tid: 2,
            runner: () async => throw StateError('boom'),
          ),
          throwsA(isA<StateError>()),
        );
        expect(t.eventCount, 1);
      },
    );

    test('recordNetworkSpan formats name + args', () {
      BuildTracer()
        ..recordNetworkSpan(
          method: 'GET',
          host: 'api.example.com',
          pid: 1,
          tid: 3,
          startMicros: 0,
          endMicros: 1000,
          status: 200,
          contentLength: 42,
        )
        ..writeToFile(traceFile);
      final e =
          (jsonDecode(traceFile.readAsStringSync()) as List).single
              as Map<String, Object?>;
      expect(e['name'], 'GET api.example.com');
      expect(e['cat'], 'network');
      final args = e['args']! as Map;
      expect(args['method'], 'GET');
      expect(args['host'], 'api.example.com');
      expect(args['status'], 200);
      expect(args['contentLength'], 42);
    });

    test('writeToFile merges with existing events', () {
      traceFile.writeAsStringSync(
        jsonEncode([
          {
            'ph': 'X',
            'name': 'old',
            'cat': 'c',
            'ts': 0,
            'dur': 1,
            'pid': 1,
            'tid': 1,
          },
        ]),
      );
      BuildTracer()
        ..addCompleteEvent(
          name: 'new',
          cat: 'c',
          pid: 1,
          tid: 1,
          startMicros: 0,
          endMicros: 1,
        )
        ..writeToFile(traceFile);
      final decoded = jsonDecode(traceFile.readAsStringSync()) as List;
      expect(decoded, hasLength(2));
      expect((decoded[0] as Map)['name'], 'old');
      expect((decoded[1] as Map)['name'], 'new');
    });

    test('writeToFile overwrites corrupt existing file', () {
      traceFile.writeAsStringSync('not json');
      BuildTracer()
        ..addCompleteEvent(
          name: 'x',
          cat: 'c',
          pid: 1,
          tid: 1,
          startMicros: 0,
          endMicros: 1,
        )
        ..writeToFile(traceFile);
      final decoded = jsonDecode(traceFile.readAsStringSync()) as List;
      expect(decoded, hasLength(1));
    });

    test('writeToFile creates missing parent directories', () {
      final nested = File('${tempDir.path}/a/b/c/trace.json');
      BuildTracer()
        ..addCompleteEvent(
          name: 'x',
          cat: 'c',
          pid: 1,
          tid: 1,
          startMicros: 0,
          endMicros: 1,
        )
        ..writeToFile(nested);
      expect(nested.existsSync(), isTrue);
    });

    test('mergeEventsFromFile appends events as-is', () {
      final src = File('${tempDir.path}/src.json')
        ..writeAsStringSync(
          jsonEncode([
            {
              'ph': 'X',
              'name': 'from-file',
              'cat': 'c',
              'ts': 0,
              'dur': 1,
              'pid': 1,
              'tid': 1,
            },
          ]),
        );
      final t = BuildTracer()..mergeEventsFromFile(src);
      expect(t.eventCount, 1);
    });

    test('mergeEventsFromFile is a no-op on missing file', () {
      BuildTracer()
        ..mergeEventsFromFile(File('${tempDir.path}/missing.json'))
        ..writeToFile(traceFile);
      final decoded = jsonDecode(traceFile.readAsStringSync()) as List;
      expect(decoded, isEmpty);
    });
  });

  group(PhaseTracker, () {
    test('transitionTo records span for previous phase', () {
      final t = BuildTracer();
      final phases =
          PhaseTracker(
              tracer: t,
              pid: 1,
              tid: 1,
              namePrefix: 'pod install',
            )
            ..transitionTo('analyzing')
            ..transitionTo('downloading')
            ..end();
      expect(t.eventCount, 2);
      phases.toString(); // silence unused warning if any
    });

    test('end closes without starting a new phase', () {
      final t = BuildTracer();
      PhaseTracker(
          tracer: t,
          pid: 1,
          tid: 1,
          namePrefix: 'x',
        )
        ..transitionTo('a')
        ..end();
      expect(t.eventCount, 1);
    });

    test('no events when no phase was ever started', () {
      final t = BuildTracer();
      PhaseTracker(tracer: t, pid: 1, tid: 1, namePrefix: 'x').end();
      expect(t.eventCount, 0);
    });
  });

  group('currentProcessId', () {
    test('returns a positive integer that is stable within a process', () {
      final first = currentProcessId();
      expect(first, greaterThan(0));
      expect(currentProcessId(), first);
    });
  });
}
