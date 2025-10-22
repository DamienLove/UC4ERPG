import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'util/backup.dart';
import 'sync/journal_sync.dart';
import 'services/narrator.dart' as narrator;
import 'game/game.dart';
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
    final isTestBinding = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding');
    if (!kIsWeb && !isTestBinding) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UC4ERPG'), actions: const [SyncIcon()]),
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
                      MaterialPageRoute(builder: (_) => const GameScreen()),
                    ),
                    child: const Text('Play'),
                  ),
                  const SizedBox(height: 12),
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
      appBar: AppBar(title: const Text('Settings'), actions: const [SyncIcon()]),
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
class SyncIcon extends StatelessWidget {
  const SyncIcon({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncStatus.busy,
      builder: (context, busy, _) {
        final lastPush = SyncStatus.lastPush?.toLocal().toString() ?? 'never';
        final lastPull = SyncStatus.lastPull?.toLocal().toString() ?? 'never';
        final tip = 'Last push: ' + lastPush + '\nLast pull: ' + lastPull;
        return Tooltip(
          message: tip,
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: busy
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_done),
          ),
        );
      },
    );
  }
}
// Re-introduce missing UI classes
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _promptController = TextEditingController();
  final _seedController = TextEditingController(text: '42');
  String _output = '';

  void _generate() {
    final prompt = _promptController.text.trim();
    final seed = int.tryParse(_seedController.text.trim()) ?? 42;
    final text = narrator.generateNarration(prompt: prompt, seed: seed);
    setState(() => _output = text);
  }

  void _saveToJournal() {
    if (_output.isEmpty) return;
    JournalStore.instance.addEntry(_output);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to Journal')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session'), actions: const [SyncIcon()]),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              key: const Key('promptField'),
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('seedField'),
                    controller: _seedController,
                    decoration: const InputDecoration(
                      labelText: 'Seed',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _generate, child: const Text('Generate')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _saveToJournal, child: const Text('Save')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _output.isEmpty ? 'Your narration will appear here.' : _output,
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = JournalStore.instance.entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Journal'), actions: const [SyncIcon()]),
      body: entries.isEmpty
          ? const Center(child: Text('No entries yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 24),
              itemBuilder: (context, index) {
                final e = entries[entries.length - index - 1];
                return Text(e, style: const TextStyle(height: 1.4));
              },
            ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(child: Text('UC4ERPG')),
          ListTile(
            title: const Text('Home'),
            onTap: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
            ),
          ),
          ListTile(
            title: const Text('Play'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GameScreen()),
            ),
          ),
          ListTile(
            title: const Text('Session'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SessionScreen()),
            ),
          ),
          ListTile(
            title: const Text('Journal'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JournalScreen()),
            ),
          ),
          ListTile(
            title: const Text('Settings'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
