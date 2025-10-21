class JournalStore {
  static final JournalStore instance = JournalStore._();
  final List<String> _entries = <String>[];
  JournalStore._();

  List<String> get entries => List.unmodifiable(_entries);
  void addEntry(String text) => _entries.add(text);
}