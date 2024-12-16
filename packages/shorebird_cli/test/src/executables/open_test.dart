import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Open, () {
    late Open open;
    late ShorebirdProcess process;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      process = MockShorebirdProcess();
      open = Open();
    });

    group('newApplication', () {
      test('executes correct command and streams logs', () async {
        final openProcess = MockProcess();
        final tailProcess = MockProcess();

        when(() => process.start('open', any())).thenAnswer((_) async {
          return openProcess;
        });
        when(() => process.start('tail', any())).thenAnswer((_) async {
          return tailProcess;
        });

        when(() => tailProcess.stdout).thenAnswer(
          (_) => Stream.fromIterable([utf8.encode('hello world') as List<int>]),
        );

        final stream = await runWithOverrides(
          () => open.newApplication(path: 'test'),
        );

        expect(stream, emits(utf8.encode('hello world')));
      });
    });
  });
}
