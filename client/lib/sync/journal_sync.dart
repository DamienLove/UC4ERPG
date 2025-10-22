import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/journal.dart';
import 'supabase_client.dart';

class JournalSyncService {
  static const table = 'journal_entries';

  static Future<void> pushAll() async {
    await SupabaseSync.ensureInitialized();
    final client = SupabaseSync.client;
    final entries = JournalStore.instance.entries;
    if (entries.isEmpty) return;
    final rows = entries.map((e) => {
          'text': e,
          'created_at': DateTime.now().toIso8601String(),
        });
    await client.from(table).upsert(rows.toList());
  }

  static Future<List<String>> pullAll() async {
    await SupabaseSync.ensureInitialized();
    final client = SupabaseSync.client;
    final data = await client.from(table).select('*').order('created_at');
    final list = (data as List)
        .map((e) => (e['text'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return list;
  }

  static Future<int> pullAndMerge() async {
    final remote = await pullAll();
    var added = 0;
    for (final e in remote) {
      if (!JournalStore.instance.entries.contains(e)) {
        JournalStore.instance.addEntry(e);
        added++;
      }
    }
    return added;
  }
}
