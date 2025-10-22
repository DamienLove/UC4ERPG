# Repository Guidelines

## Project Structure & Modules
- `client/` – Flutter app (Dart): `lib/` sources, `test/` widget/unit tests, `assets/`.
- `supabase/` – SQL schema + RLS policies (`schema.sql`).
- `docs/` – Architecture, product notes, book outline.
- `.github/workflows/` – CI (analyze/tests, Pages deploy, Supabase smoke test).

## Build, Test, and Development
- Run web locally: `cd client && flutter run -d chrome`
- Analyze code: `cd client && flutter analyze`
- Format code: `cd client && dart format .`
- Tests: `cd client && flutter test`
- Web release build: `cd client && flutter build web --release --base-href /UC4ERPG/`

## Coding Style & Naming
- Dart/Flutter defaults; 2‑space indentation.
- Files: `snake_case.dart`; Types: `PascalCase`; members/vars: `lowerCamelCase`.
- Prefer string interpolation; remove unused imports.
- Linting via `flutter analyze`; docs use markdownlint in CI.

## Testing Guidelines
- Place tests under `client/test/` with `*_test.dart`.
- Use `package:flutter_test`; keep tests deterministic (no network).
- For sync logic, mock Supabase clients; cover empty data, duplicates, and errors.
- Optional coverage: `flutter test --coverage` outputs `coverage/`.

## Commit & Pull Request Guidelines
- Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `test:`.
- Small, descriptive commits; reference issues (`Fixes #123`).
- PRs include description, linked issue, screenshots/GIFs for UI, and passing CI.
- Keep changes minimal and focused; avoid unrelated refactors.

## Security & Configuration Tips
- Never commit secrets. Store `SUPABASE_URL`/`SUPABASE_ANON_KEY` in GitHub Actions Secrets; pass via env or `--dart-define`.
- Supabase: enable Anonymous provider; SQL is idempotent.
- GitHub Pages uses project URL; for a custom domain add `CNAME` and switch `--base-href /`.
- Windows desktop builds need Developer Mode (symlinks) and VS C++ workload; web/mobile are primary targets.

## Agent Notes
- Follow these rules across the repo root.
- Prefer surgical changes; align with existing structure and CI. Document assumptions in PRs.
