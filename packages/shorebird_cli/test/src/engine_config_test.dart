import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:test/test.dart';

void main() {
  group(EngineConfig, () {
    test('creates an empty scoped ref', () async {
      const emptyConfig = EngineConfig.empty();
      runScoped(() {
        expect(engineConfig, equals(emptyConfig));
      }, values: {engineConfigRef});
    });

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
