// DO NOT commit non-public keys here. Supabase anon key is safe for client use.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://qbewpsegsyqxqpcaolgv.supabase.co');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFiZXdwc2Vnc3lxeHFwY2FvbGd2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjEwNzc0NDMsImV4cCI6MjA3NjY1MzQ0M30.MFO0I1VZVw7nSK5sC7rqx-LTCNItYtEDAcSw0i-PdLk');
}