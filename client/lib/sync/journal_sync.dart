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
    final data = await client.from(table).select<List<Map<String, dynamic>>>('*').order('created_at');
    return data.map((e) => (e['text'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
  }
}