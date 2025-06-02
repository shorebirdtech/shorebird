import 'package:equatable/equatable.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to an [EngineConfig] instance.
final ScopedRef<EngineConfig> engineConfigRef = create(
  () => const EngineConfig.empty(),
);

/// The [EngineConfig] instance available in the current zone.
EngineConfig get engineConfig => read(engineConfigRef);

/// {@template engine_config}
/// An object that contains a local engine configuration.
/// {@endtemplate}
class EngineConfig extends Equatable {
  /// {@macro engine_config}
  const EngineConfig({
    required this.localEngineSrcPath,
    required this.localEngine,
    required this.localEngineHost,
  });

  /// An empty [EngineConfig] instance.
  const EngineConfig.empty()
    : localEngineSrcPath = null,
      localEngine = null,
      localEngineHost = null;

  /// The path to the local engine source.
  final String? localEngineSrcPath;

  /// The local engine name.
  final String? localEngine;

  /// The local engine host.
  final String? localEngineHost;

  @override
  String toString() {
    return '''EngineConfig(localEngineSrcPath: $localEngineSrcPath, localEngine: $localEngine, localEngineHost: $localEngineHost)''';
  }

  @override
  List<Object?> get props => [localEngineSrcPath, localEngine, localEngineHost];
}
