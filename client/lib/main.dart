import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'util/backup.dart';
import 'sync/journal_sync.dart';
import 'services/narrator.dart' as narrator;
import 'state/journal.dart';

void main() {
  runApp(const UC4ERPGApp());
}

class SyncStatus {
  static final ValueNotifier<bool> busy = ValueNotifier(false);
  static DateTime? lastPull;
  static DateTime? lastPush;
}

class UC4ERPGApp extends StatelessWidget {
  const UC4ERPGApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UC4ERPG',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Pull on app start
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        SyncStatus.busy.value = true;
        final added = await JournalSyncService.pullAndMerge();
        SyncStatus.lastPull = DateTime.now();
        if (mounted && added > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pulled ' + added.toString() + ' new entries')),
          );
        }
      } catch (_) {
        // swallow for now
      } finally {
        SyncStatus.busy.value = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UC4ERPG')),
      drawer: const _AppDrawer(),
      body: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: SyncStatus.busy,
            builder: (context, busy, _) => busy
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SessionScreen()),
                    ),
                    child: const Text('Start Session'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const JournalScreen()),
                    ),
                    child: const Text('Open Journal'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncEnabled = false;
  bool _busy = false;
  String? _error;

  Future<void> _push() async {
    setState(() { _busy = true; _error = null; });
    try { await JournalSyncService.pushAll(); } catch (e) { _error = '$e'; }
    setState(() { _busy = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Enable Cloud Sync (Supabase)'),
              value: _syncEnabled,
              onChanged: (v) => setState(() => _syncEnabled = v),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy ? null : _push,
              child: _busy ? const Text('Syncing...') : const Text('Push Journal Now'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}