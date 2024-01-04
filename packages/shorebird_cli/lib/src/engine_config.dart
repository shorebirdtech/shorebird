import 'package:scoped/scoped.dart';

// A reference to a [EngineConfig] instance.
final engineConfigRef = create(() => const EngineConfig.empty());

// The [EngineConfig] instance available in the current zone.
EngineConfig get engineConfig => read(engineConfigRef);

class EngineConfig {
  const EngineConfig({
    this.localEngineSrcPath,
    this.localEngine,
    this.localEngineHost,
  });

  const EngineConfig.empty()
      : localEngineSrcPath = null,
        localEngine = null,
        localEngineHost = null;

  final String? localEngineSrcPath;
  final String? localEngine;
  final String? localEngineHost;

  @override
  String toString() {
    return '''EngineConfig(localEngineSrcPath: $localEngineSrcPath, localEngine: $localEngine, localEngineHost: $localEngineHost)''';
  }
}
