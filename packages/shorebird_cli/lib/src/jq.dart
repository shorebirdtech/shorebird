import 'dart:convert';

import 'package:collection/collection.dart';

/// {@template jq_exception}
/// A jq expression that could not be parsed or evaluated.
/// {@endtemplate}
class JqException implements Exception {
  /// {@macro jq_exception}
  const JqException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

typedef _Filter = List<Object?> Function(Object? input);

/// {@template jq_query}
/// A parsed expression in a small subset of jq, the language `gh api --jq`
/// takes.
///
/// Supported: `.`, `.a.b`, `."a"`, `.[]`, `.[n]`, `.["a"]`, the `?` suffix,
/// `|`, `,`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not`, `{...}`
/// and `[...]` construction, string interpolation (`"\(.a)"`), literals,
/// and the functions `length`, `keys`, `map(f)`, `select(f)`, `empty`,
/// `first`, `first(f)`, `last`, `sort_by(f)`, `unique`, `unique_by(f)`,
/// `join(sep)`, `to_entries`, `from_entries` and `with_entries(f)`.
/// Anything else is rejected with a [JqException] that names it.
/// {@endtemplate}
class JqQuery {
  /// Parses [source], throwing a [JqException] if it is not in the subset.
  factory JqQuery.parse(String source) => JqQuery._(_Parser(source).parse());

  JqQuery._(this._filter);

  final _Filter _filter;

  /// The outputs of this query for [input], a decoded JSON value.
  List<Object?> evaluate(Object? input) => _filter(input);

  /// [value] as jq prints it with `--raw-output`, as `gh api --jq` does:
  /// strings as-is, everything else as JSON (indented by [indent], if any).
  static String format(Object? value, {String indent = ''}) {
    if (value is String) return value;
    return indent.isEmpty
        ? jsonEncode(value)
        : JsonEncoder.withIndent(indent).convert(value);
  }
}

class _Parser {
  _Parser(this._source);

  final String _source;
  var _pos = 0;

  static final _identifier = RegExp('[A-Za-z_][A-Za-z0-9_]*');
  static final _number = RegExp(r'-?\d+(\.\d+)?([eE][+-]?\d+)?');

  _Filter parse() {
    final filter = _pipe();
    _skipSpace();
    if (_pos < _source.length) _unsupported();
    return filter;
  }

  Never _unsupported() {
    final rest = _source.substring(_pos);
    final shown = rest.length > 20 ? '${rest.substring(0, 20)}...' : rest;
    throw JqException(
      'unsupported or invalid jq at position ${_pos + 1}: "$shown"',
    );
  }

  void _skipSpace() {
    while (_pos < _source.length && _source[_pos].trim().isEmpty) {
      _pos++;
    }
  }

  bool _peek(String token) {
    _skipSpace();
    return _source.startsWith(token, _pos);
  }

  bool _eat(String token) {
    if (!_peek(token)) return false;
    _pos += token.length;
    return true;
  }

  void _expect(String token) {
    if (!_eat(token)) _unsupported();
  }

  String? _matchAt(RegExp pattern) {
    final match = pattern.matchAsPrefix(_source, _pos);
    if (match == null) return null;
    _pos = match.end;
    return match[0];
  }

  /// Eats [word] if it is the next whole identifier.
  bool _eatWord(String word) {
    _skipSpace();
    final match = _identifier.matchAsPrefix(_source, _pos);
    if (match?[0] != word) return false;
    _pos = match!.end;
    return true;
  }

  _Filter _pipe() {
    var filter = _comma();
    while (_eat('|')) {
      final left = filter;
      final right = _comma();
      filter = (input) => [for (final v in left(input)) ...right(v)];
    }
    return filter;
  }

  _Filter _comma() {
    var filter = _or();
    while (_eat(',')) {
      final left = filter;
      final right = _or();
      filter = (input) => [...left(input), ...right(input)];
    }
    return filter;
  }

  _Filter _or() {
    var filter = _and();
    while (_eatWord('or')) {
      final left = filter;
      final right = _and();
      filter = (input) => [
        for (final l in left(input))
          if (_isTruthy(l)) true else ...right(input).map(_isTruthy),
      ];
    }
    return filter;
  }

  _Filter _and() {
    var filter = _comparison();
    while (_eatWord('and')) {
      final left = filter;
      final right = _comparison();
      filter = (input) => [
        for (final l in left(input))
          if (!_isTruthy(l)) false else ...right(input).map(_isTruthy),
      ];
    }
    return filter;
  }

  _Filter _comparison() {
    final left = _postfix();
    for (final op in ['==', '!=', '<=', '>=', '<', '>']) {
      if (!_eat(op)) continue;
      final right = _postfix();
      return (input) => [
        for (final l in left(input))
          for (final r in right(input)) _compareWith(op, l, r),
      ];
    }
    return left;
  }

  _Filter _postfix() {
    var filter = _primary();
    while (true) {
      if (_peek('[')) {
        filter = _indexSuffix(filter);
      } else if (_peek('.') && !_peek('..')) {
        _pos++;
        filter = _fieldAccess(filter);
      } else if (_eat('?')) {
        final inner = filter;
        filter = (input) {
          try {
            return inner(input);
          } on JqException {
            return const [];
          }
        };
      } else {
        return filter;
      }
    }
  }

  /// `.name` or `."name"` applied to [target]'s outputs, with the `.`
  /// already consumed.
  _Filter _fieldAccess(_Filter target) {
    if (_source.startsWith('"', _pos)) {
      final key = _string();
      return (input) => [
        for (final v in target(input))
          for (final k in key(input)) _index(v, k),
      ];
    }
    final name = _matchAt(_identifier) ?? _unsupported();
    return (input) => [for (final v in target(input)) _index(v, name)];
  }

  /// `[]` or `[expr]` applied to [target]'s outputs.
  _Filter _indexSuffix(_Filter target) {
    _expect('[');
    if (_eat(']')) {
      return (input) => [for (final v in target(input)) ..._iterate(v)];
    }
    final key = _pipe();
    _expect(']');
    return (input) => [
      for (final v in target(input))
        for (final k in key(input)) _index(v, k),
    ];
  }

  _Filter _primary() {
    _skipSpace();
    if (_pos >= _source.length) _unsupported();
    final char = _source[_pos];
    if (char == '.') {
      if (_source.startsWith('..', _pos)) _unsupported();
      _pos++;
      if (_source.startsWith('"', _pos) ||
          _identifier.matchAsPrefix(_source, _pos) != null) {
        return _fieldAccess((input) => [input]);
      }
      return (input) => [input];
    }
    if (char == '"') return _string();
    if (char == '(') {
      _pos++;
      final inner = _pipe();
      _expect(')');
      return inner;
    }
    if (char == '[') {
      _pos++;
      if (_eat(']')) return (input) => [<Object?>[]];
      final inner = _pipe();
      _expect(']');
      return (input) => [inner(input)];
    }
    if (char == '{') return _object();
    final number = _matchAt(_number);
    if (number != null) {
      final value = num.parse(number);
      return (input) => [value];
    }
    return _function();
  }

  _Filter _function() {
    final name = _matchAt(_identifier) ?? _unsupported();
    switch (name) {
      case 'true' || 'false' || 'null':
        final value = name == 'null' ? null : name == 'true';
        return (input) => [value];
      case 'not':
        return (input) => [!_isTruthy(input)];
      case 'empty':
        return (input) => const [];
      case 'length':
        return (input) => [_length(input)];
      case 'keys':
        return (input) => [_keys(input)];
      case 'map':
        final f = _argument();
        return (input) => [
          [for (final v in _iterate(input)) ...f(v)],
        ];
      case 'select':
        final f = _argument();
        return (input) => [
          for (final v in f(input))
            if (_isTruthy(v)) input,
        ];
      case 'first' when _peek('('):
        final f = _argument();
        return (input) => f(input).take(1).toList();
      case 'first':
        return (input) => [_index(input, 0)];
      case 'last':
        return (input) => [_index(input, -1)];
      case 'sort_by':
        final f = _argument();
        return (input) => [_sortBy(input, f)];
      case 'unique':
        return (input) => [
          _uniqueBy(input, (v) => [v]),
        ];
      case 'unique_by':
        final f = _argument();
        return (input) => [_uniqueBy(input, f)];
      case 'join':
        final separator = _argument();
        return (input) => [
          for (final s in separator(input)) _join(input, s),
        ];
      case 'to_entries':
        return (input) => [_toEntries(input)];
      case 'from_entries':
        return (input) => [_fromEntries(input)];
      case 'with_entries':
        final f = _argument();
        return (input) => [
          _fromEntries([
            for (final entry in _toEntries(input)) ...f(entry),
          ]),
        ];
    }
    throw JqException('unsupported jq function or keyword "$name"');
  }

  _Filter _argument() {
    _expect('(');
    final f = _pipe();
    _expect(')');
    return f;
  }

  _Filter _object() {
    _expect('{');
    final entries = <(_Filter, _Filter)>[];
    while (!_eat('}')) {
      if (entries.isNotEmpty) _expect(',');
      _skipSpace();
      final _Filter key;
      final String? name;
      if (_source.startsWith('"', _pos)) {
        key = _string();
        name = null;
      } else if (_eat('(')) {
        key = _pipe();
        _expect(')');
        name = null;
      } else {
        final identifier = _matchAt(_identifier) ?? _unsupported();
        key = (input) => [identifier];
        name = identifier;
      }
      if (_eat(':')) {
        entries.add((key, _or()));
      } else if (name != null) {
        // `{a}` is shorthand for `{a: .a}`.
        entries.add((key, (input) => [_index(input, name)]));
      } else {
        _unsupported();
      }
    }
    return (input) {
      var objects = [<String, Object?>{}];
      for (final (key, value) in entries) {
        objects = [
          for (final object in objects)
            for (final k in key(input))
              for (final v in value(input)) {...object, _objectKey(k): v},
        ];
      }
      return objects;
    };
  }

  /// A string literal, with `\(...)` interpolation.
  _Filter _string() {
    _expect('"');
    final parts = <Object>[]; // String or _Filter
    final literal = StringBuffer();
    while (true) {
      if (_pos >= _source.length) {
        throw const JqException('unterminated string in jq expression');
      }
      final char = _source[_pos++];
      if (char == '"') break;
      if (char != r'\') {
        literal.write(char);
        continue;
      }
      if (_pos >= _source.length) _unsupported();
      final escape = _source[_pos++];
      if (escape == '(') {
        parts.add(literal.toString());
        literal.clear();
        parts.add(_pipe());
        _expect(')');
        continue;
      }
      literal.write(switch (escape) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        '"' || r'\' || '/' => escape,
        _ => throw JqException('unsupported escape "\\$escape" in jq string'),
      });
    }
    parts.add(literal.toString());
    return (input) {
      var strings = [''];
      for (final part in parts) {
        final values = part is String
            ? [part]
            : [
                for (final v in (part as _Filter)(input)) JqQuery.format(v),
              ];
        strings = [
          for (final s in strings)
            for (final v in values) '$s$v',
        ];
      }
      return strings;
    };
  }
}

bool _isTruthy(Object? value) => value != null && value != false;

String _typeName(Object? value) => switch (value) {
  null => 'null',
  bool() => 'boolean',
  num() => 'number',
  String() => 'string',
  List() => 'array',
  _ => 'object',
};

String _objectKey(Object? key) {
  if (key is String) return key;
  throw JqException('object keys must be strings, got ${_typeName(key)}');
}

Object? _index(Object? value, Object? key) {
  if (value == null) return null;
  if (value is Map && key is String) return value[key];
  if (value is List && key is num) {
    final i = key.floor();
    final index = i < 0 ? value.length + i : i;
    return index >= 0 && index < value.length ? value[index] : null;
  }
  final keyText = key is String ? '"$key"' : _typeName(key);
  throw JqException('Cannot index ${_typeName(value)} with $keyText');
}

Iterable<Object?> _iterate(Object? value) => switch (value) {
  List() => value,
  Map() => value.values,
  _ => throw JqException('Cannot iterate over ${_typeName(value)}'),
};

num _length(Object? value) => switch (value) {
  null => 0,
  num() => value.abs(),
  String() => value.runes.length,
  List() => value.length,
  Map() => value.length,
  _ => throw JqException('${_typeName(value)} ($value) has no length'),
};

List<Object?> _keys(Object? value) => switch (value) {
  Map() => value.keys.cast<String>().toList()..sort(),
  List() => [for (var i = 0; i < value.length; i++) i],
  _ => throw JqException('${_typeName(value)} has no keys'),
};

bool _compareWith(String op, Object? left, Object? right) => switch (op) {
  '==' => const DeepCollectionEquality().equals(left, right),
  '!=' => !const DeepCollectionEquality().equals(left, right),
  '<' => _compare(left, right) < 0,
  '<=' => _compare(left, right) <= 0,
  '>' => _compare(left, right) > 0,
  _ => _compare(left, right) >= 0,
};

/// jq's ordering: null < false < true < numbers < strings < arrays <
/// objects.
int _compare(Object? a, Object? b) {
  int rank(Object? v) => switch (v) {
    null => 0,
    false => 1,
    true => 2,
    num() => 3,
    String() => 4,
    List() => 5,
    _ => 6,
  };
  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is List && b is List) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      final byElement = _compare(a[i], b[i]);
      if (byElement != 0) return byElement;
    }
    return a.length.compareTo(b.length);
  }
  // Objects: by their sorted keys first, then by the values of those keys.
  final aMap = a! as Map;
  final bMap = b! as Map;
  final aKeys = aMap.keys.cast<String>().toList()..sort();
  final bKeys = bMap.keys.cast<String>().toList()..sort();
  final byKeys = _compare(aKeys, bKeys);
  if (byKeys != 0) return byKeys;
  for (final key in aKeys) {
    final byValue = _compare(aMap[key], bMap[key]);
    if (byValue != 0) return byValue;
  }
  return 0;
}

List<Object?> _sortable(Object? value) {
  if (value is List) return value;
  throw JqException(
    '${_typeName(value)} (${jsonEncode(value)}) cannot be sorted, as it is '
    'not an array',
  );
}

/// [value] sorted by the outputs of [f] on each element, keeping the order
/// of elements that compare equal, as jq's `sort_by` does.
List<Object?> _sortBy(Object? value, _Filter f) => [
  for (final (_, v) in _sortedByKey(value, f)) v,
];

/// The first element of [value] for each distinct output of [f], sorted by
/// those outputs, as jq's `unique_by` does.
List<Object?> _uniqueBy(Object? value, _Filter f) {
  final keyed = _sortedByKey(value, f);
  return [
    for (var i = 0; i < keyed.length; i++)
      if (i == 0 || _compare(keyed[i - 1].$1, keyed[i].$1) != 0) keyed[i].$2,
  ];
}

/// Each element of [value] paired with the outputs of [f] on it, stably
/// sorted by those outputs.
List<(List<Object?>, Object?)> _sortedByKey(Object? value, _Filter f) {
  final keyed = [for (final v in _sortable(value)) (f(v), v)];
  mergeSort(keyed, compare: (a, b) => _compare(a.$1, b.$1));
  return keyed;
}

String _join(Object? value, Object? separator) {
  if (separator is! String) {
    throw JqException(
      'cannot join with ${_typeName(separator)} (${jsonEncode(separator)})',
    );
  }
  return [
    for (final v in _iterate(value))
      switch (v) {
        null => '',
        String() || num() || bool() => '$v',
        _ => throw JqException('Cannot join with ${_typeName(v)}'),
      },
  ].join(separator);
}

List<Object?> _toEntries(Object? value) {
  if (value is! Map) throw JqException('${_typeName(value)} has no keys');
  return [
    for (final MapEntry(:key, :value) in value.entries)
      {'key': key, 'value': value},
  ];
}

/// jq's `from_entries`: each entry's key is the first of `key`, `name`,
/// `Name`, `K` and `Key` that is not null or false, and its value is `value`
/// if present, otherwise `Value`.
Map<String, Object?> _fromEntries(Object? value) {
  final result = <String, Object?>{};
  for (final entry in _iterate(value)) {
    final key = [
      'key',
      'name',
      'Name',
      'K',
      'Key',
    ].map((name) => _index(entry, name)).firstWhereOrNull(_isTruthy);
    if (key is! String) {
      throw JqException(
        'Cannot use ${_typeName(key)} (${jsonEncode(key)}) as object key',
      );
    }
    final hasValue = entry is Map && entry.containsKey('value');
    result[key] = _index(entry, hasValue ? 'value' : 'Value');
  }
  return result;
}
