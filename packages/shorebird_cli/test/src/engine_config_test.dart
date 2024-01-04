import 'package:shorebird_cli/src/engine_config.dart';
import 'package:test/test.dart';

void main() {
  group(EngineConfig, () {
    test('toString', () {
      const config = EngineConfig(
        localEngineSrcPath: 'a',
        localEngine: 'b',
        localEngineHost: 'c',
      );
      expect(
        config.toString(),
        equals(
          '''EngineConfig(localEngineSrcPath: a, localEngine: b, localEngineHost: c)''',
        ),
      );
    });
  });
}
