import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/ios_deploy.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(IOSDeploy, () {
    late ShorebirdProcess process;
    late IOSDeploy iosDeploy;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      process = _MockShorebirdProcess();
      iosDeploy = IOSDeploy();
    });

    test('executes correct command', () async {
      const processResult = ShorebirdProcessResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
      );
      when(
        () => process.run(any(), any()),
      ).thenAnswer((_) async => processResult);
      const deviceId = 'test-device-id';
      const bundlePath = 'test-bundle-path';
      final result = await runWithOverrides(
        () => iosDeploy.installApp(
          deviceId: deviceId,
          bundlePath: bundlePath,
        ),
      );
      expect(result, equals(processResult.exitCode));
      verify(
        () => process.run(any(that: endsWith('ios-deploy')), [
          '--id',
          deviceId,
          '--bundle',
          bundlePath,
        ]),
      ).called(1);
    });
  });
}
