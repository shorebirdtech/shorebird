class PipelineContext {
  PipelineContext() : _data = {};

  PipelineContext._(Map<String, Object> data) : _data = data;

  final Map<String, Object> _data;

  PipelineContext provide<T extends Object?>(T Function() create) {
    final value = _data['$T'];
    if (value != null) {
      throw StateError(
        'Attempting to provide $T on a context that already contains a $T.',
      );
    }
    return PipelineContext._({..._data, '$T': create});
  }

  T read<T>() {
    final value = _data['$T'];
    if (value == null) {
      throw StateError('''
context.read<$T>() called with a context that does not contain a $T.
''');
    }

    return (value as T Function())();
  }
}
