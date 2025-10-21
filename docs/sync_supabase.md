# Supabase Sync Setup (Dev)

This enables optional cloud sync during development using the free Supabase tier.

Steps:
- Create a free project at https://app.supabase.com
- Get the Project URL and anon public API key (Settings â†’ API)
- Create table `journal_entries` with columns:
  - id uuid primary key default uuid_generate_v4()
  - text text not null
  - created_at timestamptz default now()
- In `client/lib/config.dart`, set:
  - `AppConfig.supabaseUrl`
  - `AppConfig.supabaseAnonKey`

Optional (recommended later): enable Row Level Security (RLS) and policy allowing anonymous users to read/write their own rows.

Run locally:
```
cd client
flutter pub get
flutter create .
flutter run
```

Use the Settings screen â†’ â€œPush Journal Nowâ€ to upload current entries.

You can override via flutter defines (no code edits):
``bash
flutter run --dart-define=SUPABASE_URL=https://qbewpsegsyqxqpcaolgv.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon>
``
