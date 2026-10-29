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
