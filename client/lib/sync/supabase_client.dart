import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

class SupabaseSync {
  static bool _initialized = false;
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    if (AppConfig.supabaseUrl.isEmpty || AppConfig.supabaseAnonKey.isEmpty) {
      throw StateError('Supabase config missing. Set AppConfig.supabaseUrl and supabaseAnonKey.');
    }
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    // Anonymous sign-in for MVP
    await client.auth.signInAnonymously();
    _initialized = true;
  }
}
