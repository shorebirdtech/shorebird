/// Extracts package/filter names from dorny/paths-filter blocks in a
/// workflow YAML file.
///
/// Looks for `filters: |` blocks and extracts the top-level keys
/// (which are the filter names that become job outputs).
Set<String> extractDornyFilterNames(String workflowContent) =>
    extractDornyFilters(workflowContent).keys.toSet();

/// Extracts each filter in the dorny/paths-filter blocks of a workflow
/// YAML file, mapped to its path patterns (`- packages/foo/**` gives
/// `packages/foo/**`). A filter named in more than one block gets the
/// patterns of all of them.
Map<String, Set<String>> extractDornyFilters(String workflowContent) {
  final filters = <String, Set<String>>{};

  final filterBlockRegex = RegExp(r'filters:\s*\|');
  final pathRegex = RegExp(r'''^\s+-\s+['"]?([^'"#\s]*)['"]?\s*(#.*)?$''');
  for (final match in filterBlockRegex.allMatches(workflowContent)) {
    final afterBlock = workflowContent.substring(match.end);
    final lines = afterBlock.split('\n');

    // Detect the indentation of the first filter name.
    int? filterIndent;
    Set<String>? current;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final leadingSpaces = line.length - line.trimLeft().length;

      if (filterIndent == null) {
        // First non-blank line sets the expected indentation.
        final filterName = RegExp(r'^(\s+)(\w[\w-]*):\s*$').firstMatch(line);
        if (filterName == null) break;
        filterIndent = leadingSpaces;
        current = filters.putIfAbsent(filterName.group(2)!, () => {});
        continue;
      }

      if (leadingSpaces == filterIndent) {
        final filterName = RegExp(r'^\s+(\w[\w-]*):\s*$').firstMatch(line);
        if (filterName != null) {
          current = filters.putIfAbsent(filterName.group(1)!, () => {});
          continue;
        }
        break;
      }

      // Deeper indentation = path entries.
      if (leadingSpaces > filterIndent) {
        final path = pathRegex.firstMatch(line)?.group(1);
        if (path != null && path.isNotEmpty) current!.add(path);
        continue;
      }

      // Less indentation = left the filter block.
      break;
    }
  }

  return filters;
}

/// Updates `dorny/paths-filter` `filters: |` blocks in [workflowContent]
/// in-place using [packageFilters] (keyed by package slug).
///
/// Only filter keys matching entries in [packageFilters] are rewritten;
/// non-package filter blocks (such as docs-only filters) and custom keys
/// are preserved untouched. When the workflow contains a single package
/// filter block, any newly discovered package in [packageFilters] not yet
/// present in the block is added in sorted order.
///
/// Returns `null` if [workflowContent] contains no `filters: |` block.
String? updateDornyFilters(
  String workflowContent,
  Map<String, List<String>> packageFilters,
) {
  final lines = workflowContent.split('\n');
  final headerRegex = RegExp(r'^(\s*)filters:\s*\|(\s*#.*)?$');
  final filterKeyRegex = RegExp(r'^(\s+)(\w[\w-]*):\s*(#.*)?$');
  final pathRegex = RegExp(r'''^\s+-\s+['"]?([^'"#\s]*)['"]?\s*(#.*)?$''');

  final blocks = <_ParsedFilterBlock>[];

  for (var i = 0; i < lines.length; i++) {
    final headerMatch = headerRegex.firstMatch(lines[i]);
    if (headerMatch == null) continue;
    final headerIndent = headerMatch.group(1)!.length;

    int? filterIndent;
    final blockStart = i + 1;
    var blockEnd = blockStart;
    final entries = <_FilterEntry>[];
    _FilterEntry? current;
    final pendingPrefixLines = <String>[];

    for (var j = blockStart; j < lines.length; j++) {
      final line = lines[j];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        current?.rawLines.add(line);
        continue;
      }

      final leading = line.length - line.trimLeft().length;
      if (leading <= headerIndent) break;

      if (filterIndent == null) {
        if (trimmed.startsWith('#')) {
          pendingPrefixLines.add(line);
          blockEnd = j + 1;
          continue;
        }
        final keyMatch = filterKeyRegex.firstMatch(line);
        if (keyMatch == null) break;
        filterIndent = leading;
        current = _FilterEntry(
          name: keyMatch.group(2)!,
          rawLines: [...pendingPrefixLines, line],
        );
        pendingPrefixLines.clear();
        entries.add(current);
        blockEnd = j + 1;
        continue;
      }

      if (leading < filterIndent) break;

      if (leading == filterIndent) {
        if (trimmed.startsWith('#')) {
          pendingPrefixLines.add(line);
          blockEnd = j + 1;
          continue;
        }
        final keyMatch = filterKeyRegex.firstMatch(line);
        if (keyMatch == null) break;
        current = _FilterEntry(
          name: keyMatch.group(2)!,
          rawLines: [...pendingPrefixLines, line],
        );
        pendingPrefixLines.clear();
        entries.add(current);
        blockEnd = j + 1;
        continue;
      }

      // Deeper indentation: path entry or comment inside current filter.
      current!.rawLines.add(line);
      final pathMatch = pathRegex.firstMatch(line);
      final path = pathMatch?.group(1);
      if (path != null && path.isNotEmpty) {
        current.existingPaths.add(path);
      }
      blockEnd = j + 1;
    }

    // Trim trailing blank lines from the last entry so blank lines
    // separating steps or jobs stay outside the replaced range.
    if (entries.isNotEmpty) {
      while (entries.last.rawLines.isNotEmpty &&
          entries.last.rawLines.last.trim().isEmpty) {
        entries.last.rawLines.removeLast();
      }
    }

    if (filterIndent != null) {
      blocks.add(
        _ParsedFilterBlock(
          startLine: blockStart,
          endLine: blockEnd,
          filterIndent: filterIndent,
          entries: entries,
        ),
      );
      i = blockEnd - 1;
    }
  }

  if (blocks.isEmpty) return null;

  final packageBlocks = [
    for (final block in blocks)
      if (block.entries.any((e) => packageFilters.containsKey(e.name))) block,
  ];
  final addMissingPackages = packageBlocks.length == 1;
  final coveredPackages = <String>{
    for (final block in packageBlocks)
      for (final entry in block.entries)
        if (packageFilters.containsKey(entry.name)) entry.name,
  };

  for (final block in packageBlocks.reversed) {
    final indent = ' ' * block.filterIndent;
    final pathIndent = ' ' * (block.filterIndent + 2);
    final updatedEntries = <String, List<String>>{};
    final order = <String>[];

    for (final entry in block.entries) {
      order.add(entry.name);
      final generated = packageFilters[entry.name];
      if (generated == null) {
        updatedEntries[entry.name] = entry.rawLines;
        continue;
      }
      final preservedGithubPaths = [
        for (final existing in entry.existingPaths)
          if (existing.startsWith('.github/') ||
              existing.startsWith('./.github/'))
            existing,
      ];
      final merged = <String>{
        ...generated,
        ...preservedGithubPaths,
      }.toList()..sort();
      updatedEntries[entry.name] = [
        '$indent${entry.name}:',
        for (final path in merged) '$pathIndent- $path',
      ];
    }

    if (addMissingPackages) {
      final missing = [
        for (final slug in packageFilters.keys)
          if (!coveredPackages.contains(slug)) slug,
      ]..sort();
      for (final slug in missing) {
        final paths = [...packageFilters[slug]!]..sort();
        updatedEntries[slug] = [
          '$indent$slug:',
          for (final path in paths) '$pathIndent- $path',
        ];
        order.add(slug);
      }
      // If all entries in this single block are package slugs, keep keys
      // sorted.
      if (block.entries.every((e) => packageFilters.containsKey(e.name))) {
        order.sort();
      }
    }

    final replacementLines = <String>[
      for (final name in order) ...updatedEntries[name]!,
    ];
    lines.replaceRange(block.startLine, block.endLine, replacementLines);
  }

  return lines.join('\n');
}

class _ParsedFilterBlock {
  _ParsedFilterBlock({
    required this.startLine,
    required this.endLine,
    required this.filterIndent,
    required this.entries,
  });

  final int startLine;
  final int endLine;
  final int filterIndent;
  final List<_FilterEntry> entries;
}

class _FilterEntry {
  _FilterEntry({
    required this.name,
    required this.rawLines,
  });

  final String name;
  final List<String> rawLines;
  final List<String> existingPaths = [];
}
