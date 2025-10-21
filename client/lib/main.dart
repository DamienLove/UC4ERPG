import 'package:flutter/material.dart';
import 'services/narrator.dart' as narrator;
import 'state/journal.dart';

void main() {
  runApp(const UC4ERPGApp());
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UC4ERPG')),
      drawer: const _AppDrawer(),
      body: Center(
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
    );
  }
}

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
      appBar: AppBar(title: const Text('Session')),
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
      appBar: AppBar(title: const Text('Journal')),
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
        ],
      ),
    );
  }
}