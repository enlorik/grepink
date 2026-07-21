/// Returns a safe, display-ready version of a raw [providerName] string, or
/// `null` when the value is empty, unsafe, or credential-like.
///
/// Safety rules applied in order:
/// 1. Trim surrounding whitespace; empty → null.
/// 2. Reject values containing line breaks or control characters.
/// 3. Collapse runs of internal whitespace to a single space.
/// 4. Reject values longer than [_maxLength] characters (token-like strings).
/// 5. Reject values matching known credential patterns.
String? safeProviderDisplayName(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Reject line breaks and control characters (U+0000–U+001F, U+007F).
  if (trimmed.contains(RegExp(r'[\x00-\x1F\x7F]'))) return null;

  final collapsed = trimmed.replaceAll(RegExp(r'\s+'), ' ');

  // Reject values that are suspiciously long — real provider names are short.
  if (collapsed.length > _maxLength) return null;

  // Reject obvious credential-like values.
  final lower = collapsed.toLowerCase();
  if (_credentialPatterns.any((p) => lower.startsWith(p))) return null;
  if (_credentialSubstrings.any((s) => lower.contains(s))) return null;

  return collapsed;
}

const int _maxLength = 64;

const List<String> _credentialPatterns = [
  'sk-',
  'bearer ',
];

const List<String> _credentialSubstrings = [
  'api_key',
  'apikey',
];
