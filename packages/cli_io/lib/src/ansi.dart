// ANSI SGR escape codes. See https://en.wikipedia.org/wiki/ANSI_escape_code.
//
// The color and style constants below are self-documenting; their names
// describe their effect.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io' as io;

const _ansiOverrideKey = #cli_io.ansi_output_enabled;

/// Whether ANSI escape sequences are emitted by [AnsiCode.wrap].
///
/// Defaults to `stdout.supportsAnsiEscapes`. Override with
/// [overrideAnsiOutput] for tests or to force-enable in non-tty environments.
/// `stdout` here respects `IOOverrides.current`, so test fakes are honored.
bool get ansiOutputEnabled =>
    Zone.current[_ansiOverrideKey] as bool? ?? io.stdout.supportsAnsiEscapes;

/// Runs [body] with [ansiOutputEnabled] forced to [enabled] for the duration
/// of the zone (and any zones forked from it).
T overrideAnsiOutput<T>({required bool enabled, required T Function() body}) =>
    runZoned(body, zoneValues: {_ansiOverrideKey: enabled});

/// An ANSI SGR (Select Graphic Rendition) escape code — a foreground color,
/// background color, or text style.
class AnsiCode {
  /// Create an [AnsiCode] with the SGR [code] that enables it and the [reset]
  /// code that disables it.
  const AnsiCode(this.code, this.reset);

  /// The numeric SGR code that enables this style.
  final int code;

  /// The numeric SGR code that disables this style.
  final int reset;

  /// Wraps [value] with this code's open and close escape sequences.
  ///
  /// Returns [value] unchanged if it is null or empty, or if ANSI output is
  /// disabled (unless [forScript] is true).
  String? wrap(String? value, {bool? forScript}) {
    if (value == null || value.isEmpty) return value;
    final emit = forScript ?? ansiOutputEnabled;
    if (!emit) return value;
    return '\x1B[${code}m$value\x1B[${reset}m';
  }
}

// Foreground colors used by Shorebird CLI tooling.
const AnsiCode red = AnsiCode(31, 39);
const AnsiCode green = AnsiCode(32, 39);
const AnsiCode yellow = AnsiCode(33, 39);
const AnsiCode cyan = AnsiCode(36, 39);
const AnsiCode darkGray = AnsiCode(90, 39);
const AnsiCode lightRed = AnsiCode(91, 39);
const AnsiCode lightGreen = AnsiCode(92, 39);
const AnsiCode lightYellow = AnsiCode(93, 39);
const AnsiCode lightBlue = AnsiCode(94, 39);
const AnsiCode lightCyan = AnsiCode(96, 39);

// Text styles used by Shorebird CLI tooling.
const AnsiCode styleBold = AnsiCode(1, 22);
const AnsiCode styleDim = AnsiCode(2, 22);
const AnsiCode styleUnderlined = AnsiCode(4, 24);
