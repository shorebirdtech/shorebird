import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_process_tools/shorebird_process_tools.dart';

class MockDirectory extends Mock implements Directory {}

class MockFile extends Mock implements File {}

class MockGit extends Mock implements Git {}

class MockIOSink extends Mock implements IOSink {}

class MockShorebirdProcessResult extends Mock
    implements ShorebirdProcessResult {}

class MockProcessSignal extends Mock implements ProcessSignal {}

class MockProcessWrapper extends Mock implements ProcessWrapper {}

class MockProcess extends Mock implements Process {}

class MockProgress extends Mock implements Progress {}

class MockStdin extends Mock implements Stdin {}

class MockStdout extends Mock implements Stdout {}
