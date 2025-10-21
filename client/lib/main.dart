import 'package:flutter/material.dart';

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

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: const Center(child: Text('AI Narration Placeholder')),
    );
  }
}

class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: const Center(child: Text('Journal Entries Placeholder')),
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