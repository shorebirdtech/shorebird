/// Extracts package/filter names from dorny/paths-filter blocks in a
/// workflow YAML file.
///
/// Looks for `filters: |` blocks and extracts the top-level keys
/// (which are the filter names that become job outputs).
Set<String> extractDornyFilterNames(String workflowContent) {
  final names = <String>{};

  final filterBlockRegex = RegExp(r'filters:\s*\|');
  for (final match in filterBlockRegex.allMatches(workflowContent)) {
    final afterBlock = workflowContent.substring(match.end);
    final lines = afterBlock.split('\n');

    // Detect the indentation of the first filter name.
    int? filterIndent;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final leadingSpaces = line.length - line.trimLeft().length;

      if (filterIndent == null) {
        // First non-blank line sets the expected indentation.
        final filterName = RegExp(r'^(\s+)(\w[\w-]*):\s*$').firstMatch(line);
        if (filterName == null) break;
        filterIndent = leadingSpaces;
        names.add(filterName.group(2)!);
        continue;
      }

      if (leadingSpaces == filterIndent) {
        final filterName = RegExp(r'^\s+(\w[\w-]*):\s*$').firstMatch(line);
        if (filterName != null) {
          names.add(filterName.group(1)!);
          continue;
        }
        break;
      }

      // Deeper indentation = path entries, skip them.
      if (leadingSpaces > filterIndent) continue;

      // Less indentation = left the filter block.
      break;
    }
  }

  return names;
}
