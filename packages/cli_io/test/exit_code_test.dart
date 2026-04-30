import 'package:cli_io/cli_io.dart';
import 'package:test/test.dart';

void main() {
  group('ExitCode', () {
    test('codes match BSD sysexits.h values', () {
      expect(ExitCode.success.code, equals(0));
      expect(ExitCode.usage.code, equals(64));
      expect(ExitCode.data.code, equals(65));
      expect(ExitCode.noInput.code, equals(66));
      expect(ExitCode.noUser.code, equals(67));
      expect(ExitCode.noHost.code, equals(68));
      expect(ExitCode.unavailable.code, equals(69));
      expect(ExitCode.software.code, equals(70));
      expect(ExitCode.osError.code, equals(71));
      expect(ExitCode.osFile.code, equals(72));
      expect(ExitCode.cantCreate.code, equals(73));
      expect(ExitCode.ioError.code, equals(74));
      expect(ExitCode.tempFail.code, equals(75));
      expect(ExitCode.noPerm.code, equals(77));
      expect(ExitCode.config.code, equals(78));
    });

    test('toString includes name and code', () {
      expect(ExitCode.success.toString(), equals('success: 0'));
      expect(ExitCode.software.toString(), equals('software: 70'));
    });
  });
}
