/// Uppercases the first character of [s]; empty-safe.
String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// Returns [s] with its characters in reverse order.
String reverse(String s) => String.fromCharCodes(s.runes.toList().reversed);
