// A reference to a [EngineConfig] instance.
import 'package:scoped/scoped.dart';

final engineConfigRef = create(() => const EngineConfig.empty());

// The [EngineConfig] instance available in the current zone.
EngineConfig get engineConfig => read(engineConfigRef);

class EngineConfig {
  EngineConfig({
    this.localEngineSrcPath,
    this.localEngine,
    this.localEngineHost,
  }) {
    final args = [localEngineSrcPath, localEngine, localEngineHost];
    final allArgsAreNull = args.every((arg) => arg == null);
    final allArgsAreNotNull = args.every((arg) => arg != null);
    if (!allArgsAreNull && !allArgsAreNotNull) {
      // Only some args were provided, this is invalid.
      throw ArgumentError(
        '''local-engine, local-engine-src, and local-engine-host must all be provided''',
      );
    }
  }

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
