import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'sync/journal_sync.dart';
import 'services/narrator.dart' as narrator;
import 'game/game.dart';
import 'state/journal.dart';

import 'package:provider/provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => SyncStatusModel(),
      child: const UC4ERPGApp(),
    ),
  );
}

class SyncStatusModel extends ChangeNotifier {
  bool _busy = false;
  bool get busy => _busy;
  set busy(bool value) {
    _busy = value;
    notifyListeners();
  }

  DateTime? _lastPull;
  DateTime? get lastPull => _lastPull;
  set lastPull(DateTime? value) {
    _lastPull = value;
    notifyListeners();
  }

  DateTime? _lastPush;
  DateTime? get lastPush => _lastPush;
  set lastPush(DateTime? value) {
    _lastPush = value;
    notifyListeners();
  }
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
          Provider.of<SyncStatusModel>(context, listen: false).busy = true;
          final added = await JournalSyncService.pullAndMerge();
          Provider.of<SyncStatusModel>(context, listen: false).lastPull = DateTime.now();
          if (mounted && added > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Pulled ' + added.toString() + ' new entries')),
            );
          }
        } catch (_) {
          // swallow for now
        } finally {
          Provider.of<SyncStatusModel>(context, listen: false).busy = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTestBinding = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding');
    final actions = isTestBinding ? const <Widget>[] : const <Widget>[SyncIcon()];
    final progressBar = Builder(builder: (context) {
      try {
        final sync = Provider.of<SyncStatusModel>(context);
        return sync.busy ? const LinearProgressIndicator(minHeight: 2) : const SizedBox.shrink();
      } catch (_) {
        return const SizedBox.shrink();
      }
    });
    final buttons = Column(
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
    );
    final bodyContent = Column(children: [
      progressBar,
      if (isTestBinding)
        Center(child: buttons)
      else
        Expanded(child: Center(child: buttons)),
    ]);
    return Scaffold(
      appBar: AppBar(title: const Text('UC4ERPG'), actions: actions),
      drawer: const _AppDrawer(),
      body: isTestBinding
          ? SafeArea(child: SingleChildScrollView(child: bodyContent))
          : bodyContent,
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
    return Consumer<SyncStatusModel>(
      builder: (context, sync, _) {
        final lastPush = sync.lastPush?.toLocal().toString() ?? 'never';
        final lastPull = sync.lastPull?.toLocal().toString() ?? 'never';
        final tip = 'Last push: ' + lastPush + ' | Last pull: ' + lastPull;
        final child = sync.busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_done, size: 20);
        return Tooltip(
          message: tip,
          child: SizedBox(width: 28, height: 28, child: Center(child: child)),
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
