import 'dart:convert';

Map<String, dynamic> exportJournal(List<String> entries) {
  return {
    'version': 1,
    'entries': entries,
  };
}

List<String> importJournal(String json) {
  final decoded = jsonDecode(json);
  if (decoded is Map<String, dynamic> && decoded['entries'] is List) {
    return (decoded['entries'] as List).map((e) => e.toString()).toList();
  }
  throw const FormatException('Invalid journal backup format');
}