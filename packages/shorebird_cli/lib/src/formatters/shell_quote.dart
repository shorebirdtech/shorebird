/// [value], single-quoted when a shell would split or expand it, so a
/// command built from it runs when pasted.
String shellQuote(String value) {
  if (RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}
