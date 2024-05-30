extension NullOrEmtpy on String? {
  /// Returns `true` if this string is null or empty.
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}

extension AnsiEscapes on String {
  /// Removes ANSI escape codes (usually the result of a lightCyan.wrap or
  /// similar) from this string. Used to clean up
  String removeAnsiEscapes() {
    // Convert ansi escape links to markdown links. This assumes the string is
    // well-formed and that there are no nested links.
    //
    // Links are in the form of '\x1B]8;;<uri>\x1B\\<text>\x1B]8;;\x1B\\'
    //
    // See https://github.com/felangel/mason/blob/38a525b0607d8723df3b5b3fcc2c087efd9e1c93/packages/mason_logger/lib/src/link.dart
    final hyperlinkRegex = RegExp(
      r'\x1B\]8;;(.+)\x1B\\(.+)\x1B\]8;;\x1B\\',
    );
    final ansiEscapeRegex = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');

    // Replace all links with markdown links
    // Remove all other ANSI escape codes
    return replaceAllMapped(
      hyperlinkRegex,
      (match) => '[${match.group(2)!}](${match.group(1)!})',
    ).replaceAll(ansiEscapeRegex, '');
  }
}
