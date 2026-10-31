/// [count] and [noun], with an "s" unless [count] is one: `1 app`,
/// `3 apps`.
String formatCount(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';
