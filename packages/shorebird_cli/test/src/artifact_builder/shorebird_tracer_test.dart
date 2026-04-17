import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdTracer, () {
    late ShorebirdTracer tracer;

    setUp(() {
      tracer = ShorebirdTracer();
    });

    test('addNetworkEvent writes a cat=network span on network tid', () {
      tracer.addNetworkEvent(
        name: 'GET api.shorebird.dev',
        startMicros: 0,
        durationMicros: 1,
      );
      expect(tracer.events, hasLength(1));
      final e = tracer.events.single;
      expect(e['cat'], 'network');
      expect(e['tid'], 1);
      expect(e['pid'], isA<int>());
    });

    test('span records a completed event for a successful body', () async {
      final result = await tracer.span<int>(
        name: 'unit-test',
        category: 'shorebird',
        body: () async => 42,
      );
      expect(result, 42);
      expect(tracer.events, hasLength(1));
      final e = tracer.events.single;
      expect(e['name'], 'unit-test');
      expect(e['cat'], 'shorebird');
    });

    test('span records an event even when body throws', () async {
      await expectLater(
        tracer.span<int>(
          name: 'unit-test',
          category: 'shorebird',
          body: () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(tracer.events, hasLength(1));
      expect(tracer.events.single['name'], 'unit-test');
    });

    test('span forwards args', () async {
      await tracer.span<void>(
        name: 'x',
        category: 'c',
        args: {'k': 'v'},
        body: () async {},
      );
      expect(tracer.events.single['args'], {'k': 'v'});
    });

    test('addSpawnFlowStart emits ph:s flow event', () {
      tracer.addSpawnFlowStart(id: 4242, atMicros: 1000);
      final event = tracer.events.single;
      expect(event['ph'], 's');
      expect(event['id'], 4242);
      expect(event['ts'], 1000);
      expect(event['bp'], 'e');
    });

    group('mergeInto', () {
      late Directory tempDir;
      late File traceFile;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('shorebird_tracer_test_');
        traceFile = File('${tempDir.path}/trace.json');
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test(
        'appends events + process/thread metadata to an existing trace',
        () {
          traceFile.writeAsStringSync(
            jsonEncode([
              {
                'ph': 'X',
                'name': 'flutter build',
                'cat': 'flutter',
                'ts': 0,
                'dur': 100,
                'pid': 1,
                'tid': 1,
              },
            ]),
          );
          tracer.addNetworkEvent(
            name: 'POST api.shorebird.dev',
            startMicros: 200,
            durationMicros: 50,
          );

          tracer.mergeInto(traceFile);

          final decoded = jsonDecode(traceFile.readAsStringSync()) as List;
          // 1 pre-existing flutter span + 1 shorebird network span +
          // 3 metadata (process_name + 2 thread_name) = 5 events.
          expect(decoded, hasLength(5));
          expect((decoded[0] as Map)['name'], 'flutter build');
          expect((decoded[1] as Map)['name'], 'POST api.shorebird.dev');
          // Metadata events come after the spans when written.
          expect((decoded[2] as Map)['name'], 'process_name');
          expect((decoded[3] as Map)['name'], 'thread_name');
          expect((decoded[4] as Map)['name'], 'thread_name');
        },
      );

      test('no-op when the trace file does not exist', () {
        tracer.addNetworkEvent(
          name: 'x',
          startMicros: 0,
          durationMicros: 1,
        );
        tracer.mergeInto(traceFile);
        expect(traceFile.existsSync(), isFalse);
      });

      test('no-op when existing file is not a JSON array', () {
        traceFile.writeAsStringSync('{"not":"an array"}');
        tracer.addNetworkEvent(
          name: 'x',
          startMicros: 0,
          durationMicros: 1,
        );
        tracer.mergeInto(traceFile);
        expect(traceFile.readAsStringSync(), '{"not":"an array"}');
      });

      test('no-op when existing file is malformed JSON', () {
        traceFile.writeAsStringSync('not json');
        tracer.addNetworkEvent(
          name: 'x',
          startMicros: 0,
          durationMicros: 1,
        );
        tracer.mergeInto(traceFile);
        expect(traceFile.readAsStringSync(), 'not json');
      });
    });
  });

  group('shorebirdTracerRef', () {
    test('resolves to a ShorebirdTracer inside a scope', () {
      final tracer = runScoped(
        () => shorebirdTracer,
        values: {shorebirdTracerRef},
      );
      expect(tracer, isA<ShorebirdTracer>());
    });
  });
}
